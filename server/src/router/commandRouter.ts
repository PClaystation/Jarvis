import type {
  AgentResultMessage,
  CommandDispatchResult,
  ServerToAgentCommandMessage,
  TypedCommand,
} from "../types/protocol";
import { DeviceRegistry, type SocketLike } from "../realtime/deviceRegistry";

interface PendingResult {
  resolve: (result: CommandDispatchResult) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
}

function isSocketWritable(socket: SocketLike): boolean {
  if (typeof socket.readyState !== "number") {
    return true;
  }

  const openState = typeof socket.OPEN === "number" ? socket.OPEN : 1;
  return socket.readyState === openState;
}

export class DispatchError extends Error {
  public readonly code: string;

  public readonly retryable: boolean;

  public constructor(code: string, message: string, retryable = false) {
    super(message);
    this.name = "DispatchError";
    this.code = code;
    this.retryable = retryable;
  }
}

function asDispatchError(error: unknown): DispatchError {
  if (error instanceof DispatchError) {
    return error;
  }

  if (error instanceof Error) {
    return new DispatchError("ROUTING_ERROR", error.message, true);
  }

  return new DispatchError("ROUTING_ERROR", "Unknown routing error", true);
}

export class CommandRouter {
  private readonly pending = new Map<string, PendingResult>();

  private readonly deviceQueues = new Map<string, Promise<void>>();

  public constructor(
    private readonly registry: DeviceRegistry,
    private readonly timeoutMs: number,
    private readonly maxPendingCommands: number,
  ) {}

  public pendingCount(): number {
    return this.pending.size;
  }

  public async dispatchToDevice(input: {
    requestId: string;
    deviceId: string;
    command: TypedCommand;
  }): Promise<CommandDispatchResult> {
    return this.enqueueDevice(input.deviceId, () => this.dispatchToDeviceNow(input));
  }

  public async dispatchToMany(input: {
    requestId: string;
    deviceIds: string[];
    command: TypedCommand;
  }): Promise<CommandDispatchResult[]> {
    return Promise.all(
      input.deviceIds.map((deviceId) =>
        this.dispatchToDevice({
          requestId: input.requestId,
          deviceId,
          command: input.command,
        }).catch((error) => {
          const routed = asDispatchError(error);
          return {
            request_id: input.requestId,
            device_id: deviceId,
            ok: false,
            message: routed.message,
            error_code: routed.code,
            completed_at: new Date().toISOString(),
          };
        }),
      ),
    );
  }

  public handleAgentResult(message: AgentResultMessage): boolean {
    const key = this.pendingKey(message.device_id, message.request_id);
    const pending = this.pending.get(key);
    if (!pending) {
      return false;
    }

    clearTimeout(pending.timer);
    this.pending.delete(key);

    pending.resolve({
      request_id: message.request_id,
      device_id: message.device_id,
      ok: message.ok,
      message: message.message,
      error_code: message.error_code,
      completed_at: message.completed_at,
    });

    return true;
  }

  public clearDevicePending(deviceId: string): void {
    for (const [key, pending] of this.pending.entries()) {
      if (!key.startsWith(`${deviceId}:`)) {
        continue;
      }

      clearTimeout(pending.timer);
      this.pending.delete(key);
      pending.reject(new DispatchError("DEVICE_DISCONNECTED", `${deviceId} disconnected`, true));
    }
  }

  public clearAllPending(reason = "router shutdown"): void {
    for (const [key, pending] of this.pending.entries()) {
      clearTimeout(pending.timer);
      this.pending.delete(key);
      pending.reject(new DispatchError("ROUTER_CLOSED", reason, true));
    }

    this.deviceQueues.clear();
  }

  private async dispatchToDeviceNow(input: {
    requestId: string;
    deviceId: string;
    command: TypedCommand;
  }): Promise<CommandDispatchResult> {
    if (this.pending.size >= this.maxPendingCommands) {
      throw new DispatchError("ROUTER_OVERLOADED", "Server is busy, try again", true);
    }

    const connection = this.registry.get(input.deviceId);
    if (!connection) {
      throw new DispatchError("DEVICE_OFFLINE", `${input.deviceId} is offline`, true);
    }

    if (!isSocketWritable(connection.socket)) {
      throw new DispatchError("DEVICE_OFFLINE", `${input.deviceId} is offline`, true);
    }

    const key = this.pendingKey(input.deviceId, input.requestId);
    if (this.pending.has(key)) {
      throw new DispatchError("DUPLICATE_REQUEST", `Duplicate request_id for ${input.deviceId}`, false);
    }

    const message: ServerToAgentCommandMessage = {
      kind: "command",
      request_id: input.requestId,
      device_id: input.deviceId,
      type: input.command.type,
      args: input.command.args,
      issued_at: new Date().toISOString(),
    };

    const promise = new Promise<CommandDispatchResult>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(key);
        reject(new DispatchError("TIMEOUT", `${input.deviceId} did not respond in time`, true));
      }, this.timeoutMs);

      this.pending.set(key, { resolve, reject, timer });
    });

    try {
      connection.socket.send(JSON.stringify(message));
    } catch (error) {
      const pending = this.pending.get(key);
      if (pending) {
        clearTimeout(pending.timer);
        this.pending.delete(key);
      }

      const asError = error instanceof Error ? error : new Error("Failed to send command");
      throw new DispatchError("SEND_FAILED", asError.message, true);
    }

    return promise;
  }

  private enqueueDevice<T>(deviceId: string, task: () => Promise<T>): Promise<T> {
    const tail = this.deviceQueues.get(deviceId) ?? Promise.resolve();
    const run = tail.then(task, task);

    const newTail = run.then(
      () => undefined,
      () => undefined,
    );

    this.deviceQueues.set(deviceId, newTail);

    newTail.finally(() => {
      const current = this.deviceQueues.get(deviceId);
      if (current === newTail) {
        this.deviceQueues.delete(deviceId);
      }
    });

    return run;
  }

  private pendingKey(deviceId: string, requestId: string): string {
    return `${deviceId}:${requestId}`;
  }
}
