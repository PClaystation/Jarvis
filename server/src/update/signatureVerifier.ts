import { createPublicKey, verify, type KeyObject } from "node:crypto";

export interface UpdateSignatureMaterial {
  version: string;
  packageUrl: string;
  sha256: string;
  sizeBytes: number | null;
}

export interface SignatureVerificationInput extends UpdateSignatureMaterial {
  signature: string;
  keyId: string | null;
  keyStore: Record<string, string>;
}

export interface SignatureVerificationResult {
  ok: boolean;
  keyId: string | null;
  code: string | null;
  message: string | null;
}

function normalizeBase64(value: string): string {
  return value.replace(/-/g, "+").replace(/_/g, "/");
}

function decodeBase64(value: string): Buffer | null {
  const compact = value.replace(/\s+/g, "");
  if (!compact) {
    return null;
  }

  try {
    const normalized = normalizeBase64(compact);
    const padding = normalized.length % 4 === 0 ? "" : "=".repeat(4 - (normalized.length % 4));
    return Buffer.from(`${normalized}${padding}`, "base64");
  } catch {
    return null;
  }
}

function toBase64Url(buffer: Buffer): string {
  return buffer.toString("base64url");
}

function resolveVerificationKey(input: {
  keyId: string | null;
  keyStore: Record<string, string>;
}): { keyId: string; keyValue: string } | null {
  const keys = Object.entries(input.keyStore);
  if (keys.length === 0) {
    return null;
  }

  if (input.keyId) {
    const keyValue = input.keyStore[input.keyId];
    if (!keyValue) {
      return null;
    }

    return { keyId: input.keyId, keyValue };
  }

  if (keys.length !== 1) {
    return null;
  }

  return {
    keyId: keys[0][0],
    keyValue: keys[0][1],
  };
}

function keyObjectFromString(rawKey: string): KeyObject | null {
  const trimmed = rawKey.trim();
  if (!trimmed) {
    return null;
  }

  try {
    if (trimmed.startsWith("-----BEGIN")) {
      return createPublicKey(trimmed);
    }

    const decoded = decodeBase64(trimmed);
    if (!decoded || decoded.length !== 32) {
      return null;
    }

    return createPublicKey({
      key: {
        kty: "OKP",
        crv: "Ed25519",
        x: toBase64Url(decoded),
      },
      format: "jwk",
    });
  } catch {
    return null;
  }
}

export function buildUpdateSignaturePayload(input: UpdateSignatureMaterial): Buffer {
  const lines = [
    "cordyceps-update-signature-v1",
    `version=${input.version}`,
    `package_url=${input.packageUrl}`,
    `sha256=${input.sha256}`,
    `size_bytes=${input.sizeBytes ?? ""}`,
  ];

  return Buffer.from(lines.join("\n"), "utf8");
}

export function verifyUpdateSignature(input: SignatureVerificationInput): SignatureVerificationResult {
  const signatureBytes = decodeBase64(input.signature);
  if (!signatureBytes || signatureBytes.length === 0) {
    return {
      ok: false,
      keyId: null,
      code: "INVALID_UPDATE_SIGNATURE",
      message: "signature must be valid base64/base64url",
    };
  }

  const resolved = resolveVerificationKey({
    keyId: input.keyId,
    keyStore: input.keyStore,
  });
  if (!resolved) {
    if (Object.keys(input.keyStore).length === 0) {
      return {
        ok: false,
        keyId: null,
        code: "SIGNING_KEYS_NOT_CONFIGURED",
        message: "No update signing keys are configured on the server",
      };
    }

    if (input.keyId) {
      return {
        ok: false,
        keyId: input.keyId,
        code: "UNKNOWN_SIGNING_KEY",
        message: `Unknown signature_key_id: ${input.keyId}`,
      };
    }

    return {
      ok: false,
      keyId: null,
      code: "SIGNATURE_KEY_REQUIRED",
      message: "signature_key_id is required when multiple signing keys are configured",
    };
  }

  const keyObject = keyObjectFromString(resolved.keyValue);
  if (!keyObject) {
    return {
      ok: false,
      keyId: resolved.keyId,
      code: "INVALID_SIGNING_KEY",
      message: `Configured signing key ${resolved.keyId} is invalid`,
    };
  }

  const payload = buildUpdateSignaturePayload(input);
  let verified = false;
  try {
    verified = verify(null, payload, keyObject, signatureBytes);
  } catch {
    verified = false;
  }

  if (!verified) {
    return {
      ok: false,
      keyId: resolved.keyId,
      code: "UPDATE_SIGNATURE_MISMATCH",
      message: "signature verification failed for package metadata",
    };
  }

  return {
    ok: true,
    keyId: resolved.keyId,
    code: null,
    message: null,
  };
}
