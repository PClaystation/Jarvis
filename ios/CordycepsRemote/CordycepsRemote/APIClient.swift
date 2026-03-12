import Foundation

enum CordycepsClientError: LocalizedError {
  case missingToken
  case invalidBaseURL
  case invalidResponse
  case httpError(status: Int, message: String)
  case decodingFailed

  var errorDescription: String? {
    switch self {
    case .missingToken:
      return "Set PHONE_API_TOKEN first."
    case .invalidBaseURL:
      return "Set a valid API base URL, for example https://your-server.example"
    case .invalidResponse:
      return "Server returned an invalid response."
    case let .httpError(status, message):
      return "HTTP \(status): \(message)"
    case .decodingFailed:
      return "Could not decode server response."
    }
  }
}

struct ConnectionConfig {
  let baseURL: URL
  let token: String
}

enum CordycepsClient {
  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return encoder
  }()

  private static let decoder = JSONDecoder()
  private static let isoFormatter = ISO8601DateFormatter()

  static func makeConnectionConfig(apiBaseInput: String, tokenInput: String) throws -> ConnectionConfig {
    let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    if token.isEmpty {
      throw CordycepsClientError.missingToken
    }

    guard let baseURL = normalizeBaseURL(from: apiBaseInput) else {
      throw CordycepsClientError.invalidBaseURL
    }

    return ConnectionConfig(baseURL: baseURL, token: token)
  }

  static func loadDevices(config: ConnectionConfig) async throws -> APIResponse<DevicesResponse> {
    try await execute(
      config: config,
      path: "/api/devices",
      method: "GET",
      body: Optional<CommandRequest>.none,
      responseType: DevicesResponse.self
    )
  }

  static func loadGroups(config: ConnectionConfig) async throws -> APIResponse<GroupsResponse> {
    try await execute(
      config: config,
      path: "/api/groups",
      method: "GET",
      body: Optional<CommandRequest>.none,
      responseType: GroupsResponse.self
    )
  }

  static func upsertGroup(
    config: ConnectionConfig,
    groupID: String,
    displayName: String,
    description: String?,
    deviceIDs: [String]
  ) async throws -> APIResponse<GroupResponse> {
    let payload = GroupUpsertRequest(
      display_name: displayName,
      description: description,
      device_ids: deviceIDs
    )

    return try await execute(
      config: config,
      path: "/api/groups/\(groupID)",
      method: "PUT",
      body: payload,
      responseType: GroupResponse.self
    )
  }

  static func saveDeviceDisplayName(
    config: ConnectionConfig,
    deviceID: String,
    displayName: String
  ) async throws -> APIResponse<DeviceResponse> {
    let payload = DeviceDisplayNameUpsertRequest(display_name: displayName)
    return try await execute(
      config: config,
      path: "/api/devices/\(deviceID)/display-name",
      method: "PUT",
      body: payload,
      responseType: DeviceResponse.self
    )
  }

  static func loadDeviceAppAliases(
    config: ConnectionConfig,
    deviceID: String
  ) async throws -> APIResponse<DeviceAppAliasesResponse> {
    try await execute(
      config: config,
      path: "/api/devices/\(deviceID)/app-aliases",
      method: "GET",
      body: Optional<CommandRequest>.none,
      responseType: DeviceAppAliasesResponse.self
    )
  }

  static func saveDeviceAppAliases(
    config: ConnectionConfig,
    deviceID: String,
    aliases: [DeviceAppAliasUpsertEntry]
  ) async throws -> APIResponse<DeviceAppAliasesResponse> {
    let payload = DeviceAppAliasesUpsertRequest(aliases: aliases)
    return try await execute(
      config: config,
      path: "/api/devices/\(deviceID)/app-aliases",
      method: "PUT",
      body: payload,
      responseType: DeviceAppAliasesResponse.self
    )
  }

  static func deleteGroup(config: ConnectionConfig, groupID: String) async throws -> APIResponse<GroupResponse> {
    try await execute(
      config: config,
      path: "/api/groups/\(groupID)",
      method: "DELETE",
      body: Optional<CommandRequest>.none,
      responseType: GroupResponse.self
    )
  }

  static func loadCommandLogs(
    config: ConnectionConfig,
    limit: Int = 40,
    before: String? = nil,
    deviceID: String? = nil
  ) async throws -> APIResponse<CommandLogsResponse> {
    var params = URLComponents()
    var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(max(1, min(limit, 500))))]
    if let before, !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      items.append(URLQueryItem(name: "before", value: before))
    }
    if let deviceID, !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      items.append(URLQueryItem(name: "device_id", value: deviceID))
    }
    params.queryItems = items
    let query = params.percentEncodedQuery.map { "?\($0)" } ?? ""

    return try await execute(
      config: config,
      path: "/api/command-logs\(query)",
      method: "GET",
      body: Optional<CommandRequest>.none,
      responseType: CommandLogsResponse.self
    )
  }

  static func listAPIKeys(config: ConnectionConfig) async throws -> APIResponse<APIKeysResponse> {
    try await execute(
      config: config,
      path: "/api/auth/keys",
      method: "GET",
      body: Optional<CommandRequest>.none,
      responseType: APIKeysResponse.self
    )
  }

  static func createAPIKey(
    config: ConnectionConfig,
    name: String,
    scopes: [String]
  ) async throws -> APIResponse<APIKeyCreateResponse> {
    let payload = APIKeyCreateRequest(name: name, scopes: scopes)
    return try await execute(
      config: config,
      path: "/api/auth/keys",
      method: "POST",
      body: payload,
      responseType: APIKeyCreateResponse.self
    )
  }

  static func revokeAPIKey(config: ConnectionConfig, keyID: String) async throws -> APIResponse<ErrorResponse> {
    try await execute(
      config: config,
      path: "/api/auth/keys/\(keyID)/revoke",
      method: "POST",
      body: Optional<CommandRequest>.none,
      responseType: ErrorResponse.self
    )
  }

  static func sendCommand(config: ConnectionConfig, text: String) async throws -> APIResponse<CommandResponse> {
    let requestID = requestID(prefix: "ios")
    let payload = CommandRequest(
      request_id: requestID,
      text: text,
      source: "ios-native",
      is_async: true,
      timeout_ms: nil,
      sent_at: isoFormatter.string(from: Date()),
      client_version: "cordyceps-remote-ios-v3"
    )

    return try await execute(
      config: config,
      path: "/api/command",
      method: "POST",
      body: payload,
      responseType: CommandResponse.self
    )
  }

  static func sendAdminCommand(
    config: ConnectionConfig,
    target: String,
    shell: String,
    commandValue: String
  ) async throws -> APIResponse<CommandResponse> {
    let requestID = requestID(prefix: "ios-admin")
    let action = shell == "powershell" ? "ps" : "cmd"
    let payload = CommandRequest(
      request_id: requestID,
      text: "\(target) admin \(action) \(commandValue)",
      source: "ios-admin",
      is_async: true,
      timeout_ms: 120_000,
      sent_at: isoFormatter.string(from: Date()),
      client_version: "cordyceps-remote-ios-v3"
    )

    return try await execute(
      config: config,
      path: "/api/command",
      method: "POST",
      body: payload,
      responseType: CommandResponse.self
    )
  }

  static func sendGroupCommand(
    config: ConnectionConfig,
    groupID: String,
    text: String,
    confirmBulk: Bool
  ) async throws -> APIResponse<CommandResponse> {
    let requestID = requestID(prefix: "ios-group")
    let payload = GroupCommandRequest(
      request_id: requestID,
      text: text,
      source: "ios-native",
      confirm_bulk: confirmBulk
    )

    return try await execute(
      config: config,
      path: "/api/groups/\(groupID)/command",
      method: "POST",
      body: payload,
      responseType: CommandResponse.self
    )
  }

  static func pushUpdate(
    config: ConnectionConfig,
    target: String,
    version: String,
    packageURL: String,
    queueIfOffline: Bool,
    sha256: String?,
    sizeBytes: Int?
  ) async throws -> APIResponse<UpdateResponse> {
    let requestID = requestID(prefix: "ios-update")
    let payload = UpdateRequest(
      request_id: requestID,
      source: "ios-native",
      target: target,
      version: version,
      package_url: packageURL,
      queue_if_offline: queueIfOffline,
      sha256: sha256,
      size_bytes: sizeBytes
    )

    return try await execute(
      config: config,
      path: "/api/update",
      method: "POST",
      body: payload,
      responseType: UpdateResponse.self
    )
  }

  private static func execute<RequestBody: Encodable, ResponseBody: Decodable>(
    config: ConnectionConfig,
    path: String,
    method: String,
    body: RequestBody?,
    responseType: ResponseBody.Type
  ) async throws -> APIResponse<ResponseBody> {
    let request = try makeRequest(config: config, path: path, method: method, body: body)

    let data: Data
    let response: URLResponse
    let startTime = Date()

    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw error
    }

    guard let http = response as? HTTPURLResponse else {
      throw CordycepsClientError.invalidResponse
    }

    let latencyMs = Date().timeIntervalSince(startTime) * 1000

    if !(200 ... 299).contains(http.statusCode) {
      let message = parseErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      throw CordycepsClientError.httpError(status: http.statusCode, message: message)
    }

    guard let decoded = try? decoder.decode(responseType, from: data) else {
      throw CordycepsClientError.decodingFailed
    }

    return APIResponse(
      body: decoded,
      rawJSON: prettyJSON(from: data),
      latencyMs: latencyMs,
      statusCode: http.statusCode
    )
  }

  static func makeRequest<RequestBody: Encodable>(
    config: ConnectionConfig,
    path: String,
    method: String,
    body: RequestBody?
  ) throws -> URLRequest {
    guard let endpointURL = buildURL(baseURL: config.baseURL, path: path) else {
      throw CordycepsClientError.invalidBaseURL
    }

    var request = URLRequest(url: endpointURL)
    request.httpMethod = method
    request.timeoutInterval = 20
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    if let body {
      request.httpBody = try encoder.encode(body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    return request
  }

  static func makeRequest(
    config: ConnectionConfig,
    path: String,
    method: String
  ) throws -> URLRequest {
    try makeRequest(
      config: config,
      path: path,
      method: method,
      body: Optional<CommandRequest>.none
    )
  }

  private static func buildURL(baseURL: URL, path: String) -> URL? {
    var base = baseURL.absoluteString
    while base.hasSuffix("/") {
      base.removeLast()
    }

    let normalizedPath: String
    if path.hasPrefix("/") {
      normalizedPath = path
    } else {
      normalizedPath = "/\(path)"
    }

    return URL(string: base + normalizedPath)
  }

  private static func parseErrorMessage(from data: Data) -> String? {
    guard let decoded = try? decoder.decode(ErrorResponse.self, from: data) else {
      return prettyJSON(from: data)
    }

    if let message = decoded.message, !message.isEmpty {
      return message
    }

    if let error = decoded.error, !error.isEmpty {
      return error
    }

    return decoded.error_code
  }

  static func normalizeBaseURL(from input: String) -> URL? {
    let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty {
      return nil
    }

    let wsMapped = raw
      .replacingOccurrences(
        of: #"^wss://"#,
        with: "https://",
        options: [.regularExpression, .caseInsensitive]
      )
      .replacingOccurrences(
        of: #"^ws://"#,
        with: "http://",
        options: [.regularExpression, .caseInsensitive]
      )

    let candidate: String
    if wsMapped.contains("://") {
      candidate = wsMapped
    } else {
      candidate = "https://\(wsMapped)"
    }

    guard var components = URLComponents(string: candidate),
          let scheme = components.scheme?.lowercased(),
          ["http", "https"].contains(scheme)
    else {
      return nil
    }

    if components.user != nil || components.password != nil {
      return nil
    }

    components.path = ""
    components.query = nil
    components.fragment = nil

    if components.host == nil {
      return nil
    }

    return components.url
  }

  static func requestID(prefix: String) -> String {
    let millis = Int(Date().timeIntervalSince1970 * 1000)
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
    return "\(prefix)-\(millis)-\(suffix)"
  }

  static func prettyJSON(from data: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data),
          let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
          let string = String(data: prettyData, encoding: .utf8)
    else {
      return String(data: data, encoding: .utf8) ?? "(no response body)"
    }

    return string
  }
}
