import fs from "node:fs";
import path from "node:path";
import BetterSqlite3 from "better-sqlite3";
import { constantTimeEqual } from "../auth/auth";
import type { DeviceRecord } from "../types/protocol";
import { sha256Hex } from "../utils/crypto";

export interface EnrollDeviceInput {
  deviceId: string;
  tokenHash: string;
  displayName?: string;
  version?: string;
  hostname?: string;
  username?: string;
  capabilities?: string[];
}

export interface CommandLogInsert {
  id: string;
  requestId: string;
  deviceId: string;
  source: string;
  rawText: string;
  parsedTarget: string;
  parsedType: string;
  argsJson: string;
  status: string;
  resultMessage: string | null;
  errorCode?: string | null;
}

export interface CommandLogRecord {
  id: string;
  request_id: string;
  device_id: string;
  source: string;
  raw_text: string;
  parsed_target: string;
  parsed_type: string;
  args: Record<string, unknown>;
  status: string;
  result_message: string | null;
  error_code: string | null;
  created_at: string;
  completed_at: string | null;
}

export interface CommandLogQuery {
  limit: number;
  before?: string;
  deviceId?: string;
  requestId?: string;
  parsedType?: string;
  status?: string;
}

export interface ApiKeyRecord {
  key_id: string;
  name: string;
  scopes: string[];
  status: "active" | "revoked";
  created_at: string;
  updated_at: string;
  last_used_at: string | null;
}

export interface ApiKeyLookup extends ApiKeyRecord {
  token_hash: string;
}

export interface DeviceGroupRecord {
  group_id: string;
  display_name: string;
  description: string | null;
  device_ids: string[];
  created_at: string;
  updated_at: string;
}

function parseJsonArray(value: string | null | undefined): string[] {
  if (!value) {
    return [];
  }

  try {
    const parsed = JSON.parse(value) as unknown;
    if (!Array.isArray(parsed)) {
      return [];
    }

    return parsed
      .map((item) => (typeof item === "string" ? item.trim() : ""))
      .filter((item) => item.length > 0);
  } catch {
    return [];
  }
}

function parseJsonObject(value: string | null | undefined): Record<string, unknown> {
  if (!value) {
    return {};
  }

  try {
    const parsed = JSON.parse(value) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return {};
    }

    return parsed as Record<string, unknown>;
  } catch {
    return {};
  }
}

function normalizeLimit(limit: number, fallback = 100, max = 500): number {
  if (!Number.isFinite(limit)) {
    return fallback;
  }

  const rounded = Math.floor(limit);
  if (rounded <= 0) {
    return fallback;
  }

  return Math.min(rounded, max);
}

export class Database {
  private readonly db: InstanceType<typeof BetterSqlite3>;

  public constructor(sqlitePath: string) {
    const dir = path.dirname(sqlitePath);
    fs.mkdirSync(dir, { recursive: true });

    this.db = new BetterSqlite3(sqlitePath);
    this.db.pragma("journal_mode = WAL");
    this.db.pragma("busy_timeout = 5000");
    this.db.pragma("foreign_keys = ON");
    this.init();
  }

