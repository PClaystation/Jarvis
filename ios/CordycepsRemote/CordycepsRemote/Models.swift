import Foundation

enum JSONValue: Decodable, Hashable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
      return
    }
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
      return
    }
    if let value = try? container.decode(Double.self) {
      self = .number(value)
      return
    }
    if let value = try? container.decode(String.self) {
      self = .string(value)
      return
    }
    if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
      return
    }
    if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
      return
    }

    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "Unsupported JSON value."
    )
  }

  var compactText: String {
    switch self {
    case let .string(value):
      return value
    case let .number(value):
      if value.rounded() == value {
        return String(Int(value))
      }
      return String(value)
    case let .bool(value):
      return value ? "true" : "false"
    case let .array(values):
      return values.map(\.compactText).joined(separator: ", ")
    case let .object(map):
      let keys = map.keys.sorted()
      if keys.isEmpty {
        return "{}"
      }
      return keys.map { "\($0)=\(map[$0]?.compactText ?? "null")" }.joined(separator: ", ")
    case .null:
      return "null"
    }
  }
}

struct DeviceRecord: Decodable, Identifiable, Hashable {
  private static let preciseFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let fallbackFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  let device_id: String
  let display_name: String?
  let status: String
  let last_seen: String
  let version: String?
  let hostname: String?
  let username: String?
  let capabilities: [String]?
  let profile: String?
  let device_info: [String: JSONValue]?
  let created_at: String?
  let updated_at: String?
  let quarantine_enabled: Bool?
  let kill_switch_enabled: Bool?
  let quarantine_reason: String?

  var id: String { device_id }

  var isOnline: Bool {
    status.lowercased() == "online"
  }

  var displayTitle: String {
    if let display_name, !display_name.trimmed.isEmpty {
      return display_name.trimmed
    }
    return device_id
  }

  var subtitleLabel: String? {
    var parts: [String] = []

    if displayTitle != device_id {
      parts.append(device_id)
    }

    if let hostname, !hostname.trimmed.isEmpty {
      parts.append(hostname.trimmed)
    }

    if let username, !username.trimmed.isEmpty {
      parts.append(username.trimmed)
    }

    if parts.isEmpty {
      return nil
    }
    return parts.joined(separator: " • ")
  }

  var lastSeenLabel: String {
    guard let date = DeviceRecord.preciseFormatter.date(from: last_seen)
      ?? DeviceRecord.fallbackFormatter.date(from: last_seen)
    else {
      return last_seen
    }

    return DateFormatter.cordyceps.string(from: date)
  }

  var agentVersionLabel: String {
    let normalized = version?.trimmed ?? ""
    if normalized.isEmpty {
      return "unknown"
    }
    return normalized
  }
}

struct DevicesResponse: Decodable {
  let ok: Bool
  let devices: [DeviceRecord]
}

struct CommandLogEntry: Decodable, Identifiable, Hashable {
  let id: String
  let request_id: String
  let device_id: String
  let source: String
  let raw_text: String
  let parsed_target: String
  let parsed_type: String
  let status: String
  let result_message: String?
  let error_code: String?
  let created_at: String
  let completed_at: String?
}

struct CommandLogsResponse: Decodable {
  let ok: Bool
  let count: Int?
  let next_before: String?
  let logs: [CommandLogEntry]
}

struct GroupRecord: Decodable, Identifiable, Hashable {
  let group_id: String
  let display_name: String
  let description: String?
  let device_ids: [String]
  let online_count: Int?
  let created_at: String?
  let updated_at: String?

  var id: String { group_id }
}

struct GroupsResponse: Decodable {
  let ok: Bool
  let groups: [GroupRecord]
}

struct GroupResponse: Decodable {
  let ok: Bool
  let group: GroupRecord?
  let message: String?
  let error_code: String?
}

struct DeviceResponse: Decodable {
  let ok: Bool
  let device: DeviceRecord?
  let message: String?
  let error_code: String?
}

struct DeviceRealtimeRecord: Decodable, Hashable {
  let connected: Bool
  let connected_at: String?
  let last_seen_at: String?
  let device_info: [String: JSONValue]?
}

