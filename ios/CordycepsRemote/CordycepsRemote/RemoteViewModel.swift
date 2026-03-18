import AVFoundation
import Foundation
import Speech
import UIKit

@MainActor
final class RemoteViewModel: ObservableObject {
  private enum DefaultsKey {
    static let apiBase = "cordyceps.ios.apiBase"
    static let token = "cordyceps.ios.phoneToken"
    static let target = "cordyceps.ios.target"
    static let renameDevice = "cordyceps.ios.renameDevice"
    static let aliasDevice = "cordyceps.ios.aliasDevice"
    static let updateTarget = "cordyceps.ios.updateTarget"
    static let updateVersion = "cordyceps.ios.updateVersion"
    static let updateURL = "cordyceps.ios.updateURL"
    static let updateSha = "cordyceps.ios.updateSha"
    static let updateSize = "cordyceps.ios.updateSize"
    static let updateSignatureKeyID = "cordyceps.ios.updateSignatureKeyID"
    static let updateSignature = "cordyceps.ios.updateSignature"
    static let updateUsePrivilegedHelper = "cordyceps.ios.updateUsePrivilegedHelper"
    static let updateQueueOffline = "cordyceps.ios.updateQueueOffline"
    static let securityDevice = "cordyceps.ios.securityDevice"
    static let securityReason = "cordyceps.ios.securityReason"
    static let securityLockdownMinutes = "cordyceps.ios.securityLockdownMinutes"
    static let adminTarget = "cordyceps.ios.adminTarget"
    static let adminShell = "cordyceps.ios.adminShell"
    static let ownerGraceSeconds = "cordyceps.ios.ownerGraceSeconds"
    static let lastSuccess = "cordyceps.ios.lastSuccess"
    static let lastAction = "cordyceps.ios.lastAction"
    static let commandHistory = "cordyceps.ios.commandHistory"
  }

  private static let pollIntervalNs: UInt64 = 300_000_000_000
  private static let eventReconnectDelayNs: UInt64 = 4_000_000_000
  private static let deviceStatusMinRefreshInterval: TimeInterval = 1.5
  private static let maxCommandHistory = 12

  @Published var apiBaseInput: String
  @Published var tokenInput: String
  @Published var targetInput: String

  @Published var actionSearchInput = ""
  @Published var selectedActionValue: String
  @Published var argumentInput = ""
  @Published var commandText = ""

  @Published var renameDeviceInput: String
  @Published var renameDisplayNameInput = ""
  @Published var aliasDeviceInput: String
  @Published var aliasKeyInput = ""
  @Published var aliasAppInput = ""

  @Published var adminTargetInput: String
  @Published var adminShellInput: String
  @Published var adminCommandInput = ""

  @Published var updateTargetInput: String
  @Published var updateVersionInput: String
  @Published var updateURLInput: String
  @Published var updateShaInput: String
  @Published var updateSizeInput: String
  @Published var updateSignatureKeyIDInput: String
  @Published var updateSignatureInput: String
  @Published var updateUsePrivilegedHelperInput: Bool
  @Published var updateQueueOfflineInput: Bool
  @Published var securityDeviceInput: String
  @Published var securityReasonInput: String
  @Published var securityLockdownMinutesInput: String
  @Published var ownerGraceSecondsInput: String

  @Published var pairingLinkInput = ""
  @Published var deviceSearchInput = ""
  @Published var showOnlyOnlineDevices = false

  @Published var devices: [DeviceRecord] = []
  @Published var groups: [GroupRecord] = []
  @Published var commandLogs: [CommandLogEntry] = []
  @Published var nextCommandLogCursor: String?
  @Published var historyDeviceFilterInput = ""
  @Published var apiKeys: [APIKeyRecord] = []
  @Published var generatedAPIKey = ""
  @Published var groupIDInput = ""
  @Published var groupDisplayNameInput = ""
  @Published var groupDescriptionInput = ""
  @Published var groupMembersInput = ""
  @Published var apiKeyNameInput = ""
  @Published var apiKeyScopesInput = "devices:read,commands:execute,history:read,events:read"
  @Published var recentCommands: [String]
  @Published var inspectedDeviceID = ""
  @Published var inspectedDevice: DeviceRecord?
  @Published var inspectedRealtime: DeviceRealtimeRecord?
  @Published var inspectedAliases: [DeviceAppAliasRecord] = []
  @Published var inspectedQueuedUpdates: [QueuedUpdateRecord] = []
  @Published var inspectedRecentLogs: [CommandLogEntry] = []
  @Published var rotatedTokenPayload = ""

  @Published var isLoadingDevices = false
  @Published var isLoadingGroups = false
  @Published var isLoadingHistory = false
  @Published var isLoadingAPIKeys = false
  @Published var isLoadingDeviceInspector = false
  @Published var isSavingGroup = false
  @Published var isDeletingGroup = false
  @Published var deletingDeviceID = ""
  @Published var isSavingDisplayName = false
  @Published var isSavingAlias = false
  @Published var isSendingAdminCommand = false
  @Published var isCreatingAPIKey = false
  @Published var rotatingAPIKeyID = ""
  @Published var isRotatingTokens = false
  @Published var isTestingToken = false
  @Published var isSendingCommand = false
  @Published var isPushingUpdate = false
  @Published var isApplyingSecurityControl = false

  @Published var connectionState: ConnectionState
  @Published var statusText = "Set API base URL and PHONE_API_TOKEN, then load devices."
  @Published var statusIsError = false
  @Published var lastSuccessLabel = "Last success: never"

  @Published var resultStatus = "idle"
  @Published var resultRequestId = "-"
  @Published var resultLatency = "-"
  @Published var resultMessage = "No request yet."
  @Published var responseText = "No request yet."
  @Published var resultIsError = false

  @Published var speechInfoText = "Speech: tap Speak to dictate a command."
  @Published var speechSupported = true
  @Published var isListening = false

  private let defaults = UserDefaults.standard
  private let speechController = SpeechController()
  private var pollingTask: Task<Void, Never>?
  private var eventsTask: Task<Void, Never>?
  private var hasInitialized = false
  private var appIsActive = true
  private var lastDeviceStatusRefreshAt: Date = .distantPast

  init() {
    let initialTarget = defaults.string(forKey: DefaultsKey.target) ?? "m1"
    let initialRenameDevice = defaults.string(forKey: DefaultsKey.renameDevice) ?? initialTarget
    let initialAliasDevice = defaults.string(forKey: DefaultsKey.aliasDevice) ?? initialTarget
    let initialSecurityDevice = defaults.string(forKey: DefaultsKey.securityDevice) ?? initialTarget
    let initialAdminTarget = defaults.string(forKey: DefaultsKey.adminTarget) ?? "a1"
    let initialAdminShell = Self.normalizeAdminShellValue(defaults.string(forKey: DefaultsKey.adminShell) ?? "cmd")
    let rememberedAction = defaults.string(forKey: DefaultsKey.lastAction) ?? "ping"
    let initialToken = defaults.string(forKey: DefaultsKey.token) ?? ""
    let initialQueueOffline: Bool
    let initialUsePrivilegedHelper: Bool
    if defaults.object(forKey: DefaultsKey.updateQueueOffline) == nil {
      initialQueueOffline = true
    } else {
      initialQueueOffline = defaults.bool(forKey: DefaultsKey.updateQueueOffline)
    }
    if defaults.object(forKey: DefaultsKey.updateUsePrivilegedHelper) == nil {
      initialUsePrivilegedHelper = false
    } else {
      initialUsePrivilegedHelper = defaults.bool(forKey: DefaultsKey.updateUsePrivilegedHelper)
    }

    apiBaseInput = defaults.string(forKey: DefaultsKey.apiBase) ?? ""
    tokenInput = initialToken
    targetInput = initialTarget

    selectedActionValue = CommandLibrary.safeAction(rememberedAction)

    let normalizedInitialTarget = Self.normalizeDeviceIDValue(initialTarget)
    let fallbackSingleDevice = normalizedInitialTarget.isEmpty ? "m1" : normalizedInitialTarget
    let normalizedRenameDevice = Self.normalizeDeviceIDValue(initialRenameDevice)
    let normalizedAliasDevice = Self.normalizeDeviceIDValue(initialAliasDevice)
    let normalizedAdminTarget = Self.normalizeDeviceIDValue(initialAdminTarget)
    renameDeviceInput = normalizedRenameDevice.isEmpty ? fallbackSingleDevice : normalizedRenameDevice
    aliasDeviceInput = normalizedAliasDevice.isEmpty ? fallbackSingleDevice : normalizedAliasDevice

    adminTargetInput = normalizedAdminTarget.isEmpty ? "a1" : normalizedAdminTarget
    adminShellInput = initialAdminShell

    updateTargetInput = defaults.string(forKey: DefaultsKey.updateTarget) ?? initialTarget
    updateVersionInput = defaults.string(forKey: DefaultsKey.updateVersion) ?? ""
    updateURLInput = defaults.string(forKey: DefaultsKey.updateURL) ?? ""
    updateShaInput = defaults.string(forKey: DefaultsKey.updateSha) ?? ""
    updateSizeInput = defaults.string(forKey: DefaultsKey.updateSize) ?? ""
    updateSignatureKeyIDInput = defaults.string(forKey: DefaultsKey.updateSignatureKeyID) ?? ""
    updateSignatureInput = defaults.string(forKey: DefaultsKey.updateSignature) ?? ""
    updateUsePrivilegedHelperInput = initialUsePrivilegedHelper
    updateQueueOfflineInput = initialQueueOffline
    securityDeviceInput = defaults.string(forKey: DefaultsKey.securityDevice) ?? initialSecurityDevice
    securityReasonInput = defaults.string(forKey: DefaultsKey.securityReason) ?? ""
    securityLockdownMinutesInput = defaults.string(forKey: DefaultsKey.securityLockdownMinutes) ?? "30"
    ownerGraceSecondsInput = defaults.string(forKey: DefaultsKey.ownerGraceSeconds) ?? "600"
    recentCommands = []

    connectionState = initialToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .disconnected : .retrying

    if let lastSuccess = defaults.string(forKey: DefaultsKey.lastSuccess) {
      lastSuccessLabel = "Last success: \(toLocalTimestamp(lastSuccess))"
    }

    commandText = composeCommand()
    speechSupported = speechController.isAvailable
    if !speechSupported {
      speechInfoText = "Speech not supported on this device."
    }

    recentCommands = loadCommandHistory()
  }

