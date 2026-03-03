import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { extractBearerToken, constantTimeEqual } from "../auth/auth";
import type { AppConfig } from "../config/env";
import type { Database } from "../db/database";
import { parseExternalCommand } from "../parser/commandParser";
import { DeviceRegistry } from "../realtime/deviceRegistry";
import { CommandRouter, DispatchError } from "../router/commandRouter";
import type { CommandDispatchResult } from "../types/protocol";
import { randomToken, sha256Hex } from "../utils/crypto";
import { makeRequestId } from "../utils/id";
import { log } from "../utils/logger";

interface ApiDeps {
  config: AppConfig;
  db: Database;
  registry: DeviceRegistry;
  router: CommandRouter;
}

interface CommandRequestBody {
  request_id?: string;
  text?: string;
  source?: string;
  sent_at?: string;
  client_version?: string;
  user_id?: string;
  shortcut_name?: string;
}

interface EnrollRequestBody {
  bootstrap_token?: string;
  device_id?: string;
  display_name?: string;
  version?: string;
  hostname?: string;
  username?: string;
  capabilities?: string[];
}

const MAX_TEXT_LEN = 280;
const MAX_SOURCE_LEN = 40;

function makeLogId(requestId: string, deviceId: string): string {
  return `${requestId}:${deviceId}`;
}

function unauthorized(reply: FastifyReply): void {
  reply.code(401).send({ ok: false, message: "Unauthorized" });
}

function isPhoneAuthorized(request: FastifyRequest, config: AppConfig): boolean {
  const token = extractBearerToken(request.headers.authorization);
  if (!token) {
    return false;
  }

  return constantTimeEqual(token, config.phoneApiToken);
}

function normalizeRequestId(candidate?: string): string {
  const value = candidate?.trim();
  if (!value) {
    return makeRequestId();
  }

  if (!/^[A-Za-z0-9_.:-]{1,100}$/.test(value)) {
    return makeRequestId();
  }

  return value;
}

function normalizeSource(candidate?: string): string {
  const value = candidate?.trim().toLowerCase() ?? "iphone";
  if (!value) {
    return "iphone";
  }

  return value.slice(0, MAX_SOURCE_LEN);
}

function parseDispatchError(error: unknown): { code: string; message: string; httpStatus: number } {
  if (!(error instanceof DispatchError)) {
    const message = error instanceof Error ? error.message : "Unknown routing error";
    return {
      code: "ROUTING_ERROR",
      message,
      httpStatus: 502,
    };
  }

  switch (error.code) {
    case "TIMEOUT":
      return { code: error.code, message: error.message, httpStatus: 504 };
    case "ROUTER_OVERLOADED":
      return { code: error.code, message: error.message, httpStatus: 503 };
    case "DEVICE_OFFLINE":
    case "DEVICE_DISCONNECTED":
    case "DUPLICATE_REQUEST":
      return { code: error.code, message: error.message, httpStatus: 409 };
    case "SEND_FAILED":
      return { code: error.code, message: error.message, httpStatus: 502 };
    default:
      return { code: error.code, message: error.message, httpStatus: 500 };
  }
}

function asCommandBody(body: unknown): CommandRequestBody {
  if (!body || typeof body !== "object") {
    return {};
  }

  return body as CommandRequestBody;
}

function asEnrollBody(body: unknown): EnrollRequestBody {
  if (!body || typeof body !== "object") {
    return {};
  }

  return body as EnrollRequestBody;
}