struct QueuedUpdateRecord: Decodable, Identifiable, Hashable {
  let id: String?
  let request_id: String?
  let device_id: String?
  let version: String
  let package_url: String
  let sha256: String?
  let created_at: String

  var stableID: String {
    if let id, !id.isEmpty {
      return id
    }
    return "\(request_id ?? "req"):\(device_id ?? "dev"):\(version):\(created_at)"
  }
}

struct DeviceInspectorResponse: Decodable {
  let ok: Bool
  let device: DeviceRecord
  let realtime: DeviceRealtimeRecord
  let aliases: [DeviceAppAliasRecord]
  let queued_updates: [QueuedUpdateRecord]
  let recent_logs: [CommandLogEntry]
}

struct DeviceDeleteResponse: Decodable {
  let ok: Bool
  let device_id: String?
  let message: String?
  let error_code: String?
}

struct DeviceControlRecord: Decodable, Hashable {
  let device_id: String
  let quarantine_enabled: Bool
  let kill_switch_enabled: Bool
  let reason: String?
  let updated_at: String
}

struct DeviceLockdownResult: Decodable, Hashable {
  let attempted: Bool
  let command_type: String
  let lockdown_minutes: Int?
  let ok: Bool
  let message: String
  let error_code: String?
}

struct DeviceControlResponse: Decodable {
  let ok: Bool
  let device_id: String?
  let control: DeviceControlRecord?
  let lockdown: DeviceLockdownResult?
  let disconnected: Bool?
  let message: String?
  let error_code: String?
}

struct DeviceAppAliasRecord: Decodable, Identifiable, Hashable {
  let device_id: String
  let alias: String
  let app: String
  let created_at: String?
  let updated_at: String?

  var id: String { alias }
}

struct DeviceAppAliasesResponse: Decodable {
  let ok: Bool
  let device_id: String?
  let aliases: [DeviceAppAliasRecord]
  let message: String?
  let error_code: String?
}

struct APIKeyRecord: Decodable, Identifiable, Hashable {
  let key_id: String
  let name: String
  let scopes: [String]
  let status: String
  let created_at: String
  let updated_at: String
  let last_used_at: String?

  var id: String { key_id }
}

struct APIKeysResponse: Decodable {
  let ok: Bool
  let keys: [APIKeyRecord]
}

struct APIKeyCreateResponse: Decodable {
  let ok: Bool
  let key: APIKeyRecord?
  let api_key: String?
  let message: String?
  let error_code: String?
}

struct APIKeyRotateResponse: Decodable {
  let ok: Bool
  let rotated_from: String?
  let key: APIKeyRecord?
  let api_key: String?
  let message: String?
  let error_code: String?
}

struct TokenRotationResponse: Decodable {
  let ok: Bool
  let rotated_owner_token: Bool?
  let rotated_bootstrap_token: Bool?
  let owner_token: String?
  let bootstrap_token: String?
  let owner_grace_seconds: Int?
  let previous_owner_token_valid_until: String?
  let message: String?
  let error_code: String?
}

struct DispatchResult: Decodable, Hashable {
  let device_id: String
  let ok: Bool
  let message: String
  let error_code: String?
}

struct CommandResponse: Decodable {
  let ok: Bool
  let request_id: String?
  let target: String?
  let parsed_type: String?
  let message: String?
  let error_code: String?
  let result: DispatchResult?
  let results: [DispatchResult]?
}

struct UpdateResponse: Decodable {
  let ok: Bool
  let request_id: String?
  let target: String?
  let parsed_type: String?
  let message: String?
  let error_code: String?
  let version: String?
  let package_url: String?
  let sha256: String?
  let hash_source: String?
  let package_size_bytes: Int?
  let signature: String?
  let signature_key_id: String?
  let signature_verified: Bool?
  let use_privileged_helper: Bool?
  let queued: Bool?
  let result: DispatchResult?
  let results: [DispatchResult]?
}

struct ErrorResponse: Decodable {
  let ok: Bool?
  let message: String?
  let error: String?
  let error_code: String?
}

struct CommandRequest: Encodable {
  let request_id: String
  let text: String
  let source: String
  let is_async: Bool
  let timeout_ms: Int?
  let sent_at: String
  let client_version: String

