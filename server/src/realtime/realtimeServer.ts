import websocketPlugin from "@fastify/websocket";
import type { FastifyInstance } from "fastify";
import type {
  AgentHeartbeatMessage,
  AgentHelloMessage,
  AgentResultMessage,
} from "../types/protocol";
import type { Database } from "../db/database";
import { CommandRouter } from "../router/commandRouter";
import { DeviceRegistry } from "./deviceRegistry";
import { log } from "../utils/logger";

interface RealtimeDeps {
  db: Database;
  registry: DeviceRegistry;
  router: CommandRouter;
  wsAuthTimeoutMs: number;
  wsPingIntervalMs: number;
  wsMaxMessageBytes: number;
}

interface WsLike {
  send(data: string): void;
  ping?(data?: Buffer | string, cb?: (error?: Error) => void): void;
  close(code?: number, reason?: Buffer | string): void;
  on(event: "message", listener: (data: unknown) => void): void;
  on(event: "close", listener: () => void): void;
  on(event: "error", listener: (error: unknown) => void): void;
  readyState?: number;
  OPEN?: number;
}

function isWsLike(value: unknown): value is WsLike {
  if (!value || typeof value !== "object") {
    return false;
  }

  const candidate = value as Record<string, unknown>;
  return (
    typeof candidate.send === "function" &&
    typeof candidate.close === "function" &&
    typeof candidate.on === "function"
  );
}

function resolveSocket(connection: unknown): WsLike | null {
  if (isWsLike(connection)) {
    return connection;
  }

  if (!connection || typeof connection !== "object") {
    return null;
  }

  const maybeSocket = (connection as { socket?: unknown }).socket;
  if (isWsLike(maybeSocket)) {
    return maybeSocket;
  }

  return null;
}

function isSocketOpen(socket: WsLike): boolean {
  if (typeof socket.readyState !== "number") {
    return true;
  }

  const openState = typeof socket.OPEN === "number" ? socket.OPEN : 1;
  return socket.readyState === openState;
}

function closeQuietly(socket: WsLike, code: number, reason: string): void {
  try {
    socket.close(code, reason);
  } catch {
    // socket already closing/closed
  }
}