  deinit {
    pollingTask?.cancel()
    eventsTask?.cancel()
    speechController.stop()
  }

  var selectedAction: CommandLibraryEntry {
    CommandLibrary.entry(for: selectedActionValue) ?? CommandLibrary.entry(for: "ping")!
  }

  var filteredActions: [CommandLibraryEntry] {
    CommandLibrary
      .filteredEntries(matching: actionSearchInput)
      .filter { action in
        actionSupportedOnCurrentTarget(action.normalizedValue)
      }
  }

  var filteredDevices: [DeviceRecord] {
    var filtered = devices

    if showOnlyOnlineDevices {
      filtered = filtered.filter(\.isOnline)
    }

    let query = deviceSearchInput.normalizedActionText
    if query.isEmpty {
      return filtered
    }

    let terms = query.split(separator: " ").map(String.init)
    return filtered.filter { device in
      let searchable = [
        device.device_id,
        device.display_name ?? "",
        device.hostname ?? "",
        device.username ?? "",
      ]
      .joined(separator: " ")
      .normalizedActionText

      return terms.allSatisfy { term in
        searchable.contains(term)
      }
    }
  }

  var actionPickerGroups: [CommandCategoryGroup] {
    let filtered = filteredActions
    if filtered.isEmpty {
      return CommandLibrary.grouped(entries: CommandLibrary.entries)
    }
    return CommandLibrary.grouped(entries: filtered)
  }

  var actionSearchInfo: String {
    if actionSearchInput.normalizedActionText.isEmpty {
      return "Showing all \(CommandLibrary.entries.count) commands."
    }

    if filteredActions.isEmpty {
      return "No matches for \"\(actionSearchInput.normalizedActionText)\"."
    }

    return "Showing \(filteredActions.count) of \(CommandLibrary.entries.count) commands."
  }

  var selectedActionIsDangerous: Bool {
    selectedAction.isDangerous
  }

  var selectedActionSupported: Bool {
    actionSupportedOnCurrentTarget(selectedAction.normalizedValue)
  }

  var selectedActionUsesArgument: Bool {
    selectedAction.usesArgument
  }

  var selectedActionArgumentPlaceholder: String {
    selectedAction.placeholderArgument
  }

  var hasInspectorData: Bool {
    inspectedDevice != nil
  }

  var canDeleteInspectedDevice: Bool {
    guard let inspectedDevice else {
      return false
    }
    return !inspectedDevice.isOnline
  }

  var inspectedDeviceInfo: [String: JSONValue] {
    if let fromDevice = inspectedDevice?.device_info, !fromDevice.isEmpty {
      return fromDevice
    }
    if let fromRealtime = inspectedRealtime?.device_info, !fromRealtime.isEmpty {
      return fromRealtime
    }
    return [:]
  }

  var inspectedDeviceInfoSummary: [(String, String)] {
    inspectedDeviceInfo.keys.sorted().prefix(24).map { key in
      (key, inspectedDeviceInfo[key]?.compactText ?? "null")
    }
  }

  var deviceSummaryText: String {
    guard !devices.isEmpty else {
      return "No data yet"
    }

    let onlineCount = devices.filter(\.isOnline).count
    if filteredDevices.count != devices.count {
      return "\(onlineCount)/\(devices.count) online • \(filteredDevices.count) shown"
    }
    return "\(onlineCount)/\(devices.count) online"
  }

  func handleInitialLoad() async {
    guard !hasInitialized else {
      return
    }

    hasInitialized = true

    guard !tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      connectionState = .disconnected
      return
    }