  enum CodingKeys: String, CodingKey {
    case request_id
    case text
    case source
    case is_async = "async"
    case timeout_ms
    case sent_at
    case client_version
  }
}

struct UpdateRequest: Encodable {
  let request_id: String
  let source: String
  let target: String
  let version: String
  let package_url: String
  let queue_if_offline: Bool?
  let sha256: String?
  let size_bytes: Int?
  let signature: String?
  let signature_key_id: String?
  let use_privileged_helper: Bool?
}

struct TokenRotationRequest: Encodable {
  let rotate_owner_token: Bool
  let rotate_bootstrap_token: Bool
  let owner_grace_seconds: Int?
}

struct DeviceDisplayNameUpsertRequest: Encodable {
  let display_name: String
}

struct DeviceAppAliasUpsertEntry: Encodable {
  let alias: String
  let app: String
}

struct DeviceAppAliasesUpsertRequest: Encodable {
  let aliases: [DeviceAppAliasUpsertEntry]
}

struct DeviceControlRequest: Encodable {
  let quarantine_enabled: Bool?
  let kill_switch_enabled: Bool?
  let reason: String?
  let enforce_lockdown: Bool?
  let trigger_lockdown: Bool?
  let lockdown_minutes: Int?
}

struct GroupUpsertRequest: Encodable {
  let display_name: String
  let description: String?
  let device_ids: [String]
}

struct GroupCommandRequest: Encodable {
  let request_id: String
  let text: String
  let source: String
  let confirm_bulk: Bool
}

struct APIKeyCreateRequest: Encodable {
  let name: String
  let scopes: [String]
}

struct APIResponse<T> {
  let body: T
  let rawJSON: String
  let latencyMs: Double
  let statusCode: Int
}

enum ConnectionState: String {
  case connected
  case retrying
  case disconnected
}

struct CommandCategoryGroup: Identifiable, Hashable {
  let category: String
  let entries: [CommandLibraryEntry]
  var id: String { category }
}

struct CommandLibraryEntry: Identifiable, Hashable {
  let value: String
  let label: String
  let category: String
  let keywords: [String]

  var id: String { value }

  var normalizedValue: String {
    value.normalizedActionText
  }

  var searchText: String {
    "\(normalizedValue) \(label.lowercased()) \(category.lowercased()) \(keywords.joined(separator: " ").lowercased())"
  }

  var isDangerous: Bool {
    CommandLibrary.dangerousActions.contains(normalizedValue)
  }

  var usesArgument: Bool {
    normalizedValue == "notify" ||
      normalizedValue == "clipboard" ||
      normalizedValue == "copy" ||
      normalizedValue == "type" ||
      CommandLibrary.repeatableActions.contains(normalizedValue)
  }

  var placeholderArgument: String {
    if normalizedValue == "notify" {
      return "hello"
    }

    if normalizedValue == "clipboard" || normalizedValue == "copy" {
      return "copied from cordyceps"
    }

    if normalizedValue == "type" {
      return "text to type"
    }

    if normalizedValue == "brightness up" || normalizedValue == "brightness down" {
      return "optional percent"
    }

    if CommandLibrary.repeatableActions.contains(normalizedValue) {
      return "optional repeat count"
    }

    return ""
  }
}