function parseJson(input: unknown): Record<string, unknown> | null {
  const text = typeof input === "string" ? input : input instanceof Buffer ? input.toString("utf8") : "";
  if (!text) {
    return null;
  }

  try {
    const parsed = JSON.parse(text) as unknown;
    if (typeof parsed !== "object" || parsed === null) {
      return null;
    }

    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

function payloadSizeBytes(input: unknown): number {
  if (typeof input === "string") {
    return Buffer.byteLength(input, "utf8");
  }

  if (input instanceof Buffer) {
    return input.byteLength;
  }

  return 0;
}

function safeSendJson(socket: WsLike, payload: Record<string, unknown>): void {
  if (!isSocketOpen(socket)) {
    return;
  }

  try {
    socket.send(JSON.stringify(payload));
  } catch {
    // ignore send errors here, read/write loop will close eventually
  }
}

function isString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

function isValidDeviceId(value: string): boolean {
  return /^[a-z0-9_-]{2,32}$/.test(value);
}

function asHelloMessage(value: Record<string, unknown>): AgentHelloMessage | null {
  if (value.kind !== "hello") {
    return null;
  }

  if (
    !isString(value.device_id) ||
    !isString(value.token) ||
    !isString(value.version) ||
    !isString(value.hostname) ||
    !isString(value.username) ||
    !isStringArray(value.capabilities)
  ) {
    return null;
  }

  if (!isValidDeviceId(value.device_id)) {
    return null;
  }

  if (value.token.length > 256 || value.version.length > 64) {
    return null;
  }

  return {
    kind: "hello",
    device_id: value.device_id,
    token: value.token,
    version: value.version,
    hostname: value.hostname,
    username: value.username,
    capabilities: value.capabilities,
  };
}

function asHeartbeatMessage(value: Record<string, unknown>): AgentHeartbeatMessage | null {
  if (value.kind !== "heartbeat") {
    return null;
  }

  if (!isString(value.device_id) || !isString(value.sent_at)) {
    return null;
  }

  return {
    kind: "heartbeat",
    device_id: value.device_id,
    sent_at: value.sent_at,
  };
}

function asResultMessage(value: Record<string, unknown>): AgentResultMessage | null {
  if (value.kind !== "result") {
    return null;
  }

  if (
    !isString(value.request_id) ||
    !isString(value.device_id) ||
    typeof value.ok !== "boolean" ||
    !isString(value.message) ||
    !isString(value.completed_at)
  ) {
    return null;
  }

  if (value.error_code !== undefined && typeof value.error_code !== "string") {
    return null;
  }

  if (value.version !== undefined && typeof value.version !== "string") {
    return null;
  }

  return {
    kind: "result",
    request_id: value.request_id,
    device_id: value.device_id,
    ok: value.ok,
    message: value.message,
    error_code: value.error_code,
    completed_at: value.completed_at,
    version: value.version,
  };
}

export async function registerRealtime(server: FastifyInstance, deps: RealtimeDeps): Promise<void> {
  await server.register(websocketPlugin);

  server.get("/ws/agent", { websocket: true }, (connection) => {
    const socket = resolveSocket(connection);
    if (!socket) {
      log("error", "Failed to resolve websocket socket instance");
      return;
    }

    let authenticated = false;
    let activeDeviceId: string | null = null;
    let pingTimer: NodeJS.Timeout | null = null;

    const authTimer = setTimeout(() => {
      if (!authenticated) {
        closeQuietly(socket, 4001, "Authentication timeout");
      }
    }, deps.wsAuthTimeoutMs);

    authTimer.unref?.();

    socket.on("message", (raw) => {
      try {
        if (payloadSizeBytes(raw) > deps.wsMaxMessageBytes) {
          closeQuietly(socket, 1009, "Message too large");
          return;
        }

        const payload = parseJson(raw);
        if (!payload) {
          closeQuietly(socket, 4004, "Invalid JSON message");
          return;
        }

        if (!authenticated) {
          const hello = asHelloMessage(payload);
          if (!hello) {
            closeQuietly(socket, 4003, "Expected hello handshake");
            return;
          }

          const validToken = deps.db.isValidDeviceToken(hello.device_id, hello.token);
          if (!validToken) {
            closeQuietly(socket, 4003, "Invalid device token");
            return;
          }

          authenticated = true;
          activeDeviceId = hello.device_id;
          clearTimeout(authTimer);

          deps.registry.register({
            deviceId: hello.device_id,
            socket,
            version: hello.version,
            hostname: hello.hostname,
            username: hello.username,
            capabilities: hello.capabilities,
          });

          deps.db.markDeviceOnline({
            deviceId: hello.device_id,
            version: hello.version,
            hostname: hello.hostname,
            username: hello.username,
            capabilities: hello.capabilities,
          });

          safeSendJson(socket, {
            kind: "hello_ack",
            server_time: new Date().toISOString(),
          });

          pingTimer = setInterval(() => {
            if (!isSocketOpen(socket)) {
              return;
            }

            if (typeof socket.ping !== "function") {
              return;
            }

            try {
              socket.ping();
            } catch {
              closeQuietly(socket, 1011, "Ping failure");
            }
          }, deps.wsPingIntervalMs);

          pingTimer.unref?.();

          log("info", "Agent connected", {
            device_id: hello.device_id,
            version: hello.version,
            hostname: hello.hostname,
          });
          return;
        }

        if (!activeDeviceId) {
          closeQuietly(socket, 4003, "Authentication state error");
          return;
        }

        const heartbeat = asHeartbeatMessage(payload);
        if (heartbeat) {
          if (heartbeat.device_id !== activeDeviceId) {
            closeQuietly(socket, 4003, "Device mismatch");
            return;
          }

          deps.registry.markHeartbeat(activeDeviceId);
          deps.db.touchHeartbeat(activeDeviceId);
          safeSendJson(socket, { kind: "heartbeat_ack", server_time: new Date().toISOString() });
          return;
        }

        const result = asResultMessage(payload);
        if (result) {
          if (result.device_id !== activeDeviceId) {
            closeQuietly(socket, 4003, "Device mismatch");
            return;
          }

          deps.registry.markHeartbeat(activeDeviceId);
          deps.db.touchHeartbeat(activeDeviceId);

          const matched = deps.router.handleAgentResult(result);
          if (!matched) {
            log("warn", "Unmatched command result", {
              device_id: result.device_id,
              request_id: result.request_id,
            });
          }

          return;
        }

        log("warn", "Unknown message kind", {
          device_id: activeDeviceId,
          payload,
        });
      } catch (error) {
        log("error", "Unhandled websocket message error", {
          device_id: activeDeviceId ?? "unknown",
          error: error instanceof Error ? error.message : String(error),
        });

        closeQuietly(socket, 1011, "Internal error");
      }
    });

    socket.on("close", () => {
      clearTimeout(authTimer);
      if (pingTimer) {
        clearInterval(pingTimer);
      }

      if (!activeDeviceId) {
        return;
      }

      const stillCurrent = deps.registry.isCurrentSocket(activeDeviceId, socket);
      if (!stillCurrent) {
        return;
      }

      deps.registry.disconnect(activeDeviceId);
      deps.db.markDeviceOffline(activeDeviceId);
      deps.router.clearDevicePending(activeDeviceId);

      log("info", "Agent disconnected", {
        device_id: activeDeviceId,
      });
    });

    socket.on("error", (error) => {
      log("warn", "Agent socket error", {
        device_id: activeDeviceId ?? "unknown",
        error: error instanceof Error ? error.message : String(error),
      });
    });
  });
}