  private init(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        display_name TEXT,
        auth_token_hash TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'offline',
        last_seen TEXT NOT NULL,
        version TEXT,
        hostname TEXT,
        username TEXT,
        capabilities_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS command_logs (
        id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        source TEXT NOT NULL,
        raw_text TEXT NOT NULL,
        parsed_target TEXT NOT NULL,
        parsed_type TEXT NOT NULL,
        args_json TEXT NOT NULL,
        status TEXT NOT NULL,
        result_message TEXT,
        error_code TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY (device_id) REFERENCES devices(device_id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS api_keys (
        key_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        scopes_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_used_at TEXT
      );

      CREATE TABLE IF NOT EXISTS device_groups (
        group_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS device_group_members (
        group_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (group_id, device_id),
        FOREIGN KEY (group_id) REFERENCES device_groups(group_id) ON DELETE CASCADE,
        FOREIGN KEY (device_id) REFERENCES devices(device_id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_command_logs_request_id ON command_logs(request_id);
      CREATE INDEX IF NOT EXISTS idx_command_logs_device_id ON command_logs(device_id);
      CREATE INDEX IF NOT EXISTS idx_command_logs_created_at ON command_logs(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
      CREATE INDEX IF NOT EXISTS idx_api_keys_status ON api_keys(status);
      CREATE INDEX IF NOT EXISTS idx_device_group_members_group_id ON device_group_members(group_id);
      CREATE INDEX IF NOT EXISTS idx_device_group_members_device_id ON device_group_members(device_id);
    `);
  }

  private runEnrollStatement(
    input: EnrollDeviceInput,
    statement: { run: (params: Record<string, unknown>) => { changes: number } },
  ): { changes: number } {
    const now = new Date().toISOString();
    const capabilitiesJson = JSON.stringify(input.capabilities ?? []);

    return statement.run({
      device_id: input.deviceId,
      display_name: input.displayName ?? null,
      auth_token_hash: input.tokenHash,
      last_seen: now,
      version: input.version ?? null,
      hostname: input.hostname ?? null,
      username: input.username ?? null,
      capabilities_json: capabilitiesJson,
      created_at: now,
      updated_at: now,
    });
  }

  private mapDeviceRow(row: {
    device_id: string;
    display_name: string | null;
    status: "online" | "offline";
    last_seen: string;
    version: string | null;
    hostname: string | null;
    username: string | null;
    capabilities_json: string | null;
    created_at: string;
    updated_at: string;
  }): DeviceRecord {
    return {
      device_id: row.device_id,
      display_name: row.display_name,
      status: row.status,
      last_seen: row.last_seen,
      version: row.version,
      hostname: row.hostname,
      username: row.username,
      capabilities: parseJsonArray(row.capabilities_json),
      created_at: row.created_at,
      updated_at: row.updated_at,
    };
  }

  public enrollDevice(input: EnrollDeviceInput): void {
    const statement = this.db.prepare(`
      INSERT INTO devices (
        device_id,
        display_name,
        auth_token_hash,
        status,
        last_seen,
        version,
        hostname,
        username,
        capabilities_json,
        created_at,
        updated_at
      ) VALUES (
        @device_id,
        @display_name,
        @auth_token_hash,
        'offline',
        @last_seen,
        @version,
        @hostname,
        @username,
        @capabilities_json,
        @created_at,
        @updated_at
      )
      ON CONFLICT(device_id) DO UPDATE SET
        display_name = excluded.display_name,
        auth_token_hash = excluded.auth_token_hash,
        version = excluded.version,
        hostname = excluded.hostname,
        username = excluded.username,
        capabilities_json = excluded.capabilities_json,
        updated_at = excluded.updated_at
    `);

    this.runEnrollStatement(input, statement);
  }

  public enrollDeviceIfAbsent(input: EnrollDeviceInput): boolean {
    const statement = this.db.prepare(`
      INSERT OR IGNORE INTO devices (
        device_id,
        display_name,
        auth_token_hash,
        status,
        last_seen,
        version,
        hostname,
        username,
        capabilities_json,
        created_at,
        updated_at
      ) VALUES (
        @device_id,
        @display_name,
        @auth_token_hash,
        'offline',
        @last_seen,
        @version,
        @hostname,
        @username,
        @capabilities_json,
        @created_at,
        @updated_at
      )
    `);

    const result = this.runEnrollStatement(input, statement);
    return result.changes > 0;
  }

  public allocateNextDeviceId(prefix: string): string {
    const normalizedPrefix = prefix.toLowerCase().replace(/[^a-z]/g, "").slice(0, 4) || "m";
    const pattern = `${normalizedPrefix}%`;

    const rows = this.db
      .prepare("SELECT device_id FROM devices WHERE device_id LIKE ?")
      .all(pattern) as Array<{ device_id: string }>;

    let maxSuffix = 0;
    const exactPrefixRegex = new RegExp(`^${normalizedPrefix}(\\d+)$`);
    for (const row of rows) {
      const deviceId = String(row.device_id || "").toLowerCase();
      const match = deviceId.match(exactPrefixRegex);
      if (!match) {
        continue;
      }

      const value = Number.parseInt(match[1] ?? "", 10);
      if (Number.isFinite(value) && value > maxSuffix) {
        maxSuffix = value;
      }
    }

    return `${normalizedPrefix}${maxSuffix + 1}`;
  }

  public listExistingDeviceIds(deviceIds: string[]): Set<string> {
    const normalized = [...new Set(deviceIds.map((item) => item.trim().toLowerCase()).filter((item) => item.length > 0))];
    if (normalized.length === 0) {
      return new Set<string>();
    }

    const placeholders = normalized.map(() => "?").join(",");
    const sql = `SELECT device_id FROM devices WHERE device_id IN (${placeholders})`;
    const rows = this.db.prepare(sql).all(...normalized) as Array<{ device_id: string }>;
    return new Set(rows.map((row) => row.device_id));
  }

  public isValidDeviceToken(deviceId: string, rawToken: string): boolean {
    const row = this.db
      .prepare("SELECT auth_token_hash FROM devices WHERE device_id = ?")
      .get(deviceId) as { auth_token_hash: string } | undefined;

    if (!row) {
      return false;
    }

    return constantTimeEqual(row.auth_token_hash, sha256Hex(rawToken));
  }

  public getDevice(deviceId: string): DeviceRecord | null {
    const row = this.db
      .prepare(
        "SELECT device_id, display_name, status, last_seen, version, hostname, username, capabilities_json, created_at, updated_at FROM devices WHERE device_id = ?",
      )
      .get(deviceId) as
      | {
          device_id: string;
          display_name: string | null;
          status: "online" | "offline";
          last_seen: string;
          version: string | null;
          hostname: string | null;
          username: string | null;
          capabilities_json: string | null;
          created_at: string;
          updated_at: string;
        }
      | undefined;

    return row ? this.mapDeviceRow(row) : null;
  }

  public listDevices(): DeviceRecord[] {
    const rows = this.db
      .prepare(
        "SELECT device_id, display_name, status, last_seen, version, hostname, username, capabilities_json, created_at, updated_at FROM devices ORDER BY device_id ASC",
      )
      .all() as Array<{
      device_id: string;
      display_name: string | null;
      status: "online" | "offline";
      last_seen: string;
      version: string | null;
      hostname: string | null;
      username: string | null;
      capabilities_json: string | null;
      created_at: string;
      updated_at: string;
    }>;

    return rows.map((row) => this.mapDeviceRow(row));
  }

  public updateDeviceDisplayName(deviceId: string, displayName?: string): boolean {
    const now = new Date().toISOString();
    const result = this.db
      .prepare(
        `
          UPDATE devices
          SET display_name = @display_name,
              updated_at = @updated_at
          WHERE device_id = @device_id
        `,
      )
      .run({
        device_id: deviceId,
        display_name: displayName ?? null,
        updated_at: now,
      });

    return result.changes > 0;
  }

  public cloneDeviceWithNewId(currentDeviceId: string, nextDeviceId: string): boolean {
    if (currentDeviceId === nextDeviceId) {
      return true;
    }

    const now = new Date().toISOString();
    const transaction = this.db.transaction((sourceId: string, targetId: string) => {
      const source = this.db
        .prepare(
          `
            SELECT
              device_id,
              display_name,
              auth_token_hash,
              status,
              last_seen,
              version,
              hostname,
              username,
              capabilities_json,
              created_at,
              updated_at
            FROM devices
            WHERE device_id = ?
          `,
        )
        .get(sourceId) as
        | {
            device_id: string;
            display_name: string | null;
            auth_token_hash: string;
            status: string;
            last_seen: string;
            version: string | null;
            hostname: string | null;
            username: string | null;
            capabilities_json: string | null;
            created_at: string;
            updated_at: string;
          }
        | undefined;

      if (!source) {
        return false;
      }

      const existingTarget = this.db
        .prepare("SELECT 1 FROM devices WHERE device_id = ?")
        .get(targetId) as { 1: number } | undefined;
      if (existingTarget) {
        return false;
      }

      const displayName =
        source.display_name && source.display_name.trim().toLowerCase() === source.device_id.toLowerCase()
          ? targetId
          : source.display_name;

      const insertResult = this.db
        .prepare(
          `
            INSERT INTO devices (
              device_id,
              display_name,
              auth_token_hash,
              status,
              last_seen,
              version,
              hostname,
              username,
              capabilities_json,
              created_at,
              updated_at
            ) VALUES (
              @device_id,
              @display_name,
              @auth_token_hash,
              'offline',
              @last_seen,
              @version,
              @hostname,
              @username,
              @capabilities_json,
              @created_at,
              @updated_at
            )
          `,
        )
        .run({
          device_id: targetId,
          display_name: displayName,
          auth_token_hash: source.auth_token_hash,
          last_seen: source.last_seen,
          version: source.version,
          hostname: source.hostname,
          username: source.username,
          capabilities_json: source.capabilities_json ?? "[]",
          created_at: source.created_at,
          updated_at: now,
        });

      return insertResult.changes > 0;
    });

    return transaction(currentDeviceId, nextDeviceId);
  }

  public deleteDevice(deviceId: string): boolean {
    const result = this.db.prepare("DELETE FROM devices WHERE device_id = ?").run(deviceId);
    return result.changes > 0;
  }

  public markDeviceOnline(input: {
    deviceId: string;
    version?: string;
    hostname?: string;
    username?: string;
    capabilities?: string[];
  }): void {
    const now = new Date().toISOString();
    const capabilitiesJson = Array.isArray(input.capabilities)
      ? JSON.stringify(input.capabilities)
      : null;

    const statement = this.db.prepare(`
      UPDATE devices
      SET status = 'online',
          last_seen = @last_seen,
          version = COALESCE(@version, version),
          hostname = COALESCE(@hostname, hostname),
          username = COALESCE(@username, username),
          capabilities_json = COALESCE(@capabilities_json, capabilities_json),
          updated_at = @updated_at
      WHERE device_id = @device_id
    `);

    statement.run({
      device_id: input.deviceId,
      last_seen: now,
      version: input.version ?? null,
      hostname: input.hostname ?? null,
      username: input.username ?? null,
      capabilities_json: capabilitiesJson,
      updated_at: now,
    });
  }

  public markDeviceOffline(deviceId: string): void {
    const now = new Date().toISOString();

    this.db
      .prepare(
        "UPDATE devices SET status = 'offline', updated_at = @updated_at WHERE device_id = @device_id",
      )
      .run({ device_id: deviceId, updated_at: now });
  }

  public touchHeartbeat(deviceId: string): void {
    const now = new Date().toISOString();

    this.db
      .prepare(
        "UPDATE devices SET last_seen = @last_seen, status = 'online', updated_at = @updated_at WHERE device_id = @device_id",
      )
      .run({ device_id: deviceId, last_seen: now, updated_at: now });
  }

  public insertCommandLog(input: CommandLogInsert): void {
    const now = new Date().toISOString();

    this.db
      .prepare(`
        INSERT OR REPLACE INTO command_logs (
          id,
          request_id,
          device_id,
          source,
          raw_text,
          parsed_target,
          parsed_type,
          args_json,
          status,
          result_message,
          error_code,
          created_at,
          completed_at
        ) VALUES (
          @id,
          @request_id,
          @device_id,
          @source,
          @raw_text,
          @parsed_target,
          @parsed_type,
          @args_json,
          @status,
          @result_message,
          @error_code,
          @created_at,
          @completed_at
        )
      `)
      .run({
        id: input.id,
        request_id: input.requestId,
        device_id: input.deviceId,
        source: input.source,
        raw_text: input.rawText,
        parsed_target: input.parsedTarget,
        parsed_type: input.parsedType,
        args_json: input.argsJson,
        status: input.status,
        result_message: input.resultMessage,
        error_code: input.errorCode ?? null,
        created_at: now,
        completed_at: null,
      });
  }

  public completeCommandLog(input: {
    id: string;
    status: string;
    resultMessage: string;
    errorCode?: string;
  }): void {
    const completedAt = new Date().toISOString();

    this.db
      .prepare(
        "UPDATE command_logs SET status = @status, result_message = @result_message, error_code = @error_code, completed_at = @completed_at WHERE id = @id",
      )
      .run({
        id: input.id,
        status: input.status,
        result_message: input.resultMessage,
        error_code: input.errorCode ?? null,
        completed_at: completedAt,
      });
  }

  public listCommandLogs(input: CommandLogQuery): CommandLogRecord[] {
    const where: string[] = [];
    const params: Record<string, unknown> = {
      limit: normalizeLimit(input.limit, 100, 500),
    };

    if (input.before) {
      where.push("created_at < @before");
      params.before = input.before;
    }

    if (input.deviceId) {
      where.push("device_id = @device_id");
      params.device_id = input.deviceId;
    }

    if (input.requestId) {
      where.push("request_id = @request_id");
      params.request_id = input.requestId;
    }

    if (input.parsedType) {
      where.push("parsed_type = @parsed_type");
      params.parsed_type = input.parsedType;
    }

    if (input.status) {
      where.push("status = @status");
      params.status = input.status;
    }

    const sql = `
      SELECT
        id,
        request_id,
        device_id,
        source,
        raw_text,
        parsed_target,
        parsed_type,
        args_json,
        status,
        result_message,
        error_code,
        created_at,
        completed_at
      FROM command_logs
      ${where.length > 0 ? `WHERE ${where.join(" AND ")}` : ""}
      ORDER BY created_at DESC
      LIMIT @limit
    `;

    const rows = this.db.prepare(sql).all(params) as Array<{
      id: string;
      request_id: string;
      device_id: string;
      source: string;
      raw_text: string;
      parsed_target: string;
      parsed_type: string;
      args_json: string;
      status: string;
      result_message: string | null;
      error_code: string | null;
      created_at: string;
      completed_at: string | null;
    }>;

    return rows.map((row) => ({
      id: row.id,
      request_id: row.request_id,
      device_id: row.device_id,
      source: row.source,
      raw_text: row.raw_text,
      parsed_target: row.parsed_target,
      parsed_type: row.parsed_type,
      args: parseJsonObject(row.args_json),
      status: row.status,
      result_message: row.result_message,
      error_code: row.error_code,
      created_at: row.created_at,
      completed_at: row.completed_at,
    }));
  }

  public createApiKey(input: {
    keyId: string;
    name: string;
    tokenHash: string;
    scopes: string[];
  }): ApiKeyRecord {
    const now = new Date().toISOString();

    this.db
      .prepare(
        `
          INSERT INTO api_keys (
            key_id,
            name,
            token_hash,
            scopes_json,
            status,
            created_at,
            updated_at,
            last_used_at
          ) VALUES (
            @key_id,
            @name,
            @token_hash,
            @scopes_json,
            'active',
            @created_at,
            @updated_at,
            NULL
          )
        `,
      )
      .run({
        key_id: input.keyId,
        name: input.name,
        token_hash: input.tokenHash,
        scopes_json: JSON.stringify(input.scopes),
        created_at: now,
        updated_at: now,
      });

    const created = this.getApiKeyById(input.keyId);
    if (!created) {
      throw new Error("Failed to create API key");
    }

    return created;
  }

  public getApiKeyById(keyId: string): ApiKeyRecord | null {
    const row = this.db
      .prepare(
        "SELECT key_id, name, scopes_json, status, created_at, updated_at, last_used_at FROM api_keys WHERE key_id = ?",
      )
      .get(keyId) as
      | {
          key_id: string;
          name: string;
          scopes_json: string;
          status: "active" | "revoked";
          created_at: string;
          updated_at: string;
          last_used_at: string | null;
        }
      | undefined;

    if (!row) {
      return null;
    }

    return {
      key_id: row.key_id,
      name: row.name,
      scopes: parseJsonArray(row.scopes_json),
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      last_used_at: row.last_used_at,
    };
  }

  public listApiKeys(): ApiKeyRecord[] {
    const rows = this.db
      .prepare(
        "SELECT key_id, name, scopes_json, status, created_at, updated_at, last_used_at FROM api_keys ORDER BY created_at DESC",
      )
      .all() as Array<{
      key_id: string;
      name: string;
      scopes_json: string;
      status: "active" | "revoked";
      created_at: string;
      updated_at: string;
      last_used_at: string | null;
    }>;

    return rows.map((row) => ({
      key_id: row.key_id,
      name: row.name,
      scopes: parseJsonArray(row.scopes_json),
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      last_used_at: row.last_used_at,
    }));
  }

  public resolveApiKeyByToken(rawToken: string): ApiKeyLookup | null {
    const tokenHash = sha256Hex(rawToken);

    const row = this.db
      .prepare(
        "SELECT key_id, name, token_hash, scopes_json, status, created_at, updated_at, last_used_at FROM api_keys WHERE token_hash = ?",
      )
      .get(tokenHash) as
      | {
          key_id: string;
          name: string;
          token_hash: string;
          scopes_json: string;
          status: "active" | "revoked";
          created_at: string;
          updated_at: string;
          last_used_at: string | null;
        }
      | undefined;

    if (!row) {
      return null;
    }

    return {
      key_id: row.key_id,
      name: row.name,
      token_hash: row.token_hash,
      scopes: parseJsonArray(row.scopes_json),
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      last_used_at: row.last_used_at,
    };
  }

  public revokeApiKey(keyId: string): boolean {
    const now = new Date().toISOString();
    const result = this.db
      .prepare("UPDATE api_keys SET status = 'revoked', updated_at = @updated_at WHERE key_id = @key_id")
      .run({ key_id: keyId, updated_at: now });

    return result.changes > 0;
  }

  public touchApiKeyUsage(keyId: string): void {
    const now = new Date().toISOString();
    this.db
      .prepare("UPDATE api_keys SET last_used_at = @last_used_at, updated_at = @updated_at WHERE key_id = @key_id")
      .run({
        key_id: keyId,
        last_used_at: now,
        updated_at: now,
      });
  }

  private listGroupMembers(groupIds: string[]): Map<string, string[]> {
    const out = new Map<string, string[]>();
    if (groupIds.length === 0) {
      return out;
    }

    const placeholders = groupIds.map(() => "?").join(",");
    const sql = `
      SELECT group_id, device_id
      FROM device_group_members
      WHERE group_id IN (${placeholders})
      ORDER BY group_id ASC, device_id ASC
    `;

    const rows = this.db.prepare(sql).all(...groupIds) as Array<{ group_id: string; device_id: string }>;
    for (const row of rows) {
      const list = out.get(row.group_id) ?? [];
      list.push(row.device_id);
      out.set(row.group_id, list);
    }

    return out;
  }

  public getDeviceGroup(groupId: string): DeviceGroupRecord | null {
    const row = this.db
      .prepare(
        "SELECT group_id, display_name, description, created_at, updated_at FROM device_groups WHERE group_id = ?",
      )
      .get(groupId) as
      | {
          group_id: string;
          display_name: string;
          description: string | null;
          created_at: string;
          updated_at: string;
        }
      | undefined;

    if (!row) {
      return null;
    }

    const members = this.listGroupMembers([groupId]).get(groupId) ?? [];

    return {
      group_id: row.group_id,
      display_name: row.display_name,
      description: row.description,
      device_ids: members,
      created_at: row.created_at,
      updated_at: row.updated_at,
    };
  }

  public listDeviceGroups(): DeviceGroupRecord[] {
    const groups = this.db
      .prepare(
        "SELECT group_id, display_name, description, created_at, updated_at FROM device_groups ORDER BY display_name COLLATE NOCASE ASC, group_id ASC",
      )
      .all() as Array<{
      group_id: string;
      display_name: string;
      description: string | null;
      created_at: string;
      updated_at: string;
    }>;

    const membersByGroup = this.listGroupMembers(groups.map((group) => group.group_id));

    return groups.map((group) => ({
      group_id: group.group_id,
      display_name: group.display_name,
      description: group.description,
      device_ids: membersByGroup.get(group.group_id) ?? [],
      created_at: group.created_at,
      updated_at: group.updated_at,
    }));
  }

  public upsertDeviceGroup(input: {
    groupId: string;
    displayName: string;
    description?: string;
    deviceIds: string[];
  }): DeviceGroupRecord | null {
    const now = new Date().toISOString();
    const uniqueDeviceIds = [...new Set(input.deviceIds.map((item) => item.trim().toLowerCase()).filter((item) => item.length > 0))];

    const tx = this.db.transaction(() => {
      this.db
        .prepare(
          `
            INSERT INTO device_groups (
              group_id,
              display_name,
              description,
              created_at,
              updated_at
            ) VALUES (
              @group_id,
              @display_name,
              @description,
              @created_at,
              @updated_at
            )
            ON CONFLICT(group_id) DO UPDATE SET
              display_name = excluded.display_name,
              description = excluded.description,
              updated_at = excluded.updated_at
          `,
        )
        .run({
          group_id: input.groupId,
          display_name: input.displayName,
          description: input.description?.trim() ? input.description.trim() : null,
          created_at: now,
          updated_at: now,
        });

      this.db.prepare("DELETE FROM device_group_members WHERE group_id = ?").run(input.groupId);

      const insertMember = this.db.prepare(
        "INSERT INTO device_group_members (group_id, device_id, created_at) VALUES (@group_id, @device_id, @created_at)",
      );

      for (const deviceId of uniqueDeviceIds) {
        insertMember.run({
          group_id: input.groupId,
          device_id: deviceId,
          created_at: now,
        });
      }
    });

    tx();
    return this.getDeviceGroup(input.groupId);
  }

  public deleteDeviceGroup(groupId: string): boolean {
    const result = this.db.prepare("DELETE FROM device_groups WHERE group_id = ?").run(groupId);
    return result.changes > 0;
  }

  public healthSnapshot(): {
    deviceCount: number;
    onlineDeviceCount: number;
    commandLogCount: number;
    groupCount: number;
    apiKeyCount: number;
  } {
    const deviceCountRow = this.db.prepare("SELECT COUNT(1) AS count FROM devices").get() as
      | { count: number }
      | undefined;

    const onlineCountRow = this.db
      .prepare("SELECT COUNT(1) AS count FROM devices WHERE status = 'online'")
      .get() as { count: number } | undefined;

    const commandLogCountRow = this.db.prepare("SELECT COUNT(1) AS count FROM command_logs").get() as
      | { count: number }
      | undefined;

    const groupCountRow = this.db.prepare("SELECT COUNT(1) AS count FROM device_groups").get() as
      | { count: number }
      | undefined;

    const apiKeyCountRow = this.db.prepare("SELECT COUNT(1) AS count FROM api_keys").get() as
      | { count: number }
      | undefined;

    return {
      deviceCount: deviceCountRow?.count ?? 0,
      onlineDeviceCount: onlineCountRow?.count ?? 0,
      commandLogCount: commandLogCountRow?.count ?? 0,
      groupCount: groupCountRow?.count ?? 0,
      apiKeyCount: apiKeyCountRow?.count ?? 0,
    };
  }

  public close(): void {
    this.db.close();
  }
}