enum CommandLibrary {
  static let entries: [CommandLibraryEntry] = [
    .init(value: "ping", label: "ping", category: "Connectivity", keywords: ["status", "health", "check"]),
    .init(value: "play", label: "play", category: "Media", keywords: ["resume"]),
    .init(value: "pause", label: "pause", category: "Media", keywords: ["stop"]),
    .init(value: "play pause", label: "play pause", category: "Media", keywords: ["toggle"]),
    .init(value: "next", label: "next", category: "Media", keywords: ["skip", "next track", "repeat"]),
    .init(value: "previous", label: "previous", category: "Media", keywords: ["back", "prev", "previous track", "repeat"]),
    .init(value: "volume up", label: "volume up", category: "Volume", keywords: ["louder", "vol up", "volume higher", "repeat"]),
    .init(value: "volume down", label: "volume down", category: "Volume", keywords: ["quieter", "vol down", "volume lower", "repeat"]),
    .init(value: "brightness up", label: "brightness up", category: "Display", keywords: ["brighter", "increase brightness", "screen brighter", "optional percent"]),
    .init(value: "brightness down", label: "brightness down", category: "Display", keywords: ["dimmer", "decrease brightness", "dim screen", "optional percent"]),
    .init(value: "mute", label: "mute", category: "Volume", keywords: ["mute volume", "silence", "unmute"]),
    .init(value: "f1", label: "f1", category: "Keyboard", keywords: ["press f1", "function key"]),
    .init(value: "f2", label: "f2", category: "Keyboard", keywords: ["press f2", "function key"]),
    .init(value: "f3", label: "f3", category: "Keyboard", keywords: ["press f3", "function key"]),
    .init(value: "f4", label: "f4", category: "Keyboard", keywords: ["press f4", "function key"]),
    .init(value: "f5", label: "f5", category: "Keyboard", keywords: ["press f5", "function key"]),
    .init(value: "f6", label: "f6", category: "Keyboard", keywords: ["press f6", "function key"]),
    .init(value: "f7", label: "f7", category: "Keyboard", keywords: ["press f7", "function key"]),
    .init(value: "f8", label: "f8", category: "Keyboard", keywords: ["press f8", "function key"]),
    .init(value: "f9", label: "f9", category: "Keyboard", keywords: ["press f9", "function key"]),
    .init(value: "f10", label: "f10", category: "Keyboard", keywords: ["press f10", "function key"]),
    .init(value: "f11", label: "f11", category: "Keyboard", keywords: ["press f11", "function key"]),
    .init(value: "f12", label: "f12", category: "Keyboard", keywords: ["press f12", "function key"]),
    .init(value: "enter", label: "enter", category: "Keyboard", keywords: ["return", "press enter"]),
    .init(value: "escape", label: "escape", category: "Keyboard", keywords: ["esc", "press escape"]),
    .init(value: "tab", label: "tab", category: "Keyboard", keywords: ["press tab"]),
    .init(value: "space", label: "space", category: "Keyboard", keywords: ["space bar", "press space"]),
    .init(value: "up", label: "up", category: "Keyboard", keywords: ["arrow up", "up arrow"]),
    .init(value: "down", label: "down", category: "Keyboard", keywords: ["arrow down", "down arrow"]),
    .init(value: "left", label: "left", category: "Keyboard", keywords: ["arrow left", "left arrow"]),
    .init(value: "right", label: "right", category: "Keyboard", keywords: ["arrow right", "right arrow"]),
    .init(value: "backspace", label: "backspace", category: "Keyboard", keywords: ["press backspace"]),
    .init(value: "delete", label: "delete", category: "Keyboard", keywords: ["del", "press delete"]),
    .init(value: "home", label: "home", category: "Keyboard", keywords: ["press home"]),
    .init(value: "end", label: "end", category: "Keyboard", keywords: ["press end"]),
    .init(value: "page up", label: "page up", category: "Keyboard", keywords: ["pgup"]),
    .init(value: "page down", label: "page down", category: "Keyboard", keywords: ["pgdn"]),
    .init(value: "copy shortcut", label: "copy shortcut", category: "Keyboard", keywords: ["ctrl c"]),
    .init(value: "paste shortcut", label: "paste shortcut", category: "Keyboard", keywords: ["ctrl v"]),
    .init(value: "cut shortcut", label: "cut shortcut", category: "Keyboard", keywords: ["ctrl x"]),
    .init(value: "undo shortcut", label: "undo shortcut", category: "Keyboard", keywords: ["ctrl z"]),
    .init(value: "redo shortcut", label: "redo shortcut", category: "Keyboard", keywords: ["ctrl y"]),
    .init(value: "select all shortcut", label: "select all shortcut", category: "Keyboard", keywords: ["ctrl a"]),
    .init(value: "alt tab", label: "alt tab", category: "Keyboard", keywords: ["switch app", "task switch"]),
    .init(value: "alt f4", label: "alt f4", category: "Keyboard", keywords: ["close window", "quit app"]),
    .init(value: "type", label: "type (requires text)", category: "Keyboard", keywords: ["type text", "keyboard text", "text input"]),
    .init(value: "open spotify", label: "open spotify", category: "Apps", keywords: ["launch spotify"]),
    .init(value: "open discord", label: "open discord", category: "Apps", keywords: ["launch discord"]),
    .init(value: "open chrome", label: "open chrome", category: "Apps", keywords: ["browser"]),
    .init(value: "open steam", label: "open steam", category: "Apps", keywords: ["games"]),
    .init(value: "open explorer", label: "open explorer", category: "Apps", keywords: ["file explorer", "windows explorer", "files"]),
    .init(value: "open vscode", label: "open vscode", category: "Apps", keywords: ["vs code", "visual studio code", "editor", "code"]),
    .init(value: "open edge", label: "open edge", category: "Apps", keywords: ["microsoft edge", "browser"]),
    .init(value: "open firefox", label: "open firefox", category: "Apps", keywords: ["browser"]),
    .init(value: "open notepad", label: "open notepad", category: "Apps", keywords: ["text"]),
    .init(value: "open calculator", label: "open calculator", category: "Apps", keywords: ["calc"]),
    .init(value: "open settings", label: "open settings", category: "Apps", keywords: ["windows settings"]),
    .init(value: "open slack", label: "open slack", category: "Apps", keywords: ["chat"]),
    .init(value: "open teams", label: "open teams", category: "Apps", keywords: ["meeting", "chat"]),
    .init(value: "open task manager", label: "open task manager", category: "Apps", keywords: ["taskmanager", "process"]),
    .init(value: "open terminal", label: "open terminal", category: "Apps", keywords: ["windows terminal", "wt"]),
    .init(value: "open powershell", label: "open powershell", category: "Apps", keywords: ["power shell", "shell"]),
    .init(value: "open cmd", label: "open cmd", category: "Apps", keywords: ["command prompt"]),
    .init(value: "open control panel", label: "open control panel", category: "Apps", keywords: ["controlpanel"]),
    .init(value: "open paint", label: "open paint", category: "Apps", keywords: ["mspaint"]),
    .init(value: "open snipping tool", label: "open snipping tool", category: "Apps", keywords: ["snippingtool", "screenshot"]),
    .init(value: "lock", label: "lock", category: "Power", keywords: ["lock pc"]),
    .init(value: "lock pc", label: "lock pc", category: "Power", keywords: ["lock"]),
    .init(value: "display off", label: "display off", category: "Power", keywords: ["screen off", "monitor off"]),
    .init(value: "screen off", label: "screen off", category: "Power", keywords: ["display off", "monitor off"]),
    .init(value: "monitor off", label: "monitor off", category: "Power", keywords: ["display off", "screen off"]),
    .init(value: "sleep", label: "sleep", category: "Power", keywords: ["sleep pc"]),
    .init(value: "sleep pc", label: "sleep pc", category: "Power", keywords: ["sleep"]),
    .init(value: "sign out", label: "sign out", category: "Power", keywords: ["log out", "logout"]),
    .init(value: "log out", label: "log out", category: "Power", keywords: ["sign out", "logout"]),
    .init(value: "logout", label: "logout", category: "Power", keywords: ["sign out", "log out"]),
    .init(value: "shutdown", label: "shutdown", category: "Power", keywords: ["shut down", "shutdown pc"]),
    .init(value: "restart", label: "restart", category: "Power", keywords: ["reboot", "restart pc"]),
    .init(value: "notify", label: "notify (requires message)", category: "Messaging", keywords: ["alert", "notification"]),
    .init(value: "clipboard", label: "clipboard (requires text)", category: "Messaging", keywords: ["copy", "copy text"]),
    .init(value: "copy", label: "copy (requires text)", category: "Messaging", keywords: ["clipboard", "copy text"]),
  ]