export async function registerApiRoutes(server: FastifyInstance, deps: ApiDeps): Promise<void> {
  server.get("/api/health", async () => {
    const dbStats = deps.db.healthSnapshot();

    return {
      ok: true,
      service: "jarvis-server",
      ts: new Date().toISOString(),
      uptime_seconds: Math.floor(process.uptime()),
      online_connections: deps.registry.countOnline(),
      pending_commands: deps.router.pendingCount(),
      devices_total: dbStats.deviceCount,
      devices_online: dbStats.onlineDeviceCount,
      command_logs_total: dbStats.commandLogCount,
    };
  });

  server.get("/api/devices", async (request, reply) => {
    if (!isPhoneAuthorized(request, deps.config)) {
      unauthorized(reply);
      return;
    }

    return {
      ok: true,
      devices: deps.db.listDevices(),
    };
  });

  server.post("/api/enroll", async (request, reply) => {
    const body = asEnrollBody(request.body);
    if (!body.bootstrap_token || !constantTimeEqual(body.bootstrap_token, deps.config.agentBootstrapToken)) {
      unauthorized(reply);
      return;
    }

    const deviceId = body.device_id?.trim().toLowerCase() ?? "";
    if (!/^[a-z0-9_-]{2,32}$/.test(deviceId)) {
      reply.code(400).send({
        ok: false,
        message: "device_id must be 2-32 chars and use a-z, 0-9, _ or -",
      });
      return;
    }

    const token = randomToken();
    const tokenHash = sha256Hex(token);

    deps.db.enrollDevice({
      deviceId,
      tokenHash,
      displayName: body.display_name?.slice(0, 80),
      version: body.version?.slice(0, 40),
      hostname: body.hostname?.slice(0, 120),
      username: body.username?.slice(0, 120),
      capabilities: Array.isArray(body.capabilities)
        ? body.capabilities.filter((value): value is string => typeof value === "string").slice(0, 50)
        : [],
    });

    log("info", "Device enrolled", {
      device_id: deviceId,
      hostname: body.hostname ?? null,
      username: body.username ?? null,
    });

    reply.send({
      ok: true,
      device_id: deviceId,
      device_token: token,
      ws_url: deps.config.publicWsUrl,
      message: "Enrollment complete",
    });
  });

  server.post("/api/command", async (request, reply) => {
    if (!isPhoneAuthorized(request, deps.config)) {
      unauthorized(reply);
      return;
    }

    const body = asCommandBody(request.body);
    const rawText = body.text?.toString() ?? "";
    const text = rawText.trim();
    const requestId = normalizeRequestId(body.request_id);
    const source = normalizeSource(body.source);

    if (text.length === 0) {
      reply.code(400).send({
        ok: false,
        request_id: requestId,
        message: "Command rejected: command text is empty",
        error_code: "EMPTY_COMMAND",
      });
      return;
    }

    if (text.length > MAX_TEXT_LEN) {
      reply.code(400).send({
        ok: false,
        request_id: requestId,
        message: `Command rejected: command text too long (max ${MAX_TEXT_LEN})`,
        error_code: "COMMAND_TOO_LONG",
      });
      return;
    }

    const parsed = parseExternalCommand(text);
    if ("code" in parsed) {
      reply.code(400).send({
        ok: false,
        request_id: requestId,
        message: `Command rejected: ${parsed.message}`,
        error_code: parsed.code,
      });
      return;
    }

    if (parsed.target === "all" && parsed.command.type !== "PING") {
      reply.code(400).send({
        ok: false,
        request_id: requestId,
        message: "Command rejected: target all supports only ping in MVP",
        error_code: "GROUP_COMMAND_NOT_ALLOWED",
      });
      return;
    }

    const targetDeviceIds =
      parsed.target === "all" ? deps.registry.listOnlineDeviceIds() : [parsed.target];

    if (targetDeviceIds.length === 0) {
      reply.code(409).send({
        ok: false,
        request_id: requestId,
        message: "No online devices available",
        error_code: "NO_ONLINE_DEVICES",
      });
      return;
    }

    for (const deviceId of targetDeviceIds) {
      const knownDevice = deps.db.getDevice(deviceId) ?? deps.registry.get(deviceId);
      if (!knownDevice) {
        reply.code(404).send({
          ok: false,
          request_id: requestId,
          message: `Unknown device: ${deviceId}`,
          error_code: "UNKNOWN_DEVICE",
        });
        return;
      }

      const connected = deps.registry.get(deviceId);
      if (!connected) {
        reply.code(409).send({
          ok: false,
          request_id: requestId,
          message: `${deviceId} is offline`,
          error_code: "DEVICE_OFFLINE",
        });
        return;
      }

      deps.db.insertCommandLog({
        id: makeLogId(requestId, deviceId),
        requestId,
        deviceId,
        source,
        rawText: parsed.rawText,
        parsedTarget: parsed.target,
        parsedType: parsed.command.type,
        argsJson: JSON.stringify(parsed.command.args),
        status: "queued",
        resultMessage: null,
        errorCode: null,
      });
    }

    if (parsed.target !== "all") {
      const deviceId = targetDeviceIds[0];
      try {
        const result = await deps.router.dispatchToDevice({
          requestId,
          deviceId,
          command: parsed.command,
        });

        deps.db.completeCommandLog({
          id: makeLogId(requestId, deviceId),
          status: result.ok ? "ok" : "failed",
          resultMessage: result.message,
          errorCode: result.error_code,
        });

        reply.send({
          ok: result.ok,
          request_id: requestId,
          target: deviceId,
          parsed_type: parsed.command.type,
          message: result.message,
          result,
        });
      } catch (error) {
        const dispatch = parseDispatchError(error);

        deps.db.completeCommandLog({
          id: makeLogId(requestId, deviceId),
          status: dispatch.code === "TIMEOUT" ? "timeout" : "failed",
          resultMessage: dispatch.message,
          errorCode: dispatch.code,
        });

        reply.code(dispatch.httpStatus).send({
          ok: false,
          request_id: requestId,
          target: deviceId,
          parsed_type: parsed.command.type,
          message: dispatch.message,
          error_code: dispatch.code,
        });
      }

      return;
    }

    const results = await deps.router.dispatchToMany({
      requestId,
      deviceIds: targetDeviceIds,
      command: parsed.command,
    });

    for (const result of results) {
      deps.db.completeCommandLog({
        id: makeLogId(requestId, result.device_id),
        status: result.ok ? "ok" : "failed",
        resultMessage: result.message,
        errorCode: result.error_code,
      });
    }

    const okCount = results.filter((result) => result.ok).length;
    const total = results.length;

    reply.send({
      ok: okCount === total,
      request_id: requestId,
      target: "all",
      parsed_type: parsed.command.type,
      message: `Completed ${okCount}/${total}`,
      results: results.map((result: CommandDispatchResult) => ({
        device_id: result.device_id,
        ok: result.ok,
        message: result.message,
        error_code: result.error_code,
      })),
    });
  });
}
