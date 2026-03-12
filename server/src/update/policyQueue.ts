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
  const signature = input.policy.signature?.trim() || null;
  const signatureKeyId = input.policy.signature_key_id?.trim() || null;
  const usePrivilegedHelper = input.policy.use_privileged_helper === true;

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
        item.size_bytes === sizeBytes &&
        (item.signature ?? null) === signature &&
        (item.signature_key_id ?? null) === signatureKeyId &&
        item.use_privileged_helper === usePrivilegedHelper,
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
      ...(signature ? { signature } : {}),
      ...(signatureKeyId ? { signature_key_id: signatureKeyId } : {}),
      ...(usePrivilegedHelper ? { use_privileged_helper: true } : {}),
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
    signature,
    signatureKeyId,
    usePrivilegedHelper,
  });

  return {
    queued: true,
    requestId,
  };
}