  static let knownActionValues = Set(entries.map { $0.normalizedValue })
  static let actionAliases: [String: String] = [
    "status": "ping",
    "resume": "play",
    "toggle": "play pause",
    "next track": "next",
    "skip": "next",
    "skip track": "next",
    "previous track": "previous",
    "prev": "previous",
    "back": "previous",
    "vol up": "volume up",
    "louder": "volume up",
    "volume higher": "volume up",
    "vol down": "volume down",
    "quieter": "volume down",
    "volume lower": "volume down",
    "brighter": "brightness up",
    "increase brightness": "brightness up",
    "raise brightness": "brightness up",
    "dimmer": "brightness down",
    "decrease brightness": "brightness down",
    "lower brightness": "brightness down",
    "dim screen": "brightness down",
    "mute volume": "mute",
    "press f1": "f1",
    "press f2": "f2",
    "press f3": "f3",
    "press f4": "f4",
    "press f5": "f5",
    "press f6": "f6",
    "press f7": "f7",
    "press f8": "f8",
    "press f9": "f9",
    "press f10": "f10",
    "press f11": "f11",
    "press f12": "f12",
    "return": "enter",
    "press enter": "enter",
    "esc": "escape",
    "press escape": "escape",
    "press esc": "escape",
    "press tab": "tab",
    "space bar": "space",
    "press space": "space",
    "arrow up": "up",
    "up arrow": "up",
    "arrow down": "down",
    "down arrow": "down",
    "arrow left": "left",
    "left arrow": "left",
    "arrow right": "right",
    "right arrow": "right",
    "press backspace": "backspace",
    "del": "delete",
    "press delete": "delete",
    "press home": "home",
    "press end": "end",
    "pgup": "page up",
    "pgdn": "page down",
    "ctrl c": "copy shortcut",
    "ctrl v": "paste shortcut",
    "ctrl x": "cut shortcut",
    "ctrl z": "undo shortcut",
    "ctrl y": "redo shortcut",
    "ctrl a": "select all shortcut",
    "switch app": "alt tab",
    "task switch": "alt tab",
    "close window": "alt f4",
    "quit app": "alt f4",
    "type text": "type",
    "keyboard type": "type",
    "keyboard text": "type",
    "open file explorer": "open explorer",
    "open vs code": "open vscode",
    "open visual studio code": "open vscode",
    "open microsoft edge": "open edge",
    "open calc": "open calculator",
    "open taskmanager": "open task manager",
    "open windows terminal": "open terminal",
    "open power shell": "open powershell",
    "open command prompt": "open cmd",
    "open mspaint": "open paint",
    "lock pc": "lock",
    "sleep pc": "sleep",
    "shut down": "shutdown",
    "shutdown pc": "shutdown",
    "reboot": "restart",
    "restart pc": "restart",
  ]
  static let repeatableActions: Set<String> = [
    "volume up",
    "volume down",
    "brightness up",
    "brightness down",
    "next",
    "previous",
  ]
  static let dangerousActions: Set<String> = [
    "shutdown",
    "restart",
    "sleep",
    "sleep pc",
    "sign out",
    "log out",
    "logout",
  ]

