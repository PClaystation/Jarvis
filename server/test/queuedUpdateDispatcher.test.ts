import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Database } from "../src/db/database";
import { EventHub } from "../src/events/eventHub";
import { DeviceRegistry } from "../src/realtime/deviceRegistry";
import { CommandRouter, DispatchError } from "../src/router/commandRouter";
import { sha256Hex } from "../src/utils/crypto";
import { QueuedUpdateDispatcher } from "../src/update/queuedUpdateDispatcher";

class MockSocket {
  public readyState = 1;
  public OPEN = 1;

  public send(_data: string): void {
    // noop
  }

  public close(): void {
    // noop
  }
}

class SuccessfulRouter {
  public calls: Array<{ requestId: string; deviceId: string; type: string; timeoutMs?: number }> = [];

  public async dispatchToDevice(input: {
    requestId: string;
    deviceId: string;
    command: { type: string };
    timeoutMs?: number;
  }): Promise<{
    request_id: string;
    device_id: string;
    ok: boolean;
    message: string;
    completed_at: string;
  }> {
    this.calls.push({
      requestId: input.requestId,
      deviceId: input.deviceId,
      type: input.command.type,
      timeoutMs: input.timeoutMs,
    });

    return {
      request_id: input.requestId,
      device_id: input.deviceId,
      ok: true,
      message: "queued update applied",
      completed_at: new Date().toISOString(),
    };
  }
}

class RetryableFailureRouter {
  public calls = 0;

  public async dispatchToDevice(_input: {
    requestId: string;
    deviceId: string;
    command: { type: string };
    timeoutMs?: number;
  }): Promise<{
    request_id: string;
    device_id: string;
    ok: boolean;
    message: string;
    completed_at: string;
  }> {
    this.calls += 1;
    throw new DispatchError("DEVICE_OFFLINE", "m1 is offline", true);
  }
}

function makeTempDbPath(): string {
  const suffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `cordyceps-queued-update-test-${suffix}.db`);
}

function seedQueuedUpdate(db: Database): void {
  db.enrollDevice({
    deviceId: "m1",
    tokenHash: sha256Hex("device-token"),
    displayName: "m1",
    version: "1.0.0",
    hostname: "host",
    username: "user",
    capabilities: ["updater"],
  });

  db.insertCommandLog({
    id: "req-1:m1",
    requestId: "req-1",
    deviceId: "m1",
    source: "test",
    rawText: "m1 update 1.0.1 https://example.com/cordyceps-agent.exe",
    parsedTarget: "m1",
    parsedType: "AGENT_UPDATE",
    argsJson: JSON.stringify({
      version: "1.0.1",
      url: "https://example.com/cordyceps-agent.exe",
      sha256: "a".repeat(64),
    }),
    status: "queued",
    resultMessage: null,
    errorCode: null,
  });

  db.upsertQueuedUpdate({
    id: "req-1:m1",
    requestId: "req-1",
    deviceId: "m1",
    source: "test",
    rawText: "m1 update 1.0.1 https://example.com/cordyceps-agent.exe",
    parsedTarget: "m1",
    version: "1.0.1",
    packageUrl: "https://example.com/cordyceps-agent.exe",
    sha256: "a".repeat(64),
    sizeBytes: null,
  });
}

test("queued update dispatches and completes when device is online", async () => {
  const sqlitePath = makeTempDbPath();
  const db = new Database(sqlitePath);
  const registry = new DeviceRegistry();
  const router = new SuccessfulRouter();
  const eventHub = new EventHub();

  seedQueuedUpdate(db);
  registry.register({
    deviceId: "m1",
    socket: new MockSocket(),
    version: "1.0.0",
    hostname: "host",
    username: "user",
    capabilities: ["updater"],
  });

  const dispatcher = new QueuedUpdateDispatcher({
    db,
    eventHub,
    registry,
    router: router as unknown as CommandRouter,
    updateCommandTimeoutMs: 12345,
  });

  try {
    await dispatcher.kick("m1");

    assert.equal(router.calls.length, 1);
    assert.equal(router.calls[0]?.type, "AGENT_UPDATE");
    assert.equal(router.calls[0]?.timeoutMs, 12345);
    assert.equal(db.listQueuedUpdatesForDevice("m1").length, 0);

    const logs = db.listCommandLogs({ limit: 20, requestId: "req-1", deviceId: "m1" });
    assert.equal(logs.length, 1);
    assert.equal(logs[0]?.status, "ok");
    assert.equal(logs[0]?.result_message, "queued update applied");
  } finally {
    db.close();
    try {
      fs.unlinkSync(sqlitePath);
    } catch {
      // ignore cleanup races
    }
  }
});

test("retryable dispatch error keeps queued update for next reconnect", async () => {
  const sqlitePath = makeTempDbPath();
  const db = new Database(sqlitePath);
  const registry = new DeviceRegistry();
  const router = new RetryableFailureRouter();
  const eventHub = new EventHub();

  seedQueuedUpdate(db);
  registry.register({
    deviceId: "m1",
    socket: new MockSocket(),
    version: "1.0.0",
    hostname: "host",
    username: "user",
    capabilities: ["updater"],
  });

  const dispatcher = new QueuedUpdateDispatcher({
    db,
    eventHub,
    registry,
    router: router as unknown as CommandRouter,
    updateCommandTimeoutMs: 12345,
  });

  try {
    await dispatcher.kick("m1");

    assert.equal(router.calls, 1);
    assert.equal(db.listQueuedUpdatesForDevice("m1").length, 1);
    const logs = db.listCommandLogs({ limit: 20, requestId: "req-1", deviceId: "m1" });
    assert.equal(logs.length, 1);
    assert.equal(logs[0]?.status, "queued");
  } finally {
    db.close();
    try {
      fs.unlinkSync(sqlitePath);
    } catch {
      // ignore cleanup races
    }
  }
});
