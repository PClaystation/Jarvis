import test from "node:test";
import assert from "node:assert/strict";
import { CommandRouter, DispatchError } from "../src/router/commandRouter";
import { DeviceRegistry } from "../src/realtime/deviceRegistry";

class MockSocket {
  public readonly sent: string[] = [];
  public readyState = 1;
  public OPEN = 1;

  public send(data: string): void {
    this.sent.push(data);
  }

  public close(): void {
    // noop for tests
  }
}

test("command router dispatch resolves when agent result arrives", async () => {
  const registry = new DeviceRegistry();
  const router = new CommandRouter(registry, 1_000, 100);
  const socket = new MockSocket();

  registry.register({
    deviceId: "m1",
    socket,
    version: "1.0.0",
    hostname: "host",
    username: "user",
    capabilities: ["media_control"],
  });

  const dispatchPromise = router.dispatchToDevice({
    requestId: "req-1",
    deviceId: "m1",
    command: {
      type: "PING",
      args: {},
    },
  });

  await new Promise((resolve) => setTimeout(resolve, 1));
  assert.equal(socket.sent.length, 1);

  const handled = router.handleAgentResult({
    kind: "result",
    request_id: "req-1",
    device_id: "m1",
    ok: true,
    message: "pong",
    completed_at: new Date().toISOString(),
  });

  assert.equal(handled, true);
  const result = await dispatchPromise;
  assert.equal(result.ok, true);
  assert.equal(result.message, "pong");
});

test("command router dispatch times out when no result arrives", async () => {
  const registry = new DeviceRegistry();
  const router = new CommandRouter(registry, 15, 100);
  const socket = new MockSocket();

  registry.register({
    deviceId: "m1",
    socket,
    version: "1.0.0",
    hostname: "host",
    username: "user",
    capabilities: ["media_control"],
  });

  await assert.rejects(
    () =>
      router.dispatchToDevice({
        requestId: "req-timeout",
        deviceId: "m1",
        command: {
          type: "PING",
          args: {},
        },
      }),
    (error: unknown) => {
      assert.ok(error instanceof DispatchError);
      assert.equal(error.code, "TIMEOUT");
      return true;
    },
  );
});