  static let quickActions: [String] = [
    "ping",
    "play pause",
    "brightness up",
    "next",
    "volume up",
    "volume down",
    "mute",
    "lock",
    "restart",
  ]

  static func entry(for value: String) -> CommandLibraryEntry? {
    let normalized = value.normalizedActionText
    return entries.first(where: { $0.normalizedValue == normalized })
  }

  static func filteredEntries(matching query: String) -> [CommandLibraryEntry] {
    let normalized = query.normalizedActionText
    if normalized.isEmpty {
      return entries
    }

    let terms = normalized.split(separator: " ").map(String.init)
    return entries.filter { entry in
      terms.allSatisfy { term in
        entry.searchText.contains(term)
      }
    }
  }

  static func grouped(entries: [CommandLibraryEntry]) -> [CommandCategoryGroup] {
    let sorted = entries.sorted {
      if $0.category == $1.category {
        return $0.label < $1.label
      }
      return $0.category < $1.category
    }

    let groupedDict = Dictionary(grouping: sorted, by: \.category)
    return groupedDict.keys.sorted().map { category in
      CommandCategoryGroup(category: category, entries: groupedDict[category] ?? [])
    }
  }

  static func safeAction(_ value: String) -> String {
    let normalized = value.normalizedActionText
    let canonical = actionAliases[normalized] ?? normalized
    if knownActionValues.contains(canonical) {
      return canonical
    }
    return "ping"
  }
}

extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var normalizedActionText: String {
    lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }

  var decodedURLValue: String {
    replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? self
  }
}

extension DateFormatter {
  static let cordyceps: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
  }()
}
