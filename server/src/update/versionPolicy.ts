import type { UpdatePolicyRecord } from "../db/database";

export type VersionPolicyCode = "VERSION_REVOKED" | "VERSION_PINNED_UPDATE_REQUIRED" | null;

export interface VersionPolicyEvaluation {
  requiresUpdate: boolean;
  code: VersionPolicyCode;
  message: string | null;
}

function normalizeVersion(value: string | null | undefined): string {
  return typeof value === "string" ? value.trim() : "";
}

export function hasManagedPolicyPackage(policy: UpdatePolicyRecord): boolean {
  return Boolean(policy.pinned_version && policy.package_url && policy.sha256);
}

export function evaluateVersionPolicy(version: string | null | undefined, policy: UpdatePolicyRecord): VersionPolicyEvaluation {
  const normalizedVersion = normalizeVersion(version);
  const pinnedVersion = normalizeVersion(policy.pinned_version);
  const revoked = new Set(policy.revoked_versions.map((item) => normalizeVersion(item)).filter((item) => item.length > 0));

  if (normalizedVersion && revoked.has(normalizedVersion)) {
    return {
      requiresUpdate: true,
      code: "VERSION_REVOKED",
      message: `Version ${normalizedVersion} is revoked by server policy`,
    };
  }

  if (pinnedVersion && normalizedVersion !== pinnedVersion) {
    return {
      requiresUpdate: true,
      code: "VERSION_PINNED_UPDATE_REQUIRED",
      message: normalizedVersion
        ? `Version ${normalizedVersion} does not match pinned version ${pinnedVersion}`
        : `Pinned version ${pinnedVersion} is required`,
    };
  }

  return {
    requiresUpdate: false,
    code: null,
    message: null,
  };
}
