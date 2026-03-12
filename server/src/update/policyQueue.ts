import type { Database, UpdatePolicyRecord } from "../db/database";
import { makeRequestId } from "../utils/id";

interface QueuePolicyUpdateInput {
  db: Database;
  deviceId: string;
  source: string;
  policy: UpdatePolicyRecord;
}

interface QueuePolicyUpdateResult {
  queued: boolean;
  requestId: string | null;
}

function makeUpdateRawText(deviceId: string, version: string, packageUrl: string): string {
  return `${deviceId} update ${version} ${packageUrl}`;
}

export function queuePolicyUpdate(input: QueuePolicyUpdateInput): QueuePolicyUpdateResult {
  const version = input.policy.pinned_version?.trim() ?? "";
  const packageUrl = input.policy.package_url?.trim() ?? "";
  const sha256 = input.policy.sha256?.trim().toLowerCase() ?? "";
  const sizeBytes = input.policy.size_bytes ?? null;

  if (!version || !packageUrl || !sha256) {
    return {
      queued: false,
      requestId: null,
    };
  }

  const alreadyQueued = input.db
    .listQueuedUpdatesForDevice(input.deviceId)
    .some(
      (item) =>
        item.version === version &&
        item.package_url === packageUrl &&
        item.sha256.toLowerCase() === sha256 &&
        item.size_bytes === sizeBytes,
    );

  if (alreadyQueued) {
    return {
      queued: false,
      requestId: null,
    };
  }

  const requestId = makeRequestId();
  const logId = `${requestId}:${input.deviceId}`;
  const rawText = makeUpdateRawText(input.deviceId, version, packageUrl);

  input.db.insertCommandLog({
    id: logId,
    requestId,
    deviceId: input.deviceId,
    source: input.source,
    rawText,
    parsedTarget: input.deviceId,
    parsedType: "AGENT_UPDATE",
    argsJson: JSON.stringify({
      version,
      url: packageUrl,
      sha256,
      ...(sizeBytes ? { size_bytes: sizeBytes } : {}),
    }),
    status: "queued",
    resultMessage: null,
    errorCode: null,
  });

  input.db.upsertQueuedUpdate({
    id: logId,
    requestId,
    deviceId: input.deviceId,
    source: input.source,
    rawText,
    parsedTarget: input.deviceId,
    version,
    packageUrl,
    sha256,
    sizeBytes,
  });

  return {
    queued: true,
    requestId,
  };
}
