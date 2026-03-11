import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import Fastify from "fastify";
import { registerApiRoutes } from "../src/api/routes";
import { Database } from "../src/db/database";
import type { AppConfig } from "../src/config/env";
import { DeviceRegistry } from "../src/realtime/deviceRegistry";
import { EventHub } from "../src/events/eventHub";
import { sha256Hex } from "../src/utils/crypto";
import type { CommandRouter } from "../src/router/commandRouter";

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

class FakeRouter {
  public dispatchedMany: Array<{ requestId: string; deviceIds: string[]; type: string }> = [];

  public pendingCount(): number {
    return 0;
  }

  public async dispatchToDevice(input: {
    requestId: string;
    deviceId: string;
    command: { type: string };
  }): Promise<{
    request_id: string;
    device_id: string;
    ok: boolean;
    message: string;
    completed_at: string;
  }> {
    return {
      request_id: input.requestId,
      device_id: input.deviceId,
      ok: true,
      message: `${input.command.type} ok`,
      completed_at: new Date().toISOString(),
    };
  }

  public async dispatchToMany(input: {
    requestId: string;
    deviceIds: string[];
    command: { type: string };
  }): Promise<Array<{
    request_id: string;
    device_id: string;
    ok: boolean;
    message: string;
    completed_at: string;
  }>> {
    this.dispatchedMany.push({ requestId: input.requestId, deviceIds: [...input.deviceIds], type: input.command.type });
    return input.deviceIds.map((deviceId) => ({
      request_id: input.requestId,
      device_id: deviceId,
      ok: true,
      message: `${input.command.type} ok`,
      completed_at: new Date().toISOString(),
    }));
  }

  public clearDevicePending(_deviceId: string): void {
    // noop
  }

  public clearAllPending(_reason = ""): void {
    // noop
  }
}

function makeConfig(): AppConfig {
  return {
    host: "127.0.0.1",
    port: 0,
    phoneApiToken: "owner-token",
    phoneApiTokenSource: "env",
    agentBootstrapToken: "bootstrap-token",
    agentBootstrapTokenSource: "env",
    secretsPath: "",
    secretsPathSource: "default",
    sqlitePath: "",
    sqlitePathSource: "default",
    commandTimeoutMs: 1000,
    maxPendingCommands: 100,
    heartbeatTtlMs: 90_000,
    wsAuthTimeoutMs: 10_000,
    wsPingIntervalMs: 30_000,
    wsMaxMessageBytes: 65_536,
    updateCommandTimeoutMs: 10_000,
    updateMetadataTimeoutMs: 10_000,
    updateMaxPackageBytes: 10_000_000,
    enforceHttpsUpdateUrl: false,
    corsAllowedOrigins: ["*"],
    publicWsUrl: "ws://localhost/ws/agent",
    pwaPublicUrl: "http://localhost/app",
  };
}

function makeTempDbPath(): string {
  const suffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `cordyceps-routes-test-${suffix}.db`);
}

async function createHarness() {
  const sqlitePath = makeTempDbPath();
  const db = new Database(sqlitePath);
  const registry = new DeviceRegistry();
  const router = new FakeRouter();
  const eventHub = new EventHub();

  db.enrollDevice({
    deviceId: "m1",
    tokenHash: sha256Hex("device-token"),
    displayName: "m1",
    version: "1.0.0",
    hostname: "host",
    username: "user",
    capabilities: ["media_control", "locking", "open_app", "notifications", "clipboard_control"],
  });

  registry.register({
    deviceId: "m1",
    socket: new MockSocket(),
    version: "1.0.0",
    hostname: "host",
    username: "user",
    capabilities: ["media_control", "locking", "open_app", "notifications", "clipboard_control"],
  });

  db.markDeviceOnline({
    deviceId: "m1",
    version: "1.0.0",
    hostname: "host",
    username: "user",
    capabilities: ["media_control", "locking", "open_app", "notifications", "clipboard_control"],
  });

  const server = Fastify({ logger: false });
  await registerApiRoutes(server, {
    config: makeConfig(),
    db,
    registry,
    router: router as unknown as CommandRouter,
    eventHub,
  });

  const cleanup = async () => {
    await server.close();
    db.close();
    try {
      fs.unlinkSync(sqlitePath);
    } catch {
      // ignore cleanup races
    }
  };

  return { server, db, registry, router, cleanup };
}

