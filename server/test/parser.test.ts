import test from "node:test";
import assert from "node:assert/strict";
import { parseExternalCommand } from "../src/parser/commandParser";

test("parser accepts repeat-step commands", () => {
  const parsed = parseExternalCommand("m1 volume up 3");
  assert.ok(!("code" in parsed));
  assert.equal(parsed.target, "m1");
  assert.equal(parsed.command.type, "VOLUME_UP");
  assert.deepEqual(parsed.command.args, { steps: 3 });
});

test("parser supports admin command family", () => {
  const parsed = parseExternalCommand("a1 admin system info");
  assert.ok(!("code" in parsed));
  assert.equal(parsed.target, "a1");
  assert.equal(parsed.command.type, "SYSTEM_INFO");
});

test("parser rejects unconfirmed emergency command", () => {
  const parsed = parseExternalCommand("e1 panic");
  assert.ok("code" in parsed);
  assert.equal(parsed.code, "MALFORMED_ARGUMENT");
  assert.match(parsed.message, /requires explicit confirmation/i);
});
