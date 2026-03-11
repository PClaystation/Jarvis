import type { Database } from "../db/database";

export interface PreparedDesignationChange {
  currentDeviceId: string;
  nextDeviceId: string;
}

export function inferDesignationPrefixFromPackageUrl(packageUrl: string): string | null {
  const value = packageUrl.trim().toLowerCase();
  if (!value) {
    return null;
  }

  if (value.includes("se1-agent")) {
    return "se";
  }

  if (value.includes("e1-agent")) {
    return "e";
  }

  if (value.includes("t1-agent")) {
    return "t";
  }

  if (value.includes("s1-agent")) {
    return "s";
  }

  if (value.includes("a1-agent")) {
    return "a";
  }

  if (value.includes("cordyceps-agent") || value.includes("jarvis-agent")) {
    return "m";
  }

  return null;
}

function deviceIdPrefix(deviceId: string): string {
  const match = deviceId.trim().toLowerCase().match(/^[a-z]+/);
  return match ? match[0].slice(0, 1) : "";
}

export function prepareDesignationChange(
  db: Database,
  deviceId: string,
  nextPrefix: string | null,
): PreparedDesignationChange | null {
  if (!nextPrefix) {
    return null;
  }

  const currentPrefix = deviceIdPrefix(deviceId);
  if (!currentPrefix || currentPrefix === nextPrefix) {
    return null;
  }

  const nextDeviceId = db.allocateNextDeviceId(nextPrefix);
  if (!db.cloneDeviceWithNewId(deviceId, nextDeviceId)) {
    return null;
  }

  return {
    currentDeviceId: deviceId,
    nextDeviceId,
  };
}