function authHeaders(token: string): Record<string, string> {
  return {
    authorization: `Bearer ${token}`,
    "content-type": "application/json",
  };
}

test("scoped API key can read devices but cannot execute updates", async () => {
  const harness = await createHarness();
  const { server, cleanup } = harness;

  try {
    const createKey = await server.inject({
      method: "POST",
      url: "/api/auth/keys",
      headers: authHeaders("owner-token"),
      payload: {
        name: "viewer",
        scopes: ["devices:read", "history:read"],
      },
    });

    assert.equal(createKey.statusCode, 200);
    const createdBody = createKey.json();
    assert.equal(createdBody.ok, true);
    assert.equal(typeof createdBody.api_key, "string");

    const scopedToken = createdBody.api_key as string;

    const devices = await server.inject({
      method: "GET",
      url: "/api/devices",
      headers: {
        authorization: `Bearer ${scopedToken}`,
      },
    });

    assert.equal(devices.statusCode, 200);
    const devicesBody = devices.json();
    assert.equal(devicesBody.ok, true);
    assert.equal(Array.isArray(devicesBody.devices), true);

    const updateAttempt = await server.inject({
      method: "POST",
      url: "/api/update",
      headers: authHeaders(scopedToken),
      payload: {
        target: "m1",
        version: "1.0.1",
        package_url: "https://example.com/agent.exe",
      },
    });

    assert.equal(updateAttempt.statusCode, 403);
  } finally {
    await cleanup();
  }
});

test("history endpoint returns command logs", async () => {
  const harness = await createHarness();
  const { server, db, cleanup } = harness;

  try {
    db.insertCommandLog({
      id: "req-1:m1",
      requestId: "req-1",
      deviceId: "m1",
      source: "test",
      rawText: "m1 ping",
      parsedTarget: "m1",
      parsedType: "PING",
      argsJson: "{}",
      status: "queued",
      resultMessage: null,
      errorCode: null,
    });

    db.completeCommandLog({
      id: "req-1:m1",
      status: "ok",
      resultMessage: "pong",
    });

    const response = await server.inject({
      method: "GET",
      url: "/api/command-logs?limit=10",
      headers: {
        authorization: "Bearer owner-token",
      },
    });

    assert.equal(response.statusCode, 200);
    const body = response.json();
    assert.equal(body.ok, true);
    assert.equal(body.count >= 1, true);
    assert.equal(Array.isArray(body.logs), true);
    assert.equal(body.logs[0].parsed_type, "PING");
  } finally {
    await cleanup();
  }
});

test("group command requires explicit bulk confirmation", async () => {
  const harness = await createHarness();
  const { server, router, cleanup } = harness;

  try {
    const createGroup = await server.inject({
      method: "PUT",
      url: "/api/groups/office",
      headers: authHeaders("owner-token"),
      payload: {
        display_name: "Office",
        description: "Office devices",
        device_ids: ["m1"],
      },
    });

    assert.equal(createGroup.statusCode, 200);

    const withoutConfirm = await server.inject({
      method: "POST",
      url: "/api/groups/office/command",
      headers: authHeaders("owner-token"),
      payload: {
        text: "lock",
        confirm_bulk: false,
      },
    });

    assert.equal(withoutConfirm.statusCode, 400);
    assert.equal(withoutConfirm.json().error_code, "BULK_CONFIRM_REQUIRED");

    const pingDispatch = await server.inject({
      method: "POST",
      url: "/api/groups/office/command",
      headers: authHeaders("owner-token"),
      payload: {
        text: "ping",
        confirm_bulk: false,
      },
    });

    assert.equal(pingDispatch.statusCode, 200);
    const body = pingDispatch.json();
    assert.equal(body.ok, true);
    assert.equal(router.dispatchedMany.length, 1);
    assert.deepEqual(router.dispatchedMany[0].deviceIds, ["m1"]);
  } finally {
    await cleanup();
  }
});