    await loadDevices(silent: true, fromPolling: false)
    await loadGroups(silent: true)
    await loadCommandLogs(silent: true, append: false)
    await loadAPIKeys(silent: true)
    if connectionState == .connected {
      startPollingIfNeeded()
      startRealtimeEventsIfNeeded()
    }
    if responseText == "No request yet." {
      setResult(message: "Devices loaded.", rawBody: "Devices loaded.", isError: false)
    }
  }

  func setAppLifecycle(isActive: Bool) {
    appIsActive = isActive
    if !isActive {
      pollingTask?.cancel()
      pollingTask = nil
      eventsTask?.cancel()
      eventsTask = nil
      if isListening {
        speechController.stop()
        isListening = false
        speechInfoText = "Speech paused while app is in background."
      }
      return
    }

    startPollingIfNeeded()
    startRealtimeEventsIfNeeded()
  }

  func saveConnectionSettings() {
    let normalizedBase = CordycepsClient.normalizeBaseURL(from: apiBaseInput)?.absoluteString ?? apiBaseInput.trimmed
    let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let target = normalizeTarget(targetInput)

    apiBaseInput = normalizedBase
    tokenInput = token
    targetInput = target

    defaults.set(normalizedBase, forKey: DefaultsKey.apiBase)
    defaults.set(token, forKey: DefaultsKey.token)
    defaults.set(target, forKey: DefaultsKey.target)

    if updateTargetInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      updateTargetInput = target
      defaults.set(updateTargetInput, forKey: DefaultsKey.updateTarget)
    }

    syncSingleDeviceControls(with: target)

    connectionState = token.isEmpty ? .disconnected : .retrying
    commandText = composeCommand()
    startPollingIfNeeded()
    startRealtimeEventsIfNeeded()
    setStatus("Connection settings saved.", isError: false)
    setResult(message: "Connection settings saved on this device.", rawBody: "Connection settings saved on this device.", isError: false)
  }

  func persistUpdateSettings() {
    let target = normalizeExplicitUpdateTarget(updateTargetInput)
    let version = updateVersionInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = updateURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let sha = updateShaInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let size = updateSizeInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let signatureKeyID = updateSignatureKeyIDInput.normalizedActionText
    let signature = updateSignatureInput
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)

    updateTargetInput = target
    updateVersionInput = version
    updateURLInput = url
    updateShaInput = sha
    updateSizeInput = size
    updateSignatureKeyIDInput = signatureKeyID
    updateSignatureInput = signature

    defaults.set(target, forKey: DefaultsKey.updateTarget)
    defaults.set(version, forKey: DefaultsKey.updateVersion)
    defaults.set(url, forKey: DefaultsKey.updateURL)
    defaults.set(sha, forKey: DefaultsKey.updateSha)
    defaults.set(size, forKey: DefaultsKey.updateSize)
    defaults.set(signatureKeyID, forKey: DefaultsKey.updateSignatureKeyID)
    defaults.set(signature, forKey: DefaultsKey.updateSignature)
    defaults.set(updateUsePrivilegedHelperInput, forKey: DefaultsKey.updateUsePrivilegedHelper)
    defaults.set(updateQueueOfflineInput, forKey: DefaultsKey.updateQueueOffline)
  }

  func persistOwnerGraceSeconds() {
    let trimmed = ownerGraceSecondsInput.trimmed
    guard let parsed = parseOwnerGraceSeconds(trimmed) else {
      return
    }
    ownerGraceSecondsInput = String(parsed)
    defaults.set(ownerGraceSecondsInput, forKey: DefaultsKey.ownerGraceSeconds)
  }

  func persistSecuritySettings() {
    let device = normalizeDeviceID(securityDeviceInput)
    let reason = securityReasonInput.trimmed
    let minutes = securityLockdownMinutesInput.trimmed

    if !device.isEmpty {
      securityDeviceInput = device
      defaults.set(device, forKey: DefaultsKey.securityDevice)
    }
    securityReasonInput = reason
    securityLockdownMinutesInput = minutes
    defaults.set(reason, forKey: DefaultsKey.securityReason)
    defaults.set(minutes, forKey: DefaultsKey.securityLockdownMinutes)
  }

  func persistAdminSettings() {
    let target = normalizeDeviceID(adminTargetInput)
    let shell = normalizeAdminShell(adminShellInput)

    adminShellInput = shell
    defaults.set(shell, forKey: DefaultsKey.adminShell)

    if !target.isEmpty {
      adminTargetInput = target
      defaults.set(target, forKey: DefaultsKey.adminTarget)
    }
  }

  func targetDidChange() {
    let normalized = normalizeTarget(targetInput)
    if normalized != targetInput {
      targetInput = normalized
    }

    defaults.set(normalized, forKey: DefaultsKey.target)
    if updateTargetInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      updateTargetInput = normalized
    }
    syncSingleDeviceControls(with: normalized)
    composeFromInputs()
  }

  func actionSearchDidChange() {
    if filteredActions.isEmpty {
      return
    }

    let normalizedSelected = selectedActionValue.normalizedActionText
    let exists = filteredActions.contains(where: { $0.normalizedValue == normalizedSelected })
    if !exists, let fallback = filteredActions.first {
      selectedActionValue = fallback.normalizedValue
      defaults.set(selectedActionValue, forKey: DefaultsKey.lastAction)
    }

    composeFromInputs()
  }

  func actionSelectionDidChange() {
    selectedActionValue = CommandLibrary.safeAction(selectedActionValue)
    defaults.set(selectedActionValue, forKey: DefaultsKey.lastAction)
    composeFromInputs()
  }

  func composeFromInputs() {
    commandText = composeCommand()
  }

  func setAction(_ actionValue: String) {
    selectedActionValue = CommandLibrary.safeAction(actionValue)
    defaults.set(selectedActionValue, forKey: DefaultsKey.lastAction)
    composeFromInputs()
  }

  func useDeviceAsTarget(_ deviceID: String) {
    let normalized = normalizeExplicitTarget(deviceID)
    guard !normalized.isEmpty else {
      return
    }

    targetInput = normalized
    updateTargetInput = normalized
    defaults.set(normalized, forKey: DefaultsKey.target)
    defaults.set(normalized, forKey: DefaultsKey.updateTarget)
    syncSingleDeviceControls(with: normalized)
    commandText = composeCommand()
    setStatus("Target set to \(normalized).", isError: false)
    setResult(message: "Target set to \(normalized).", rawBody: "Target set to \(normalized).", isError: false)
  }

  func inspectDevice(_ deviceID: String, silent: Bool = false) async {
    guard !isLoadingDeviceInspector else {
      return
    }

    let normalized = normalizeDeviceID(deviceID)
    guard !normalized.isEmpty else {
      if !silent {
        setStatus("Valid device ID is required for inspector.", isError: true)
        setResult(message: "Valid device ID is required for inspector.", rawBody: "Valid device ID is required for inspector.", isError: true)
      }
      return
    }

    isLoadingDeviceInspector = true
    defer { isLoadingDeviceInspector = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.loadDeviceInspector(
        config: config,
        deviceID: normalized,
        logsLimit: 40
      )

      inspectedDeviceID = normalized
      inspectedDevice = response.body.device
      inspectedRealtime = response.body.realtime
      inspectedAliases = response.body.aliases
      inspectedQueuedUpdates = response.body.queued_updates
      inspectedRecentLogs = response.body.recent_logs
      connectionState = .connected

      if !silent {
        setStatus("Loaded inspector for \(normalized).", isError: false)
        setResult(
          message: "Loaded inspector for \(normalized).",
          rawBody: response.rawJSON,
          requestID: normalized,
          latencyMs: response.latencyMs,
          isError: false
        )
      }
    } catch {
      if !silent {
        handle(error: error, silent: false, fromPolling: false)
      }
    }
  }

  func refreshInspectedDevice() async {
    guard !inspectedDeviceID.isEmpty else {
      return
    }

    await inspectDevice(inspectedDeviceID, silent: false)
  }

  func closeInspector() {
    clearInspector()
  }

  func deleteDeviceRecord(_ deviceID: String) async {
    let normalized = normalizeDeviceID(deviceID)
    guard !normalized.isEmpty else {
      setStatus("Valid device ID is required for delete.", isError: true)
      setResult(message: "Valid device ID is required for delete.", rawBody: "Valid device ID is required for delete.", isError: true)
      return
    }

    guard deletingDeviceID.isEmpty else {
      return
    }

    deletingDeviceID = normalized
    defer {
      if deletingDeviceID == normalized {
        deletingDeviceID = ""
      }
    }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.deleteDeviceRecord(config: config, deviceID: normalized)
      connectionState = .connected

      if inspectedDeviceID == normalized {
        clearInspector()
      }

      await loadDevices(silent: true, fromPolling: false)
      await loadGroups(silent: true)
      await loadCommandLogs(silent: true, append: false)

      let target = normalizeExplicitTarget(targetInput)
      if target == normalized {
        if let fallback = devices.first(where: { $0.device_id.normalizedActionText != normalized }) {
          targetInput = fallback.device_id.normalizedActionText
        } else {
          targetInput = "m1"
        }
        defaults.set(targetInput, forKey: DefaultsKey.target)
        syncSingleDeviceControls(with: targetInput)
        commandText = composeCommand()
      }

      let message = response.body.message ?? "Deleted device record \(normalized)."
      setStatus(message, isError: false)
      setResult(
        message: message,
        rawBody: response.rawJSON,
        requestID: normalized,
        latencyMs: response.latencyMs,
        isError: false
      )
      triggerFeedback(.success)
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func isDeletingDevice(_ deviceID: String) -> Bool {
    deletingDeviceID == deviceID.normalizedActionText
  }

  func isRotatingAPIKey(_ keyID: String) -> Bool {
    rotatingAPIKeyID == keyID.trimmed
  }

  func rotateAPIKey(_ keyID: String) async {
    guard rotatingAPIKeyID.isEmpty else {
      return
    }

    let normalized = keyID.trimmed
    guard !normalized.isEmpty else {
      return
    }

    rotatingAPIKeyID = normalized
    defer {
      if rotatingAPIKeyID == normalized {
        rotatingAPIKeyID = ""
      }
    }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.rotateAPIKey(config: config, keyID: normalized)
      generatedAPIKey = response.body.api_key ?? ""
      await loadAPIKeys(silent: true)
      setStatus("API key rotated.", isError: false)
      setResult(
        message: "API key rotated.",
        rawBody: response.rawJSON,
        requestID: normalized,
        latencyMs: response.latencyMs,
        isError: false
      )
      triggerFeedback(.success)
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func rotateOwnerToken() async {
    await rotateTokens(rotateOwner: true, rotateBootstrap: false)
  }

  func rotateOwnerAndBootstrapTokens() async {
    await rotateTokens(rotateOwner: true, rotateBootstrap: true)
  }

  func rotateBootstrapToken() async {
    await rotateTokens(rotateOwner: false, rotateBootstrap: true)
  }

  func saveDeviceDisplayName() async {
    guard !isSavingDisplayName else {
      return
    }

    let deviceID = normalizeDeviceID(renameDeviceInput)
    let displayName = renameDisplayNameInput.trimmed

    guard !deviceID.isEmpty else {
      setStatus("Device ID is required.", isError: true)
      setResult(message: "Device ID is required.", rawBody: "Device ID is required.", isError: true)
      return
    }

    isSavingDisplayName = true
    defer { isSavingDisplayName = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.saveDeviceDisplayName(
        config: config,
        deviceID: deviceID,
        displayName: displayName
      )

      connectionState = .connected
      renameDeviceInput = deviceID
      defaults.set(deviceID, forKey: DefaultsKey.renameDevice)
      await loadDevices(silent: true, fromPolling: false)

      let message = response.body.message ?? (displayName.isEmpty ? "Display name cleared." : "Display name saved.")
      setStatus(message, isError: false)
      setResult(
        message: message,
        rawBody: response.rawJSON,
        requestID: deviceID,
        latencyMs: response.latencyMs,
        isError: false
      )
      triggerFeedback(.success)
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func saveDeviceAlias() async {
    guard !isSavingAlias else {
      return
    }

    let deviceID = normalizeDeviceID(aliasDeviceInput)
    let alias = normalizeAlias(aliasKeyInput)
    let app = aliasAppInput.normalizedActionText

    guard !deviceID.isEmpty else {
      setStatus("Alias device ID is required.", isError: true)
      setResult(message: "Alias device ID is required.", rawBody: "Alias device ID is required.", isError: true)
      return
    }

    guard !alias.isEmpty else {
      setStatus("Alias phrase is required.", isError: true)
      setResult(message: "Alias phrase is required.", rawBody: "Alias phrase is required.", isError: true)
      return
    }

    guard alias.count <= 80,
          alias.range(of: #"^[a-z0-9 _-]+$"#, options: .regularExpression) != nil
    else {
      setStatus("Alias can only use a-z, 0-9, spaces, _ or -, max 80 chars.", isError: true)
      setResult(
        message: "Alias can only use a-z, 0-9, spaces, _ or -, max 80 chars.",
        rawBody: "Alias can only use a-z, 0-9, spaces, _ or -, max 80 chars.",
        isError: true
      )
      return
    }

    guard !app.isEmpty else {
      setStatus("Canonical app is required.", isError: true)
      setResult(message: "Canonical app is required.", rawBody: "Canonical app is required.", isError: true)
      return
    }

    isSavingAlias = true
    defer { isSavingAlias = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let existing = try await CordycepsClient.loadDeviceAppAliases(config: config, deviceID: deviceID)

      var merged: [DeviceAppAliasUpsertEntry] = []
      var updated = false
      for entry in existing.body.aliases {
        let existingAlias = normalizeAlias(entry.alias)
        let existingApp = entry.app.normalizedActionText
        if existingAlias.isEmpty || existingApp.isEmpty {
          continue
        }

        if existingAlias == alias {
          merged.append(DeviceAppAliasUpsertEntry(alias: alias, app: app))
          updated = true
        } else {
          merged.append(DeviceAppAliasUpsertEntry(alias: existingAlias, app: existingApp))
        }
      }

      if !updated {
        merged.append(DeviceAppAliasUpsertEntry(alias: alias, app: app))
      }

      let response = try await CordycepsClient.saveDeviceAppAliases(
        config: config,
        deviceID: deviceID,
        aliases: merged
      )

      connectionState = .connected
      aliasDeviceInput = deviceID
      defaults.set(deviceID, forKey: DefaultsKey.aliasDevice)

      let message = response.body.message ?? "Device app alias saved."
      setStatus(message, isError: false)
      setResult(
        message: message,
        rawBody: response.rawJSON,
        requestID: deviceID,
        latencyMs: response.latencyMs,
        isError: false
      )
      triggerFeedback(.success)
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func loadDevices(silent: Bool = false, fromPolling: Bool = false) async {
    if isLoadingDevices {
      return
    }

    isLoadingDevices = true
    defer { isLoadingDevices = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.loadDevices(config: config)
      devices = sortedDevices(response.body.devices)
      connectionState = .connected

      if !inspectedDeviceID.isEmpty {
        let inspectedStillExists = devices.contains { device in
          device.device_id.normalizedActionText == inspectedDeviceID.normalizedActionText
        }
        if !inspectedStillExists {
          clearInspector()
        } else if !isLoadingDeviceInspector {
          await inspectDevice(inspectedDeviceID, silent: true)
        }
      }

      if !silent {
        setStatus("Loaded \(devices.count) devices.", isError: false)
        setResult(
          message: "Devices loaded.",
          rawBody: response.rawJSON,
          requestID: "-",
          latencyMs: response.latencyMs,
          isError: false
        )
        triggerFeedback(.success)
      }
    } catch {
      handle(error: error, silent: silent, fromPolling: fromPolling)
    }
  }

  func loadGroups(silent: Bool = false) async {
    if isLoadingGroups {
      return
    }

    isLoadingGroups = true
    defer { isLoadingGroups = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.loadGroups(config: config)
      groups = response.body.groups.sorted {
        $0.display_name.localizedCaseInsensitiveCompare($1.display_name) == .orderedAscending
      }
      connectionState = .connected

      if !silent {
        setStatus("Loaded \(groups.count) groups.", isError: false)
        setResult(
          message: "Groups loaded.",
          rawBody: response.rawJSON,
          requestID: "-",
          latencyMs: response.latencyMs,
          isError: false
        )
      }
    } catch {
      if !silent {
        handle(error: error, silent: false, fromPolling: false)
      }
    }
  }

  func loadCommandLogs(silent: Bool = false, append: Bool = false) async {
    if isLoadingHistory {
      return
    }

    isLoadingHistory = true
    defer { isLoadingHistory = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.loadCommandLogs(
        config: config,
        limit: 40,
        before: append ? nextCommandLogCursor : nil,
        deviceID: historyDeviceFilterInput.trimmed.isEmpty ? nil : historyDeviceFilterInput.normalizedActionText
      )

      if append {
        var seen = Set(commandLogs.map(\.id))
        for entry in response.body.logs where !seen.contains(entry.id) {
          commandLogs.append(entry)
          seen.insert(entry.id)
        }
      } else {
        commandLogs = response.body.logs
      }

      nextCommandLogCursor = response.body.next_before

      if !silent {
        setStatus("Loaded \(response.body.logs.count) history entries.", isError: false)
        setResult(
          message: "Command history loaded.",
          rawBody: response.rawJSON,
          requestID: "-",
          latencyMs: response.latencyMs,
          isError: false
        )
      }
    } catch {
      if !silent {
        handle(error: error, silent: false, fromPolling: false)
      }
    }
  }

  func loadAPIKeys(silent: Bool = false) async {
    if isLoadingAPIKeys {
      return
    }

    isLoadingAPIKeys = true
    defer { isLoadingAPIKeys = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.listAPIKeys(config: config)
      apiKeys = response.body.keys
      connectionState = .connected

      if !silent {
        setStatus("Loaded \(apiKeys.count) API keys.", isError: false)
        setResult(
          message: "API keys loaded.",
          rawBody: response.rawJSON,
          requestID: "-",
          latencyMs: response.latencyMs,
          isError: false
        )
      }
    } catch {
      if !silent {
        handle(error: error, silent: false, fromPolling: false)
      }
    }
  }

  func saveGroup() async {
    guard !isSavingGroup else {
      return
    }

    let groupID = groupIDInput.normalizedActionText
    let displayName = groupDisplayNameInput.trimmed
    let description = groupDescriptionInput.trimmed
    let memberIDs = groupMembersInput
      .split(separator: ",")
      .map { String($0).normalizedActionText }
      .filter { !$0.isEmpty }

    guard !groupID.isEmpty else {
      setStatus("Group ID is required.", isError: true)
      return
    }

    guard !displayName.isEmpty else {
      setStatus("Group name is required.", isError: true)
      return
    }

    isSavingGroup = true
    defer { isSavingGroup = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.upsertGroup(
        config: config,
        groupID: groupID,
        displayName: displayName,
        description: description.isEmpty ? nil : description,
        deviceIDs: memberIDs
      )

      await loadGroups(silent: true)
      setStatus(response.body.message ?? "Group saved.", isError: false)
      setResult(
        message: response.body.message ?? "Group saved.",
        rawBody: response.rawJSON,
        requestID: "-",
        latencyMs: response.latencyMs,
        isError: false
      )
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func deleteGroup() async {
    guard !isDeletingGroup else {
      return
    }

    let groupID = groupIDInput.normalizedActionText
    guard !groupID.isEmpty else {
      setStatus("Group ID is required.", isError: true)
      return
    }

    isDeletingGroup = true
    defer { isDeletingGroup = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.deleteGroup(config: config, groupID: groupID)
      await loadGroups(silent: true)
      setStatus(response.body.message ?? "Group deleted.", isError: false)
      setResult(
        message: response.body.message ?? "Group deleted.",
        rawBody: response.rawJSON,
        requestID: "-",
        latencyMs: response.latencyMs,
        isError: false
      )
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func useGroupAsTarget(_ groupID: String) {
    let normalized = groupID.normalizedActionText
    guard !normalized.isEmpty else {
      return
    }

    targetInput = "group:\(normalized)"
    defaults.set(targetInput, forKey: DefaultsKey.target)
    composeFromInputs()
  }

  func selectGroupForEditing(_ group: GroupRecord) {
    groupIDInput = group.group_id
    groupDisplayNameInput = group.display_name
    groupDescriptionInput = group.description ?? ""
    groupMembersInput = group.device_ids.joined(separator: ",")
  }

  func createAPIKey() async {
    guard !isCreatingAPIKey else {
      return
    }

    let name = apiKeyNameInput.trimmed
    let scopes = apiKeyScopesInput
      .split(separator: ",")
      .map { String($0).normalizedActionText }
      .filter { !$0.isEmpty }

    guard !name.isEmpty else {
      setStatus("API key name is required.", isError: true)
      return
    }

    guard !scopes.isEmpty else {
      setStatus("At least one API scope is required.", isError: true)
      return
    }

    isCreatingAPIKey = true
    defer { isCreatingAPIKey = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.createAPIKey(config: config, name: name, scopes: scopes)
      generatedAPIKey = response.body.api_key ?? ""
      await loadAPIKeys(silent: true)
      setStatus("API key created.", isError: false)
      setResult(
        message: "API key created.",
        rawBody: response.rawJSON,
        requestID: "-",
        latencyMs: response.latencyMs,
        isError: false
      )
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func revokeAPIKey(_ keyID: String) async {
    let normalized = keyID.trimmed
    guard !normalized.isEmpty else {
      return
    }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      _ = try await CordycepsClient.revokeAPIKey(config: config, keyID: normalized)
      await loadAPIKeys(silent: true)
      setStatus("Revoked key \(normalized).", isError: false)
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func testToken() async {
    guard !isTestingToken else {
      return
    }

    isTestingToken = true
    defer { isTestingToken = false }

    setStatus("Testing token...", isError: false)

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.loadDevices(config: config)
      devices = sortedDevices(response.body.devices)
      let groupsResponse = try await CordycepsClient.loadGroups(config: config)
      groups = groupsResponse.body.groups
      let keysResponse = try await CordycepsClient.listAPIKeys(config: config)
      apiKeys = keysResponse.body.keys
      connectionState = .connected
      setStatus("Token valid. Device list loaded.", isError: false)
      setResult(
        message: "Token test passed.",
        rawBody: "Token test passed.",
        requestID: "-",
        latencyMs: response.latencyMs,
        isError: false
      )
      triggerFeedback(.success)
      startPollingIfNeeded()
      startRealtimeEventsIfNeeded()
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func sendCommand() async {
    let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      setStatus("Command text is empty.", isError: true)
      setResult(message: "Command text is empty.", rawBody: "Command text is empty.", isError: true)
      return
    }

    if !selectedActionSupported {
      setStatus("Selected action is not supported by the current target.", isError: true)
      setResult(
        message: "Selected action is not supported by the current target.",
        rawBody: "Selected action is not supported by the current target.",
        isError: true
      )
      return
    }

    guard !isSendingCommand else {
      return
    }

    isSendingCommand = true
    defer { isSendingCommand = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let normalizedTarget = normalizeExplicitTarget(targetInput)
      let isGroupTarget = normalizedTarget.hasPrefix("group:")
      let groupID = isGroupTarget ? String(normalizedTarget.dropFirst("group:".count)) : ""
      let actionText = groupCommandText(from: text, target: normalizedTarget)
      let requiresBulkConfirm = isGroupTarget && selectedActionValue.normalizedActionText != "ping"

      let response: APIResponse<CommandResponse>
      if isGroupTarget {
        response = try await CordycepsClient.sendGroupCommand(
          config: config,
          groupID: groupID,
          text: actionText,
          confirmBulk: requiresBulkConfirm
        )
      } else {
        response = try await CordycepsClient.sendCommand(config: config, text: text)
      }
      connectionState = .connected

      let isError = response.body.ok == false
      let message = response.body.message ?? response.body.error_code ?? (isError ? "Command failed." : "Command sent.")
      if !isError {
        setLastCommandSuccess()
        appendRecentCommand(text)
        triggerFeedback(.success)
      } else {
        triggerFeedback(.error)
      }
      setStatus(message, isError: isError)
      setResult(
        message: message,
        rawBody: response.rawJSON,
        requestID: response.body.request_id ?? "-",
        latencyMs: response.latencyMs,
        isError: isError
      )
      await loadCommandLogs(silent: true, append: false)
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func sendAdminCommand() async {
    guard !isSendingAdminCommand else {
      return
    }

    let target = normalizeDeviceID(adminTargetInput)
    let shell = normalizeAdminShell(adminShellInput)
    let commandValue = adminCommandInput.trimmed

    guard !target.isEmpty else {
      setStatus("Admin target is required.", isError: true)
      setResult(message: "Admin target is required.", rawBody: "Admin target is required.", isError: true)
      return
    }

    guard !commandValue.isEmpty else {
      setStatus("Admin command text is empty.", isError: true)
      setResult(message: "Admin command text is empty.", rawBody: "Admin command text is empty.", isError: true)
      return
    }

    adminTargetInput = target
    adminShellInput = shell
    persistAdminSettings()

    isSendingAdminCommand = true
    defer { isSendingAdminCommand = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.sendAdminCommand(
        config: config,
        target: target,
        shell: shell,
        commandValue: commandValue
      )

      connectionState = .connected
      let isError = response.body.ok == false
      let message = response.body.message ?? response.body.error_code ?? (isError ? "Admin command failed." : "Admin command sent.")
      if !isError {
        setLastCommandSuccess()
        triggerFeedback(.success)
      } else {
        triggerFeedback(.error)
      }

      setStatus(message, isError: isError)
      setResult(
        message: message,
        rawBody: response.rawJSON,
        requestID: response.body.request_id ?? "-",
        latencyMs: response.latencyMs,
        isError: isError
      )
      await loadCommandLogs(silent: true, append: false)
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func pushUpdate() async {
    guard !isPushingUpdate else {
      return
    }

    persistUpdateSettings()

    let target = normalizeExplicitUpdateTarget(updateTargetInput)
    let version = updateVersionInput
    let packageURL = updateURLInput
    let sha = updateShaInput.isEmpty ? nil : updateShaInput
    let signature = updateSignatureInput.isEmpty ? nil : updateSignatureInput
    let signatureKeyID = updateSignatureKeyIDInput.isEmpty ? nil : updateSignatureKeyIDInput
    let usePrivilegedHelper = updateUsePrivilegedHelperInput
    let queueIfOffline = updateQueueOfflineInput && target != "all"

    guard !target.isEmpty else {
      setStatus("Update target is required.", isError: true)
      setResult(message: "Update target is required.", rawBody: "Update target is required.", isError: true)
      return
    }

    guard !version.isEmpty else {
      setStatus("Update version is required.", isError: true)
      setResult(message: "Update version is required.", rawBody: "Update version is required.", isError: true)
      return
    }

    guard !packageURL.isEmpty else {
      setStatus("Update package URL is required.", isError: true)
      setResult(message: "Update package URL is required.", rawBody: "Update package URL is required.", isError: true)
      return
    }

    guard isValidAbsoluteUpdateURL(packageURL) else {
      setStatus("Update package URL must be an absolute http/https URL.", isError: true)
      setResult(
        message: "Update package URL must be an absolute http/https URL.",
        rawBody: "Update package URL must be an absolute http/https URL.",
        isError: true
      )
      return
    }

    if let sha, !isValidSHA256(sha) {
      setStatus("SHA256 must be a 64-character hex string.", isError: true)
      setResult(message: "SHA256 must be a 64-character hex string.", rawBody: "SHA256 must be a 64-character hex string.", isError: true)
      return
    }

    if let signature, signature.count > 1024 {
      setStatus("Signature must be at most 1024 characters.", isError: true)
      setResult(message: "Signature must be at most 1024 characters.", rawBody: "Signature must be at most 1024 characters.", isError: true)
      return
    }

    if let signatureKeyID, !isValidSignatureKeyID(signatureKeyID) {
      setStatus("Signature key ID must match [a-z0-9._-] and be at most 40 chars.", isError: true)
      setResult(
        message: "Signature key ID must match [a-z0-9._-] and be at most 40 chars.",
        rawBody: "Signature key ID must match [a-z0-9._-] and be at most 40 chars.",
        isError: true
      )
      return
    }

    if signatureKeyID != nil, signature == nil {
      setStatus("Signature key ID requires a signature value.", isError: true)
      setResult(message: "Signature key ID requires a signature value.", rawBody: "Signature key ID requires a signature value.", isError: true)
      return
    }

    let sizeBytes: Int?
    if updateSizeInput.isEmpty {
      sizeBytes = nil
    } else if let parsed = Int(updateSizeInput), parsed > 0 {
      sizeBytes = parsed
    } else {
      setStatus("Update size must be a positive integer.", isError: true)
      setResult(message: "Update size must be a positive integer.", rawBody: "Update size must be a positive integer.", isError: true)
      return
    }

    isPushingUpdate = true
    defer { isPushingUpdate = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.pushUpdate(
        config: config,
        target: target,
        version: version,
        packageURL: packageURL,
        queueIfOffline: queueIfOffline,
        sha256: sha,
        sizeBytes: sizeBytes,
        signature: signature,
        signatureKeyID: signatureKeyID,
        usePrivilegedHelper: usePrivilegedHelper
      )

      connectionState = .connected
      let isError = response.body.ok == false
      let message = response.body.message ?? response.body.error_code ?? (isError ? "Update failed." : "Update dispatched.")
      if isError {
        triggerFeedback(.error)
      } else {
        triggerFeedback(.success)
      }
      setStatus(message, isError: isError)
      setResult(
        message: message,
        rawBody: response.rawJSON,
        requestID: response.body.request_id ?? "-",
        latencyMs: response.latencyMs,
        isError: isError
      )
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func triggerLockdown() async {
    await applySecurityControl(
      quarantineEnabled: nil,
      killSwitchEnabled: nil,
      enforceLockdown: true,
      triggerLockdown: true,
      includeLockdownMinutes: true
    )
  }

  func quarantineDevice() async {
    await applySecurityControl(
      quarantineEnabled: true,
      killSwitchEnabled: nil,
      enforceLockdown: false,
      triggerLockdown: false,
      includeLockdownMinutes: false
    )
  }

  func unquarantineDevice() async {
    await applySecurityControl(
      quarantineEnabled: false,
      killSwitchEnabled: false,
      enforceLockdown: false,
      triggerLockdown: false,
      includeLockdownMinutes: false
    )
  }

  func setKillSwitch(_ enabled: Bool) async {
    await applySecurityControl(
      quarantineEnabled: nil,
      killSwitchEnabled: enabled,
      enforceLockdown: false,
      triggerLockdown: false,
      includeLockdownMinutes: false
    )
  }

  private func applySecurityControl(
    quarantineEnabled: Bool?,
    killSwitchEnabled: Bool?,
    enforceLockdown: Bool,
    triggerLockdown: Bool,
    includeLockdownMinutes: Bool
  ) async {
    guard !isApplyingSecurityControl else {
      return
    }

    persistSecuritySettings()

    let deviceID = normalizeDeviceID(securityDeviceInput)
    guard !deviceID.isEmpty else {
      setStatus("Security target device ID is required.", isError: true)
      setResult(message: "Security target device ID is required.", rawBody: "Security target device ID is required.", isError: true)
      return
    }

    let reason = securityReasonInput.trimmed
    let lockdownMinutes: Int?
    if includeLockdownMinutes {
      guard let parsed = parseLockdownMinutes(securityLockdownMinutesInput) else {
        setStatus("Lockdown minutes must be an integer between 1 and 240.", isError: true)
        setResult(
          message: "Lockdown minutes must be an integer between 1 and 240.",
          rawBody: "Lockdown minutes must be an integer between 1 and 240.",
          isError: true
        )
        return
      }
      lockdownMinutes = parsed
    } else {
      lockdownMinutes = nil
    }

    isApplyingSecurityControl = true
    defer { isApplyingSecurityControl = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.sendDeviceControl(
        config: config,
        deviceID: deviceID,
        quarantineEnabled: quarantineEnabled,
        killSwitchEnabled: killSwitchEnabled,
        reason: reason.isEmpty ? nil : reason,
        enforceLockdown: enforceLockdown,
        triggerLockdown: triggerLockdown,
        lockdownMinutes: lockdownMinutes
      )

      connectionState = .connected
      let lockdownFailed = response.body.lockdown?.attempted == true && response.body.lockdown?.ok == false
      let isError = response.body.ok == false || lockdownFailed
      let message =
        response.body.message ??
        response.body.lockdown?.message ??
        response.body.error_code ??
        (isError ? "Security control failed." : "Security control applied.")

      if isError {
        triggerFeedback(.error)
      } else {
        setLastCommandSuccess()
        triggerFeedback(.success)
      }

      setStatus(message, isError: isError)
      setResult(
        message: message,
        rawBody: response.rawJSON,
        requestID: response.body.device_id ?? deviceID,
        latencyMs: response.latencyMs,
        isError: isError
      )

      await loadDevices(silent: true, fromPolling: false)
      await loadCommandLogs(silent: true, append: false)
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  func pastePairingLinkFromClipboard() {
    if let copied = UIPasteboard.general.string, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      pairingLinkInput = copied
    }
  }

  func applyPairingLinkFromInput() {
    applyPairingLink(pairingLinkInput)
  }

  func applyPairingLink(_ rawLink: String) {
    let raw = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      setStatus("Pairing link is empty.", isError: true)
      setResult(message: "Pairing link is empty.", rawBody: "Pairing link is empty.", isError: true)
      return
    }

    let parameters = parsePairingParameters(raw)
    guard !parameters.isEmpty else {
      setStatus("No pairing parameters found in the link.", isError: true)
      setResult(message: "No pairing parameters found in the link.", rawBody: "No pairing parameters found in the link.", isError: true)
      return
    }

    let read: (String) -> String = { key in
      parameters[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    let token = read("token")
    let api = read("api")
    let target = read("target")
    let action = read("action")
    let arg = read("arg")
    let command = read("command")
    let updateTarget = read("update_target")
    let updateVersion = read("update_version")
    let updateURL = read("update_url")
    let updateSha = read("update_sha")
    let updateSize = read("update_size")
    let updateSignatureKeyID = read("update_signature_key_id")
    let updateSignature = read("update_signature")
    let updateUsePrivilegedHelper = read("update_use_privileged_helper")
    let updateQueueOffline = read("update_queue_offline")

    var applied = false

    if !api.isEmpty {
      let normalizedAPI = CordycepsClient.normalizeBaseURL(from: api)?.absoluteString ?? api
      apiBaseInput = normalizedAPI
      defaults.set(normalizedAPI, forKey: DefaultsKey.apiBase)
      applied = true
    }

    if !token.isEmpty {
      tokenInput = token
      defaults.set(token, forKey: DefaultsKey.token)
      applied = true
    }

    if !target.isEmpty {
      let normalizedTarget = normalizeExplicitTarget(target)
      if !normalizedTarget.isEmpty {
        targetInput = normalizedTarget
        defaults.set(normalizedTarget, forKey: DefaultsKey.target)
        applied = true
      }
    }

    if !updateTarget.isEmpty {
      let normalizedUpdateTarget = normalizeExplicitUpdateTarget(updateTarget)
      if !normalizedUpdateTarget.isEmpty {
        updateTargetInput = normalizedUpdateTarget
        defaults.set(normalizedUpdateTarget, forKey: DefaultsKey.updateTarget)
        applied = true
      }
    } else if !target.isEmpty {
      let normalizedTarget = normalizeExplicitTarget(target)
      if !normalizedTarget.isEmpty {
        updateTargetInput = normalizedTarget
        defaults.set(normalizedTarget, forKey: DefaultsKey.updateTarget)
      }
    }

    if !updateVersion.isEmpty {
      updateVersionInput = updateVersion
      defaults.set(updateVersion, forKey: DefaultsKey.updateVersion)
      applied = true
    }

    if !updateURL.isEmpty {
      updateURLInput = updateURL
      defaults.set(updateURL, forKey: DefaultsKey.updateURL)
      applied = true
    }

    if !updateSha.isEmpty {
      let sha = updateSha.lowercased()
      updateShaInput = sha
      defaults.set(sha, forKey: DefaultsKey.updateSha)
      applied = true
    }

    if !updateSize.isEmpty {
      updateSizeInput = updateSize
      defaults.set(updateSize, forKey: DefaultsKey.updateSize)
      applied = true
    }

    if !updateSignatureKeyID.isEmpty {
      let normalizedKeyID = updateSignatureKeyID.normalizedActionText
      updateSignatureKeyIDInput = normalizedKeyID
      defaults.set(normalizedKeyID, forKey: DefaultsKey.updateSignatureKeyID)
      applied = true
    }

    if !updateSignature.isEmpty {
      let sanitizedSignature = updateSignature
        .trimmed
        .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
      updateSignatureInput = sanitizedSignature
      defaults.set(sanitizedSignature, forKey: DefaultsKey.updateSignature)
      applied = true
    }

    if !updateUsePrivilegedHelper.isEmpty {
      let normalized = updateUsePrivilegedHelper.trimmed.lowercased()
      updateUsePrivilegedHelperInput = normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "on"
      defaults.set(updateUsePrivilegedHelperInput, forKey: DefaultsKey.updateUsePrivilegedHelper)
      applied = true
    }

    if !updateQueueOffline.isEmpty {
      let normalized = updateQueueOffline.trimmed.lowercased()
      updateQueueOfflineInput = !(normalized == "0" || normalized == "false" || normalized == "no")
      defaults.set(updateQueueOfflineInput, forKey: DefaultsKey.updateQueueOffline)
      applied = true
    }

    if !action.isEmpty {
      let normalizedAction = CommandLibrary.safeAction(action)
      selectedActionValue = normalizedAction
      defaults.set(normalizedAction, forKey: DefaultsKey.lastAction)
      applied = true
    }

    if !arg.isEmpty {
      argumentInput = arg
      applied = true
    }

    if !command.isEmpty {
      commandText = collapseWhitespacePreservingCase(command)
      applied = true
    } else if !target.isEmpty, !action.isEmpty {
      let combined = "\(target.normalizedActionText) \(action.normalizedActionText)\(arg.isEmpty ? "" : " \(arg)")"
      commandText = combined
      applied = true
    } else {
      commandText = composeCommand()
    }

    connectionState = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .disconnected : .retrying
    startPollingIfNeeded()
    startRealtimeEventsIfNeeded()

    if applied {
      pairingLinkInput = ""
      let message = "Connection configured from pairing link. Fields were auto-filled."
      setStatus(message, isError: false)
      setResult(message: message, rawBody: message, isError: false)
    }
  }

  func copyResponseToClipboard() {
    UIPasteboard.general.string = responseText
    setStatus("Result JSON copied.", isError: false)
    triggerFeedback(.success)
  }

  func copyCommandToClipboard() {
    let text = commandText.trimmed
    guard !text.isEmpty else {
      setStatus("Command text is empty.", isError: true)
      setResult(message: "Command text is empty.", rawBody: "Command text is empty.", isError: true)
      triggerFeedback(.error)
      return
    }

    UIPasteboard.general.string = text
    setStatus("Command copied to clipboard.", isError: false)
    triggerFeedback(.success)
  }

  func useRecentCommand(_ command: String) {
    let trimmed = command.trimmed
    guard !trimmed.isEmpty else {
      return
    }

    commandText = trimmed
    setStatus("Loaded a recent command.", isError: false)
  }

  func clearRecentCommands() {
    recentCommands = []
    defaults.removeObject(forKey: DefaultsKey.commandHistory)
    setStatus("Recent command history cleared.", isError: false)
  }

  func toggleSpeechCapture() async {
    if isListening {
      speechController.stop()
      isListening = false
      speechInfoText = "Speech stopped."
      return
    }

    guard speechController.isAvailable else {
      speechSupported = false
      speechInfoText = "Speech not supported on this device."
      setStatus(speechInfoText, isError: true)
      return
    }

    let speechAuth = await requestSpeechAuthorization()
    guard speechAuth == .authorized else {
      speechInfoText = "Speech permission denied."
      setStatus(speechInfoText, isError: true)
      setResult(message: speechInfoText, rawBody: speechInfoText, isError: true)
      return
    }

    let micGranted = await requestMicrophonePermission()
    guard micGranted else {
      speechInfoText = "Microphone permission denied."
      setStatus(speechInfoText, isError: true)
      setResult(message: speechInfoText, rawBody: speechInfoText, isError: true)
      return
    }

    do {
      try speechController.start(
        onTranscription: { [weak self] text, isFinal in
          guard let self else {
            return
          }
          Task { @MainActor in
            self.commandText = self.collapseWhitespacePreservingCase(text)
            self.speechInfoText = isFinal ? "Speech captured." : "Listening..."
            if isFinal {
              self.isListening = false
            }
          }
        },
        onError: { [weak self] message in
          guard let self else {
            return
          }
          Task { @MainActor in
            self.isListening = false
            self.speechInfoText = "Speech error: \(message)"
            self.setStatus(self.speechInfoText, isError: true)
            self.setResult(message: self.speechInfoText, rawBody: self.speechInfoText, isError: true)
          }
        }
      )
      isListening = true
      speechInfoText = "Listening..."
    } catch {
      let message = "Speech setup failed: \(error.localizedDescription)"
      isListening = false
      speechInfoText = message
      setStatus(message, isError: true)
      setResult(message: message, rawBody: message, isError: true)
    }
  }

  private func rotateTokens(rotateOwner: Bool, rotateBootstrap: Bool) async {
    guard !isRotatingTokens else {
      return
    }

    let ownerGraceSeconds: Int?
    if rotateOwner {
      let raw = ownerGraceSecondsInput.trimmed
      let candidate = raw.isEmpty ? 600 : parseOwnerGraceSeconds(raw)
      guard let parsed = candidate else {
        setStatus("Owner grace seconds must be an integer between 0 and 3600.", isError: true)
        setResult(
          message: "Owner grace seconds must be an integer between 0 and 3600.",
          rawBody: "Owner grace seconds must be an integer between 0 and 3600.",
          isError: true
        )
        return
      }
      ownerGraceSecondsInput = String(parsed)
      defaults.set(ownerGraceSecondsInput, forKey: DefaultsKey.ownerGraceSeconds)
      ownerGraceSeconds = parsed
    } else {
      ownerGraceSeconds = nil
    }

    isRotatingTokens = true
    defer { isRotatingTokens = false }

    do {
      let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
      let response = try await CordycepsClient.rotateTokens(
        config: config,
        rotateOwnerToken: rotateOwner,
        rotateBootstrapToken: rotateBootstrap,
        ownerGraceSeconds: ownerGraceSeconds
      )

      connectionState = .connected
      rotatedTokenPayload = response.rawJSON

      if rotateOwner, let newOwnerToken = response.body.owner_token, !newOwnerToken.isEmpty {
        tokenInput = newOwnerToken
        defaults.set(newOwnerToken, forKey: DefaultsKey.token)
      }

      startPollingIfNeeded()
      startRealtimeEventsIfNeeded()

      let message: String
      if let expiresAt = response.body.previous_owner_token_valid_until, !expiresAt.isEmpty {
        message = "Owner token rotated. Previous token valid until \(toLocalTimestamp(expiresAt))."
      } else {
        message = "Token rotation completed."
      }

      setStatus(message, isError: false)
      setResult(
        message: message,
        rawBody: response.rawJSON,
        requestID: "-",
        latencyMs: response.latencyMs,
        isError: false
      )
      triggerFeedback(.success)
    } catch {
      handle(error: error, silent: false, fromPolling: false)
    }
  }

  private func startRealtimeEventsIfNeeded() {
    eventsTask?.cancel()
    eventsTask = nil

    guard appIsActive else {
      return
    }

    guard !tokenInput.trimmed.isEmpty else {
      return
    }

    guard CordycepsClient.normalizeBaseURL(from: apiBaseInput) != nil else {
      return
    }

    eventsTask = Task { [weak self] in
      await self?.runEventLoop()
    }
  }

  private func clearInspector() {
    inspectedDeviceID = ""
    inspectedDevice = nil
    inspectedRealtime = nil
    inspectedAliases = []
    inspectedQueuedUpdates = []
    inspectedRecentLogs = []
  }

  private func runEventLoop() async {
    while !Task.isCancelled {
      do {
        let config = try CordycepsClient.makeConnectionConfig(apiBaseInput: apiBaseInput, tokenInput: tokenInput)
        let request = try CordycepsClient.makeRequest(config: config, path: "/api/events", method: "GET")
        let (bytes, _) = try await URLSession.shared.bytes(for: request)

        connectionState = .connected
        var currentEvent = "message"
        var dataLines: [String] = []

        for try await line in bytes.lines {
          if Task.isCancelled {
            return
          }

          if line.hasPrefix("event:") {
            currentEvent = String(line.dropFirst("event:".count)).trimmed
            continue
          }

          if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst("data:".count)).trimmed)
            continue
          }

          if line.isEmpty {
            let payload = dataLines.joined()
            if !payload.isEmpty {
              await handleRealtimeEvent(name: currentEvent, payload: payload)
            }
            currentEvent = "message"
            dataLines = []
          }
        }
      } catch {
        if Task.isCancelled {
          return
        }

        connectionState = .retrying
        try? await Task.sleep(nanoseconds: Self.eventReconnectDelayNs)
      }
    }
  }

  private func handleRealtimeEvent(name: String, payload: String) async {
    switch name {
    case "ready", "ping":
      connectionState = .connected
    case "device_status":
      let now = Date()
      if now.timeIntervalSince(lastDeviceStatusRefreshAt) < Self.deviceStatusMinRefreshInterval {
        return
      }
      lastDeviceStatusRefreshAt = now
      await loadDevices(silent: true, fromPolling: true)
      await loadGroups(silent: true)
    case "command_log":
      guard let data = payload.data(using: .utf8) else {
        return
      }

      guard let event = try? JSONDecoder().decode(CommandLogRealtimeEvent.self, from: data) else {
        return
      }

      let entry = event.asCommandLogEntry()
      upsertCommandLog(entry)
      if inspectedDeviceID == entry.device_id.normalizedActionText {
        upsertInspectedRecentLog(entry)
      }
    default:
      break
    }
  }

  private func startPollingIfNeeded() {
    pollingTask?.cancel()
    pollingTask = nil

    guard appIsActive else {
      return
    }

    let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      connectionState = .disconnected
      return
    }

    guard CordycepsClient.normalizeBaseURL(from: apiBaseInput) != nil else {
      connectionState = .retrying
      return
    }

    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: Self.pollIntervalNs)
        guard let self, !Task.isCancelled else {
          return
        }

        let activeToken = self.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if activeToken.isEmpty {
          self.connectionState = .disconnected
          return
        }

        if CordycepsClient.normalizeBaseURL(from: self.apiBaseInput) == nil {
          self.connectionState = .retrying
          return
        }

        await self.loadDevices(silent: true, fromPolling: true)
        await self.loadGroups(silent: true)
      }
    }
  }

  private func composeCommand() -> String {
    let target = normalizeTarget(targetInput)
    let action = selectedActionValue.normalizedActionText
    let argument = argumentInput.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !target.isEmpty, !action.isEmpty else {
      return ""
    }

    if action == "notify" {
      return argument.isEmpty ? "\(target) notify hello" : "\(target) notify \(argument)"
    }

    if action == "clipboard" || action == "copy" {
      return argument.isEmpty ? "\(target) \(action) copied from cordyceps" : "\(target) \(action) \(argument)"
    }

    if action == "type" {
      return argument.isEmpty ? "\(target) type hello from remote" : "\(target) type \(argument)"
    }

    if !argument.isEmpty, CommandLibrary.repeatableActions.contains(action) {
      return "\(target) \(action) \(argument)"
    }

    return "\(target) \(action)"
  }

  private func actionSupportedOnCurrentTarget(_ actionValue: String) -> Bool {
    let required = requiredCapability(for: actionValue)
    guard !required.isEmpty else {
      return true
    }

    guard let capabilities = capabilitiesForCurrentTarget() else {
      return true
    }

    return capabilities.contains(required)
  }

  private func requiredCapability(for actionValue: String) -> String {
    let normalized = actionValue.normalizedActionText
    if ["play", "pause", "play pause", "next", "previous", "volume up", "volume down", "mute"].contains(normalized) {
      return "media_control"
    }

    if ["brightness up", "brightness down", "display off", "screen off", "monitor off"].contains(normalized) {
      return "display_control"
    }

    if ["f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"].contains(normalized) {
      return "keyboard_control"
    }

    if ["enter", "escape", "tab", "space", "up", "down", "left", "right", "backspace", "delete", "home", "end", "page up", "page down", "copy shortcut", "paste shortcut", "cut shortcut", "undo shortcut", "redo shortcut", "select all shortcut", "alt tab", "alt f4", "type"].contains(normalized) {
      return "advanced_keyboard_control"
    }

    if normalized.hasPrefix("open ") {
      return "open_app"
    }

    if ["lock", "lock pc"].contains(normalized) {
      return "locking"
    }

    if ["notify"].contains(normalized) {
      return "notifications"
    }

    if ["clipboard", "copy"].contains(normalized) {
      return "clipboard_control"
    }

    if ["sleep", "sleep pc", "shutdown", "restart"].contains(normalized) {
      return "power_control"
    }

    if ["sign out", "log out", "logout"].contains(normalized) {
      return "session_control"
    }

    return ""
  }

  private func capabilitiesForCurrentTarget() -> Set<String>? {
    let target = normalizeExplicitTarget(targetInput)
    guard !target.isEmpty, target != "all" else {
      return nil
    }

    if target.hasPrefix("group:") {
      let groupID = String(target.dropFirst("group:".count))
      guard let group = groups.first(where: { $0.group_id.normalizedActionText == groupID.normalizedActionText }) else {
        return nil
      }

      var intersection: Set<String>?
      for memberID in group.device_ids {
        guard let device = devices.first(where: { $0.device_id.normalizedActionText == memberID.normalizedActionText }) else {
          continue
        }

        let capabilities = Set((device.capabilities ?? []).map { $0.normalizedActionText })
        if let current = intersection {
          intersection = current.intersection(capabilities)
        } else {
          intersection = capabilities
        }
      }

      return intersection
    }

    guard let device = devices.first(where: { $0.device_id.normalizedActionText == target.normalizedActionText }) else {
      return nil
    }

    return Set((device.capabilities ?? []).map { $0.normalizedActionText })
  }

  private func groupCommandText(from rawText: String, target: String) -> String {
    let trimmed = rawText.trimmed
    guard !trimmed.isEmpty else {
      return ""
    }

    let normalizedTarget = target.normalizedActionText
    let normalizedText = trimmed.normalizedActionText
    if normalizedText.hasPrefix("\(normalizedTarget) ") {
      if let split = trimmed.firstIndex(of: " ") {
        return String(trimmed[trimmed.index(after: split)...]).trimmed
      }
    }

    return trimmed
  }

  private func upsertCommandLog(_ entry: CommandLogEntry) {
    if let existing = commandLogs.firstIndex(where: { $0.id == entry.id }) {
      commandLogs[existing] = entry
      return
    }

    commandLogs.insert(entry, at: 0)
    if commandLogs.count > 120 {
      commandLogs = Array(commandLogs.prefix(120))
    }
  }

  private func upsertInspectedRecentLog(_ entry: CommandLogEntry) {
    if let existing = inspectedRecentLogs.firstIndex(where: { $0.id == entry.id }) {
      inspectedRecentLogs[existing] = entry
      return
    }

    inspectedRecentLogs.insert(entry, at: 0)
    if inspectedRecentLogs.count > 120 {
      inspectedRecentLogs = Array(inspectedRecentLogs.prefix(120))
    }
  }

  private func normalizeTarget(_ input: String) -> String {
    let normalized = normalizeExplicitTarget(input)
    if normalized.isEmpty {
      return "m1"
    }
    return normalized
  }

  private func normalizeExplicitTarget(_ input: String) -> String {
    let normalized = input.normalizedActionText
    guard isValidTarget(normalized) else {
      return ""
    }
    return normalized
  }

  private func normalizeExplicitUpdateTarget(_ input: String) -> String {
    let normalized = input.normalizedActionText
    guard normalized.range(of: #"^(all|[a-z][a-z0-9_-]{1,31})$"#, options: .regularExpression) != nil else {
      return ""
    }
    return normalized
  }

  private static func normalizeDeviceIDValue(_ input: String) -> String {
    let normalized = input.normalizedActionText
    guard normalized.range(of: #"^[a-z][a-z0-9_-]{1,31}$"#, options: .regularExpression) != nil else {
      return ""
    }
    return normalized
  }

  private static func normalizeAdminShellValue(_ input: String) -> String {
    let normalized = input.trimmed.lowercased()
    if normalized == "powershell" {
      return "powershell"
    }
    return "cmd"
  }

  private func normalizeDeviceID(_ input: String) -> String {
    Self.normalizeDeviceIDValue(input)
  }

  private func normalizeAlias(_ input: String) -> String {
    input.normalizedActionText
  }

  private func normalizeAdminShell(_ input: String) -> String {
    Self.normalizeAdminShellValue(input)
  }

  private func syncSingleDeviceControls(with target: String) {
    let singleDevice = normalizeDeviceID(target)
    guard !singleDevice.isEmpty else {
      return
    }

    renameDeviceInput = singleDevice
    aliasDeviceInput = singleDevice
    securityDeviceInput = singleDevice
    defaults.set(singleDevice, forKey: DefaultsKey.renameDevice)
    defaults.set(singleDevice, forKey: DefaultsKey.aliasDevice)
    defaults.set(singleDevice, forKey: DefaultsKey.securityDevice)
  }

  private func isValidTarget(_ value: String) -> Bool {
    value.range(of: #"^(all|[a-z][a-z0-9_-]{1,31}|group:[a-z][a-z0-9_-]{1,31})$"#, options: .regularExpression) != nil
  }

  private func isValidSHA256(_ value: String) -> Bool {
    value.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
  }

  private func isValidSignatureKeyID(_ value: String) -> Bool {
    value.range(of: #"^[a-z0-9._-]{1,40}$"#, options: .regularExpression) != nil
  }

  private func parseLockdownMinutes(_ value: String) -> Int? {
    let trimmed = value.trimmed
    if trimmed.isEmpty {
      return 30
    }

    guard let parsed = Int(trimmed), (1 ... 240).contains(parsed) else {
      return nil
    }

    return parsed
  }

  private func parseOwnerGraceSeconds(_ value: String) -> Int? {
    let trimmed = value.trimmed
    guard let parsed = Int(trimmed), (0 ... 3600).contains(parsed) else {
      return nil
    }
    return parsed
  }

  private func isValidAbsoluteUpdateURL(_ value: String) -> Bool {
    guard let parsed = URL(string: value), let scheme = parsed.scheme?.lowercased() else {
      return false
    }

    guard scheme == "https" || scheme == "http" else {
      return false
    }

    return parsed.host != nil
  }

  private func parsePairingParameters(_ raw: String) -> [String: String] {
    var queryValues: [String: String] = [:]
    var hashValues: [String: String] = [:]

    if let components = URLComponents(string: raw), let items = components.queryItems {
      for item in items {
        let key = item.name.lowercased()
        let value = item.value?.decodedURLValue ?? ""
        if !value.isEmpty {
          queryValues[key] = value
        }
      }
    }

    if let hashIndex = raw.firstIndex(of: "#") {
      let fragment = String(raw[raw.index(after: hashIndex)...])
      if !fragment.isEmpty,
         let hashComponents = URLComponents(string: "https://cordyceps.invalid/?\(fragment)"),
         let items = hashComponents.queryItems
      {
        for item in items {
          let key = item.name.lowercased()
          let value = item.value?.decodedURLValue ?? ""
          if !value.isEmpty {
            hashValues[key] = value
          }
        }
      }
    }

    var merged = queryValues
    for (key, value) in hashValues {
      merged[key] = value
    }

    return merged
  }

  private func sortedDevices(_ input: [DeviceRecord]) -> [DeviceRecord] {
    input.sorted { lhs, rhs in
      if lhs.isOnline != rhs.isOnline {
        return lhs.isOnline && !rhs.isOnline
      }
      return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }
  }

  private func collapseWhitespacePreservingCase(_ input: String) -> String {
    input
      .trimmed
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }

  private func appendRecentCommand(_ command: String) {
    let normalized = collapseWhitespacePreservingCase(command)
    guard !normalized.isEmpty else {
      return
    }

    recentCommands.removeAll { $0 == normalized }
    recentCommands.insert(normalized, at: 0)
    if recentCommands.count > Self.maxCommandHistory {
      recentCommands = Array(recentCommands.prefix(Self.maxCommandHistory))
    }
    persistCommandHistory()
  }

  private func loadCommandHistory() -> [String] {
    guard let payload = defaults.array(forKey: DefaultsKey.commandHistory) as? [String] else {
      return []
    }
    return payload
      .map { collapseWhitespacePreservingCase($0) }
      .filter { !$0.isEmpty }
  }

  private func persistCommandHistory() {
    defaults.set(Array(recentCommands.prefix(Self.maxCommandHistory)), forKey: DefaultsKey.commandHistory)
  }

  private func setLastCommandSuccess() {
    let nowISO = ISO8601DateFormatter().string(from: Date())
    defaults.set(nowISO, forKey: DefaultsKey.lastSuccess)
    lastSuccessLabel = "Last success: \(toLocalTimestamp(nowISO))"
  }

  private func toLocalTimestamp(_ isoString: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: isoString) else {
      return "never"
    }
    return DateFormatter.cordyceps.string(from: date)
  }

  private func setStatus(_ text: String, isError: Bool) {
    statusText = text
    statusIsError = isError
  }

  private func setResult(
    message: String,
    rawBody: String,
    requestID: String = "-",
    latencyMs: Double? = nil,
    isError: Bool
  ) {
    resultStatus = isError ? "error" : "ok"
    resultRequestId = requestID
    resultLatency = latencyMs.map { "\(Int($0.rounded())) ms" } ?? "-"
    resultMessage = message
    responseText = rawBody
    resultIsError = isError
  }

  private func handle(error: Error, silent: Bool, fromPolling: Bool) {
    let message: String
    var shouldDisconnect = false

    if let clientError = error as? CordycepsClientError {
      switch clientError {
      case .missingToken:
        shouldDisconnect = true
        message = clientError.localizedDescription
      case let .httpError(status, serverMessage):
        shouldDisconnect = status == 401 || status == 403
        if status == 401 || status == 403 {
          message = "Authentication failed. Check PHONE_API_TOKEN and save again."
        } else if status == 404 {
          message = "API endpoint not found. Verify API base URL."
        } else {
          message = serverMessage
        }
      default:
        message = clientError.localizedDescription
      }
    } else if let urlError = error as? URLError {
      if urlError.code == .appTransportSecurityRequiresSecureConnection {
        message = "Blocked by iOS security policy. Use an https API URL, not plain http."
      } else {
        message = "Cannot reach server. Connection is retrying (\(urlError.localizedDescription))."
      }
    } else {
      message = error.localizedDescription
    }

    connectionState = shouldDisconnect ? .disconnected : .retrying

    if silent {
      if fromPolling && !shouldDisconnect {
        connectionState = .retrying
      }
      return
    }

    setStatus(message, isError: true)
    setResult(message: message, rawBody: message, isError: true)
    triggerFeedback(.error)
  }

  private func triggerFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    let feedback = UINotificationFeedbackGenerator()
    feedback.prepare()
    feedback.notificationOccurred(type)
  }

  private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }

  private func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
      if #available(iOS 17.0, *) {
        AVAudioApplication.requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      } else {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
    }
  }
}

private struct CommandLogRealtimeEvent: Decodable {
  let request_id: String
  let device_id: String
  let source: String
  let raw_text: String
  let parsed_target: String
  let parsed_type: String
  let status: String
  let message: String?
  let error_code: String?
  let ts: String

  func asCommandLogEntry() -> CommandLogEntry {
    let identifier = "\(request_id):\(device_id)"
    return CommandLogEntry(
      id: identifier,
      request_id: request_id,
      device_id: device_id,
      source: source,
      raw_text: raw_text,
      parsed_target: parsed_target,
      parsed_type: parsed_type,
      status: status,
      result_message: message,
      error_code: error_code,
      created_at: ts,
      completed_at: ts
    )
  }
}

private final class SpeechController {
  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  private let audioEngine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  var isAvailable: Bool {
    recognizer != nil
  }

  func start(
    onTranscription: @escaping (_ text: String, _ isFinal: Bool) -> Void,
    onError: @escaping (_ message: String) -> Void
  ) throws {
    guard let recognizer, recognizer.isAvailable else {
      throw NSError(domain: "CordycepsSpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is unavailable."])
    }

    stop()

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    self.request = request

    let inputNode = audioEngine.inputNode
    inputNode.removeTap(onBus: 0)

    let format = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.request?.append(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()

    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      if let result {
        onTranscription(result.bestTranscription.formattedString, result.isFinal)
        if result.isFinal {
          self?.stop()
        }
      }

      if let error {
        onError(error.localizedDescription)
        self?.stop()
      }
    }
  }

  func stop() {
    if audioEngine.isRunning {
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
    }

    request?.endAudio()
    request = nil

    task?.cancel()
    task = nil

    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
