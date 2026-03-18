import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = RemoteViewModel()
  @Environment(\.scenePhase) private var scenePhase

  @State private var showDangerousSendConfirmation = false
  @State private var showUpdateConfirmation = false
  @State private var showDeleteDeviceConfirmation = false
  @State private var pendingDeleteDeviceID = ""

  var body: some View {
    NavigationStack {
      ZStack {
        backgroundLayer

        ScrollView {
          LazyVStack(spacing: 18) {
            heroCard
            connectionCard
            devicesCard
            inspectorCard
            groupsCard
            commandCard
            securityCard
            adminCommandCard
            updateCard
            historyCard
            apiKeysCard
            tokenRotationCard
            resultCard
          }
          .padding(.horizontal, 16)
          .padding(.top, 10)
          .padding(.bottom, 28)
        }
      }
      .navigationTitle("Cordyceps Bloom")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          if viewModel.isLoadingDevices {
            ProgressView()
              .tint(CordycepsTheme.myceliumGlow)
          } else {
            Button {
              Task {
                await viewModel.loadDevices()
                await viewModel.loadGroups(silent: true)
                await viewModel.loadCommandLogs(silent: true, append: false)
              }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            .tint(CordycepsTheme.myceliumGlow)
          }
        }
      }
      .task {
        await viewModel.handleInitialLoad()
      }
      .onOpenURL { url in
        viewModel.applyPairingLink(url.absoluteString)
      }
      .onChange(of: scenePhase) { phase in
        viewModel.setAppLifecycle(isActive: phase == .active)
      }
      .confirmationDialog(
        "This command can immediately interrupt the target device.",
        isPresented: $showDangerousSendConfirmation,
        titleVisibility: .visible
      ) {
        Button("Send Anyway", role: .destructive) {
          Task { await viewModel.sendCommand() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Confirm that the target is correct before dispatching.")
      }
      .confirmationDialog(
        "Push this agent update now?",
        isPresented: $showUpdateConfirmation,
        titleVisibility: .visible
      ) {
        Button("Push Update", role: .destructive) {
          Task { await viewModel.pushUpdate() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Updates may restart agents and break connectivity if details are wrong.")
      }
      .confirmationDialog(
        "Delete saved device record \(pendingDeleteDeviceID)?",
        isPresented: $showDeleteDeviceConfirmation,
        titleVisibility: .visible
      ) {
        Button("Delete Record", role: .destructive) {
          let deviceID = pendingDeleteDeviceID
          pendingDeleteDeviceID = ""
          Task { await viewModel.deleteDeviceRecord(deviceID) }
        }
        Button("Cancel", role: .cancel) {
          pendingDeleteDeviceID = ""
        }
      } message: {
        Text("This removes aliases, queued updates, and history tied to this designation.")
      }
    }
  }

  private var backgroundLayer: some View {
    ZStack {
      LinearGradient(
        colors: [CordycepsTheme.soilBlack, CordycepsTheme.soilDeep, CordycepsTheme.forestNight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      Circle()
        .fill(
          RadialGradient(
            colors: [CordycepsTheme.myceliumGlow.opacity(0.45), .clear],
            center: .center,
            startRadius: 8,
            endRadius: 260
          )
        )
        .frame(width: 360, height: 360)
        .offset(x: -130, y: -280)
        .blur(radius: 8)

      Circle()
        .fill(
          RadialGradient(
            colors: [CordycepsTheme.capsuleAmber.opacity(0.34), .clear],
            center: .center,
            startRadius: 8,
            endRadius: 240
          )
        )
        .frame(width: 300, height: 300)
        .offset(x: 170, y: -320)
        .blur(radius: 8)

      Capsule()
        .fill(CordycepsTheme.sporePurple.opacity(0.18))
        .frame(width: 420, height: 190)
        .rotationEffect(.degrees(-18))
        .offset(x: 60, y: 290)
        .blur(radius: 40)
    }
  }

  private var heroCard: some View {
    CordycepsCard(
      tint: LinearGradient(
        colors: [
          CordycepsTheme.myceliumGlow.opacity(0.35),
          CordycepsTheme.capsuleAmber.opacity(0.26),
          CordycepsTheme.sporePurple.opacity(0.18),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    ) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Mycelium command nexus")
              .font(.system(.title3, design: .rounded).weight(.bold))
              .foregroundStyle(.white)
            Text("Fungus-themed remote control for your Cordyceps fleet with live state, safer dispatch, and fast reuse.")
              .font(.system(.footnote, design: .rounded))
              .foregroundStyle(Color.white.opacity(0.78))
          }

          Spacer(minLength: 0)
          statusBadge
        }

        HStack {
          Text(viewModel.lastSuccessLabel)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.76))
          Spacer(minLength: 0)
          Text(viewModel.deviceSummaryText)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(CordycepsTheme.myceliumGlow.opacity(0.9))
        }
      }
    }
  }

  private var connectionCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Connection")

        TextField("https://your-cordyceps-host.example", text: $viewModel.apiBaseInput)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()

        SecureField("PHONE_API_TOKEN", text: $viewModel.tokenInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()

        TextField("Default target (m1)", text: $viewModel.targetInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.targetInput) { _ in
            viewModel.targetDidChange()
          }

        VStack(spacing: 8) {
          HStack(spacing: 8) {
            actionButton("Save", icon: "checkmark.circle.fill", role: .normal) {
              viewModel.saveConnectionSettings()
            }
            actionButton("Test Token", icon: "shield.checkered", role: .normal, loading: viewModel.isTestingToken) {
              Task { await viewModel.testToken() }
            }
          }

          HStack(spacing: 8) {
            actionButton("Load Devices", icon: "rectangle.3.group.bubble.left", role: .normal, loading: viewModel.isLoadingDevices) {
              Task { await viewModel.loadDevices() }
            }
            Text(viewModel.deviceSummaryText)
              .font(.system(.caption, design: .rounded).weight(.semibold))
              .foregroundStyle(Color.white.opacity(0.70))
              .frame(maxWidth: .infinity, alignment: .trailing)
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Shared Device Name")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.72))

          HStack(spacing: 8) {
            TextField("Device ID (t1)", text: $viewModel.renameDeviceInput)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .cordycepsFieldStyle()

            TextField("Display Name (t1-Molly)", text: $viewModel.renameDisplayNameInput)
              .textInputAutocapitalization(.words)
              .autocorrectionDisabled()
              .cordycepsFieldStyle()
          }

          actionButton("Save Name", icon: "rectangle.and.pencil.and.ellipsis", role: .normal, loading: viewModel.isSavingDisplayName) {
            Task { await viewModel.saveDeviceDisplayName() }
          }

          Text("Saved on the server so every remote sees the same label. Leave empty to clear.")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.66))
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Device App Aliases")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.72))

          TextField("Device ID (t1)", text: $viewModel.aliasDeviceInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .cordycepsFieldStyle()

          TextField("Alias phrase (browser work)", text: $viewModel.aliasKeyInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .cordycepsFieldStyle()

          TextField("Canonical app (chrome)", text: $viewModel.aliasAppInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .cordycepsFieldStyle()

          actionButton("Save Alias", icon: "link.badge.plus", role: .normal, loading: viewModel.isSavingAlias) {
            Task { await viewModel.saveDeviceAlias() }
          }

          Text("Maps custom open phrases to built-in app targets for one device.")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.66))
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Pairing Link")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.72))

          TextField("Paste pairing URL", text: $viewModel.pairingLinkInput)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .cordycepsFieldStyle()

          HStack(spacing: 8) {
            actionButton("Paste", icon: "doc.on.clipboard", role: .normal) {
              viewModel.pastePairingLinkFromClipboard()
            }
            actionButton("Apply Link", icon: "link.badge.plus", role: .normal) {
              viewModel.applyPairingLinkFromInput()
            }
          }
        }

        Text(viewModel.statusText)
          .font(.system(.caption, design: .rounded).weight(.medium))
          .foregroundStyle(
            viewModel.statusIsError
              ? CordycepsTheme.errorText
              : Color.white.opacity(0.74)
          )
      }
    }
  }

  private var devicesCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Devices")

        HStack(spacing: 8) {
          TextField("Search name, host, or ID", text: $viewModel.deviceSearchInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .cordycepsFieldStyle()

          Button {
            viewModel.showOnlyOnlineDevices.toggle()
          } label: {
            HStack(spacing: 6) {
              Image(systemName: viewModel.showOnlyOnlineDevices ? "dot.radiowaves.left.and.right" : "circle.dashed")
              Text("Online")
                .lineLimit(1)
            }
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
              Capsule()
                .fill(viewModel.showOnlyOnlineDevices ? CordycepsTheme.primaryButton.opacity(0.85) : CordycepsTheme.cardFill)
                .overlay(Capsule().stroke(CordycepsTheme.strokeSoft, lineWidth: 1))
            )
          }
          .foregroundStyle(viewModel.showOnlyOnlineDevices ? CordycepsTheme.buttonTextPrimary : Color.white)
        }

        if viewModel.devices.isEmpty {
          emptyState("No enrolled devices loaded yet.")
        } else if viewModel.filteredDevices.isEmpty {
          emptyState("No devices match your current filters.")
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
              ForEach(viewModel.filteredDevices, id: \.id) { device in
                deviceCard(device)
              }
            }
            .padding(.vertical, 2)
          }
        }
      }
    }
  }

  private var inspectorCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Device Inspector")

        if !viewModel.hasInspectorData {
          emptyState("Tap Inspect on a device card to load full record details.")
        } else if let device = viewModel.inspectedDevice {
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
              Text(device.displayTitle)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

              Text(device.device_id)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.68))

              if let profile = device.profile, !profile.isEmpty {
                Text("profile \(profile)")
                  .font(.system(.caption2, design: .rounded).weight(.semibold))
                  .foregroundStyle(CordycepsTheme.capsuleAmber.opacity(0.92))
              }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
              Capsule()
                .fill(device.isOnline ? CordycepsTheme.myceliumGlow : CordycepsTheme.errorDot)
                .frame(width: 8, height: 8)
              Text(device.isOnline ? "online" : "offline")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(device.isOnline ? CordycepsTheme.myceliumGlow : CordycepsTheme.errorText)
            }
          }

          HStack(spacing: 8) {
            actionButton("Refresh", icon: "arrow.clockwise", role: .normal, loading: viewModel.isLoadingDeviceInspector) {
              Task { await viewModel.refreshInspectedDevice() }
            }
            actionButton("Close", icon: "xmark.circle.fill", role: .normal) {
              viewModel.closeInspector()
            }
            actionButton(
              "Delete Record",
              icon: "trash.fill",
              role: .danger,
              loading: viewModel.isDeletingDevice(device.device_id),
              disabled: !viewModel.canDeleteInspectedDevice
            ) {
              pendingDeleteDeviceID = device.device_id.normalizedActionText
              showDeleteDeviceConfirmation = true
            }
          }

          inspectorInfoRow("Hostname", (device.hostname?.trimmed ?? "").isEmpty ? "n/a" : (device.hostname ?? "n/a"))
          inspectorInfoRow("Username", (device.username?.trimmed ?? "").isEmpty ? "n/a" : (device.username ?? "n/a"))
          inspectorInfoRow("Last Seen", device.lastSeenLabel)
          inspectorInfoRow("Connected", viewModel.inspectedRealtime?.connected == true ? "true" : "false")
          inspectorInfoRow("Connected At", toLocal(viewModel.inspectedRealtime?.connected_at ?? ""))
          inspectorInfoRow("Realtime Last Seen", toLocal(viewModel.inspectedRealtime?.last_seen_at ?? ""))
          inspectorInfoRow("Quarantine", (device.quarantine_enabled ?? false) ? "enabled" : "off")
          inspectorInfoRow("Kill Switch", (device.kill_switch_enabled ?? false) ? "enabled" : "off")
          inspectorInfoRow("Reason", (device.quarantine_reason?.trimmed ?? "").isEmpty ? "none" : (device.quarantine_reason ?? "none"))

          Text("Capabilities")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.72))

          if let capabilities = device.capabilities, !capabilities.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 6) {
                ForEach(Array(capabilities.prefix(20).enumerated()), id: \.offset) { _, capability in
                  Text(capability)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                      Capsule()
                        .fill(CordycepsTheme.cardFill)
                        .overlay(Capsule().stroke(CordycepsTheme.strokeSoft, lineWidth: 1))
                    )
                    .foregroundStyle(Color.white.opacity(0.86))
                }
              }
              .padding(.vertical, 2)
            }
          } else {
            emptyState("No capabilities reported.")
          }

          Text("App Aliases")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.72))

          if viewModel.inspectedAliases.isEmpty {
            emptyState("No aliases configured.")
          } else {
            VStack(spacing: 6) {
              ForEach(Array(viewModel.inspectedAliases.prefix(8)), id: \.id) { alias in
                inspectorInfoRow(alias.alias, alias.app)
              }
            }
          }

          Text("Queued Updates")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.72))

          if viewModel.inspectedQueuedUpdates.isEmpty {
            emptyState("No queued updates.")
          } else {
            VStack(spacing: 6) {
              ForEach(Array(viewModel.inspectedQueuedUpdates.prefix(8)), id: \.stableID) { queued in
                inspectorInfoRow(queued.version, "\(queued.package_url) • \(toLocal(queued.created_at))")
              }
            }
          }

          Text("Recent Commands")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.72))

          if viewModel.inspectedRecentLogs.isEmpty {
            emptyState("No recent command logs.")
          } else {
            VStack(spacing: 6) {
              ForEach(Array(viewModel.inspectedRecentLogs.prefix(10)), id: \.id) { entry in
                inspectorInfoRow(
                  "\(entry.parsed_type) • \(entry.status)",
                  entry.result_message ?? entry.raw_text
                )
              }
            }
          }

          Text("Device Info Snapshot")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.72))

          if viewModel.inspectedDeviceInfoSummary.isEmpty {
            emptyState("No runtime device-info payload.")
          } else {
            VStack(spacing: 6) {
              ForEach(Array(viewModel.inspectedDeviceInfoSummary.enumerated()), id: \.offset) { item in
                inspectorInfoRow(item.element.0, item.element.1)
              }
            }
          }
        }
      }
    }
  }

  private func deviceCard(_ device: DeviceRecord) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(device.displayTitle)
        .font(.system(.headline, design: .rounded).weight(.bold))
        .foregroundStyle(.white)
        .lineLimit(1)

      if let subtitle = device.subtitleLabel {
        Text(subtitle)
          .font(.system(.caption2, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.68))
          .lineLimit(2)
      }

      HStack(spacing: 8) {
        Capsule()
          .fill(device.isOnline ? CordycepsTheme.myceliumGlow : CordycepsTheme.errorDot)
          .frame(width: 8, height: 8)
        Text(device.isOnline ? "online" : "offline")
          .font(.system(.caption, design: .rounded).weight(.semibold))
          .foregroundStyle(device.isOnline ? CordycepsTheme.myceliumGlow : CordycepsTheme.errorText)
      }

      Text("last seen \(device.lastSeenLabel)")
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.66))

      Text("agent \(device.agentVersionLabel)")
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .foregroundStyle(CordycepsTheme.capsuleAmber.opacity(0.95))

      if let capabilities = device.capabilities, !capabilities.isEmpty {
        Text(capabilities.prefix(3).joined(separator: ", "))
          .font(.system(.caption2, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.6))
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      HStack(spacing: 6) {
        Button {
          viewModel.useDeviceAsTarget(device.device_id)
        } label: {
          Text("Use")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(device.isOnline ? CordycepsTheme.primaryButton : CordycepsTheme.offlineButton)

        Button {
          Task { await viewModel.inspectDevice(device.device_id) }
        } label: {
          if viewModel.isLoadingDeviceInspector && viewModel.inspectedDeviceID == device.device_id.normalizedActionText {
            ProgressView()
              .tint(CordycepsTheme.capsuleAmber)
              .frame(maxWidth: .infinity)
          } else {
            Text("Inspect")
              .font(.system(.caption, design: .rounded).weight(.bold))
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
        .tint(CordycepsTheme.capsuleAmber)

        Button {
          pendingDeleteDeviceID = device.device_id.normalizedActionText
          showDeleteDeviceConfirmation = true
        } label: {
          if viewModel.isDeletingDevice(device.device_id) {
            ProgressView()
              .tint(CordycepsTheme.errorDot)
              .frame(maxWidth: .infinity)
          } else {
            Text("Delete")
              .font(.system(.caption, design: .rounded).weight(.bold))
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
        .tint(CordycepsTheme.errorDot)
        .disabled(device.isOnline)
      }
    }
    .padding(12)
    .frame(width: 246, height: 212, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .fill(CordycepsTheme.cardFill)
        .overlay(
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
        )
    )
  }

  private var groupsCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Groups")

        Text("Create and use guarded bulk-target groups (target format: group:<id>).")
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.72))

        TextField("Group ID (office)", text: $viewModel.groupIDInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()

        TextField("Group Name (Office PCs)", text: $viewModel.groupDisplayNameInput)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()

        TextField("Description (optional)", text: $viewModel.groupDescriptionInput)
          .textInputAutocapitalization(.sentences)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()

        TextField("Members (m1,t1,s1)", text: $viewModel.groupMembersInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()

        HStack(spacing: 8) {
          actionButton("Save Group", icon: "square.and.arrow.down.fill", role: .normal, loading: viewModel.isSavingGroup) {
            Task { await viewModel.saveGroup() }
          }
          actionButton("Delete Group", icon: "trash.fill", role: .danger, loading: viewModel.isDeletingGroup) {
            Task { await viewModel.deleteGroup() }
          }
          actionButton("Load Groups", icon: "arrow.clockwise.circle.fill", role: .normal, loading: viewModel.isLoadingGroups) {
            Task { await viewModel.loadGroups() }
          }
        }

        if viewModel.groups.isEmpty {
          emptyState("No groups loaded yet.")
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
              ForEach(viewModel.groups, id: \.id) { group in
                VStack(alignment: .leading, spacing: 8) {
                  Text(group.display_name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                  Text("\(group.group_id) • \(group.device_ids.count) members")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))

                  if let description = group.description, !description.isEmpty {
                    Text(description)
                      .font(.system(.caption2, design: .rounded))
                      .foregroundStyle(Color.white.opacity(0.68))
                      .lineLimit(2)
                  }

                  if let onlineCount = group.online_count {
                    Text("\(onlineCount) online")
                      .font(.system(.caption2, design: .rounded).weight(.semibold))
                      .foregroundStyle(CordycepsTheme.myceliumGlow.opacity(0.9))
                  }

                  Spacer(minLength: 0)

                  HStack(spacing: 8) {
                    Button {
                      viewModel.useGroupAsTarget(group.group_id)
                    } label: {
                      Text("Use Group")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CordycepsTheme.primaryButton)

                    Button {
                      viewModel.selectGroupForEditing(group)
                    } label: {
                      Text("Edit")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(CordycepsTheme.capsuleAmber)
                  }
                }
                .padding(12)
                .frame(width: 250, height: 172, alignment: .topLeading)
                .background(
                  RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(CordycepsTheme.cardFill)
                    .overlay(
                      RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
                    )
                )
              }
            }
            .padding(.vertical, 2)
          }
        }
      }
    }
  }

  private var commandCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Command")

        TextField("Target (m1, all, or group:office)", text: $viewModel.targetInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.targetInput) { _ in
            viewModel.targetDidChange()
          }

        TextField("Search commands, aliases, and apps", text: $viewModel.actionSearchInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.actionSearchInput) { _ in
            viewModel.actionSearchDidChange()
          }

        Picker("Action", selection: $viewModel.selectedActionValue) {
          ForEach(viewModel.actionPickerGroups) { group in
            Section(group.category) {
              ForEach(group.entries) { entry in
                Text(entry.label).tag(entry.value)
              }
            }
          }
        }
        .pickerStyle(.menu)
        .tint(CordycepsTheme.myceliumGlow)
        .onChange(of: viewModel.selectedActionValue) { _ in
          viewModel.actionSelectionDidChange()
        }

        Text(viewModel.actionSearchInfo)
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.70))

        if !viewModel.selectedActionSupported {
          dangerZone("This action is not supported by the currently selected target.")
        }

        if viewModel.selectedActionUsesArgument {
          TextField(viewModel.selectedActionArgumentPlaceholder, text: $viewModel.argumentInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .cordycepsFieldStyle()
            .onChange(of: viewModel.argumentInput) { _ in
              viewModel.composeFromInputs()
            }
        }

        if viewModel.selectedActionIsDangerous {
          dangerZone("This command can interrupt the machine immediately. Review target and intent before sending.")
        }

        Text("Quick Cast")
          .font(.system(.caption, design: .rounded).weight(.semibold))
          .foregroundStyle(Color.white.opacity(0.74))

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(CommandLibrary.quickActions, id: \.self) { action in
              Button(action) {
                viewModel.argumentInput = ""
                viewModel.setAction(action)
              }
              .font(.system(.caption, design: .rounded).weight(.semibold))
              .padding(.horizontal, 12)
              .padding(.vertical, 7)
              .background(
                Capsule()
                  .fill(CordycepsTheme.cardFill)
                  .overlay(Capsule().stroke(CordycepsTheme.strokeSoft, lineWidth: 1))
              )
              .foregroundStyle(Color.white.opacity(0.88))
            }
          }
          .padding(.vertical, 2)
        }

        if !viewModel.recentCommands.isEmpty {
          HStack {
            Text("Recent")
              .font(.system(.caption, design: .rounded).weight(.semibold))
              .foregroundStyle(Color.white.opacity(0.74))
            Spacer(minLength: 0)
            Button("Clear") {
              viewModel.clearRecentCommands()
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(CordycepsTheme.capsuleAmber.opacity(0.95))
          }

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(viewModel.recentCommands, id: \.self) { command in
                Button {
                  viewModel.useRecentCommand(command)
                } label: {
                  Text(command)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .foregroundStyle(CordycepsTheme.myceliumGlow)
                .background(
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.23))
                    .overlay(
                      RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
                    )
                )
              }
            }
            .padding(.vertical, 2)
          }
        }

        TextField("Command text", text: $viewModel.commandText, axis: .vertical)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .lineLimit(2 ... 6)
          .cordycepsFieldStyle()

        HStack(spacing: 8) {
          actionButton("Build", icon: "wand.and.stars", role: .normal) {
            viewModel.composeFromInputs()
          }
          actionButton("Copy", icon: "doc.on.doc", role: .normal) {
            viewModel.copyCommandToClipboard()
          }
          actionButton(
            viewModel.isListening ? "Stop" : "Speak",
            icon: viewModel.isListening ? "waveform.slash" : "waveform",
            role: .normal
          ) {
            Task { await viewModel.toggleSpeechCapture() }
          }
        }

        actionButton(
          "Send Command",
          icon: "paperplane.fill",
          role: viewModel.selectedActionIsDangerous ? .danger : .primary,
          loading: viewModel.isSendingCommand,
          disabled: !viewModel.selectedActionSupported
        ) {
          if viewModel.selectedActionIsDangerous {
            showDangerousSendConfirmation = true
          } else {
            Task { await viewModel.sendCommand() }
          }
        }

        Text(viewModel.speechInfoText)
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(viewModel.speechSupported ? Color.white.opacity(0.70) : CordycepsTheme.errorText)
      }
    }
  }

  private var adminCommandCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Admin Command")

        dangerZone("Runs arbitrary shell commands on an admin-capable agent. Use only for controlled maintenance.")

        TextField("Admin Target (a1)", text: $viewModel.adminTargetInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.adminTargetInput) { _ in
            viewModel.persistAdminSettings()
          }

        Picker("Shell", selection: $viewModel.adminShellInput) {
          Text("Command Prompt").tag("cmd")
          Text("PowerShell").tag("powershell")
        }
        .pickerStyle(.segmented)
        .tint(CordycepsTheme.capsuleAmber)
        .onChange(of: viewModel.adminShellInput) { _ in
          viewModel.persistAdminSettings()
        }

        TextField("Command (whoami)", text: $viewModel.adminCommandInput, axis: .vertical)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .lineLimit(2 ... 6)
          .cordycepsFieldStyle()

        actionButton("Run Admin Command", icon: "terminal.fill", role: .warning, loading: viewModel.isSendingAdminCommand) {
          Task { await viewModel.sendAdminCommand() }
        }
      }
    }
  }

  private var securityCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Security Controls")

        Text("Run lockdown, quarantine, and kill-switch actions from this dedicated control section.")
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.72))

        dangerZone("These controls can block connectivity and isolate a machine immediately. Confirm the target device before applying.")

        TextField("Security target device ID (t1)", text: $viewModel.securityDeviceInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.securityDeviceInput) { _ in
            viewModel.persistSecuritySettings()
          }

        TextField("Reason (optional)", text: $viewModel.securityReasonInput)
          .textInputAutocapitalization(.sentences)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.securityReasonInput) { _ in
            viewModel.persistSecuritySettings()
          }

        TextField("Lockdown minutes (1-240)", text: $viewModel.securityLockdownMinutesInput)
          .keyboardType(.numberPad)
          .cordycepsFieldStyle()
          .onChange(of: viewModel.securityLockdownMinutesInput) { _ in
            viewModel.persistSecuritySettings()
          }

        HStack(spacing: 8) {
          actionButton("Trigger Lockdown", icon: "lock.shield.fill", role: .danger, loading: viewModel.isApplyingSecurityControl) {
            Task { await viewModel.triggerLockdown() }
          }
          actionButton("Quarantine", icon: "shield.lefthalf.filled", role: .warning, loading: viewModel.isApplyingSecurityControl) {
            Task { await viewModel.quarantineDevice() }
          }
        }

        HStack(spacing: 8) {
          actionButton("Lift Quarantine", icon: "shield.lefthalf.filled.slash", role: .normal, loading: viewModel.isApplyingSecurityControl) {
            Task { await viewModel.unquarantineDevice() }
          }
          actionButton("Enable Kill-Switch", icon: "bolt.trianglebadge.exclamationmark.fill", role: .danger, loading: viewModel.isApplyingSecurityControl) {
            Task { await viewModel.setKillSwitch(true) }
          }
        }

        actionButton("Disable Kill-Switch", icon: "bolt.slash.fill", role: .normal, loading: viewModel.isApplyingSecurityControl) {
          Task { await viewModel.setKillSwitch(false) }
        }
      }
    }
  }

  private var updateCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Agent Update")

        Text("Push a verified agent package to one target or all online devices.")
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.72))

        dangerZone("Updates can restart agents and cut off remote control if package metadata is wrong.")

        TextField("Target (m1 or all)", text: $viewModel.updateTargetInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.updateTargetInput) { _ in
            viewModel.persistUpdateSettings()
          }

        TextField("Version (0.2.0)", text: $viewModel.updateVersionInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.updateVersionInput) { _ in
            viewModel.persistUpdateSettings()
          }

        TextField("Package URL (https://...)", text: $viewModel.updateURLInput)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.updateURLInput) { _ in
            viewModel.persistUpdateSettings()
          }

        TextField("SHA256 (optional 64 hex chars)", text: $viewModel.updateShaInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.updateShaInput) { _ in
            viewModel.persistUpdateSettings()
          }

        TextField("Size bytes (optional)", text: $viewModel.updateSizeInput)
          .keyboardType(.numberPad)
          .cordycepsFieldStyle()
          .onChange(of: viewModel.updateSizeInput) { _ in
            viewModel.persistUpdateSettings()
          }

        TextField("Signature Key ID (optional)", text: $viewModel.updateSignatureKeyIDInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()
          .onChange(of: viewModel.updateSignatureKeyIDInput) { _ in
            viewModel.persistUpdateSettings()
          }

        TextField("Detached Signature (base64, optional)", text: $viewModel.updateSignatureInput, axis: .vertical)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .lineLimit(2 ... 4)
          .cordycepsFieldStyle()
          .onChange(of: viewModel.updateSignatureInput) { _ in
            viewModel.persistUpdateSettings()
          }

        Toggle(isOn: $viewModel.updateUsePrivilegedHelperInput) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Use Privileged Helper Split")
              .font(.system(.footnote, design: .rounded).weight(.semibold))
              .foregroundStyle(.white)
            Text("Optional. May trigger UAC prompt on supported targets.")
              .font(.system(.caption2, design: .rounded))
              .foregroundStyle(Color.white.opacity(0.68))
          }
        }
        .tint(CordycepsTheme.capsuleAmber)
        .onChange(of: viewModel.updateUsePrivilegedHelperInput) { _ in
          viewModel.persistUpdateSettings()
        }

        Toggle(isOn: $viewModel.updateQueueOfflineInput) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Queue If Target Is Offline")
              .font(.system(.footnote, design: .rounded).weight(.semibold))
              .foregroundStyle(.white)
            Text("Only applies to one device. The server stores the update until that agent reconnects.")
              .font(.system(.caption2, design: .rounded))
              .foregroundStyle(Color.white.opacity(0.68))
          }
        }
        .tint(CordycepsTheme.primaryButton)
        .onChange(of: viewModel.updateQueueOfflineInput) { _ in
          viewModel.persistUpdateSettings()
        }

        actionButton("Review & Push", icon: "arrow.up.circle.fill", role: .warning, loading: viewModel.isPushingUpdate) {
          showUpdateConfirmation = true
        }
      }
    }
  }

  private var historyCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("History")

        TextField("Filter by device ID (optional)", text: $viewModel.historyDeviceFilterInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()

        HStack(spacing: 8) {
          actionButton("Load", icon: "clock.arrow.circlepath", role: .normal, loading: viewModel.isLoadingHistory) {
            Task { await viewModel.loadCommandLogs(silent: false, append: false) }
          }
          actionButton("More", icon: "ellipsis.circle.fill", role: .normal, loading: viewModel.isLoadingHistory) {
            Task { await viewModel.loadCommandLogs(silent: false, append: true) }
          }
        }

        if viewModel.commandLogs.isEmpty {
          emptyState("No command history loaded.")
        } else {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.commandLogs.prefix(24)), id: \.id) { entry in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text("\(entry.device_id) • \(entry.parsed_type)")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                  Spacer(minLength: 0)
                  Text(entry.status.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.status == "ok" ? CordycepsTheme.myceliumGlow : CordycepsTheme.errorText)
                }

                Text("\(entry.parsed_target) • \(entry.request_id)")
                  .font(.system(.caption2, design: .rounded))
                  .foregroundStyle(Color.white.opacity(0.66))

                Text(entry.result_message ?? entry.raw_text)
                  .font(.system(.caption2, design: .rounded))
                  .foregroundStyle(Color.white.opacity(0.8))
                  .lineLimit(2)

                Text(toLocal(entry.created_at))
                  .font(.system(.caption2, design: .rounded))
                  .foregroundStyle(Color.white.opacity(0.55))
              }
              .padding(10)
              .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                  .fill(CordycepsTheme.cardFill)
                  .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                      .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
                  )
              )
            }
          }
        }
      }
    }
  }

  private var apiKeysCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("API Keys")

        Text("Manage scoped tokens for additional users. Requires admin scope.")
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.72))

        TextField("Key name", text: $viewModel.apiKeyNameInput)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()

        TextField("Scopes (comma-separated)", text: $viewModel.apiKeyScopesInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .cordycepsFieldStyle()

        HStack(spacing: 8) {
          actionButton("Create", icon: "key.fill", role: .warning, loading: viewModel.isCreatingAPIKey) {
            Task { await viewModel.createAPIKey() }
          }
          actionButton("Load", icon: "arrow.clockwise.circle.fill", role: .normal, loading: viewModel.isLoadingAPIKeys) {
            Task { await viewModel.loadAPIKeys() }
          }
        }

        if !viewModel.generatedAPIKey.isEmpty {
          Text("Generated key (shown once)")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(CordycepsTheme.capsuleAmber.opacity(0.95))

          Text(viewModel.generatedAPIKey)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(10)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .overlay(
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
                )
            )
        }

        if viewModel.apiKeys.isEmpty {
          emptyState("No API keys loaded.")
        } else {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.apiKeys.prefix(12)), id: \.id) { key in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(key.name)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                  Spacer(minLength: 0)
                  Text(key.status.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(key.status == "active" ? CordycepsTheme.myceliumGlow : CordycepsTheme.errorText)
                }

                Text("\(key.key_id) • \(key.scopes.joined(separator: ", "))")
                  .font(.system(.caption2, design: .rounded))
                  .foregroundStyle(Color.white.opacity(0.66))
                  .lineLimit(2)

                if key.status == "active" {
                  HStack(spacing: 8) {
                    actionButton(
                      "Rotate",
                      icon: "arrow.triangle.2.circlepath.circle.fill",
                      role: .warning,
                      loading: viewModel.isRotatingAPIKey(key.key_id)
                    ) {
                      Task { await viewModel.rotateAPIKey(key.key_id) }
                    }
                    actionButton("Revoke", icon: "xmark.circle.fill", role: .danger) {
                      Task { await viewModel.revokeAPIKey(key.key_id) }
                    }
                  }
                }
              }
              .padding(10)
              .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                  .fill(CordycepsTheme.cardFill)
                  .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                      .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
                  )
              )
            }
          }
        }
      }
    }
  }

  private var tokenRotationCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Token Rotation")

        Text("Owner-only rotation for owner/bootstrap tokens with optional grace window.")
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.72))

        TextField("Owner grace seconds (0-3600)", text: $viewModel.ownerGraceSecondsInput)
          .keyboardType(.numberPad)
          .cordycepsFieldStyle()
          .onChange(of: viewModel.ownerGraceSecondsInput) { _ in
            viewModel.persistOwnerGraceSeconds()
          }

        HStack(spacing: 8) {
          actionButton("Rotate Owner", icon: "key.fill", role: .warning, loading: viewModel.isRotatingTokens) {
            Task { await viewModel.rotateOwnerToken() }
          }
          actionButton("Rotate Owner + Bootstrap", icon: "arrow.triangle.2.circlepath", role: .warning, loading: viewModel.isRotatingTokens) {
            Task { await viewModel.rotateOwnerAndBootstrapTokens() }
          }
        }

        actionButton("Rotate Bootstrap", icon: "arrow.clockwise.shield", role: .normal, loading: viewModel.isRotatingTokens) {
          Task { await viewModel.rotateBootstrapToken() }
        }

        if !viewModel.rotatedTokenPayload.isEmpty {
          Text("Latest Rotation Payload")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(CordycepsTheme.capsuleAmber.opacity(0.95))

          Text(String(viewModel.rotatedTokenPayload.prefix(5000)))
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(18)
            .padding(10)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .overlay(
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
                )
            )
        }
      }
    }
  }

  private var resultCard: some View {
    CordycepsCard {
      VStack(alignment: .leading, spacing: 12) {
        sectionHeader("Result")

        VStack(spacing: 8) {
          resultRow("Status", value: viewModel.resultStatus, emphasize: viewModel.resultIsError)
          resultRow("Request ID", value: viewModel.resultRequestId)
          resultRow("Latency", value: viewModel.resultLatency)
          resultRow("Message", value: viewModel.resultMessage, multiline: true)
        }

        Text(String(viewModel.responseText.prefix(8000)))
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(CordycepsTheme.resultText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .lineLimit(26)
          .padding(12)
          .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Color.black.opacity(0.32))
              .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
              )
          )

        actionButton("Copy Result JSON", icon: "doc.on.doc.fill", role: .normal) {
          viewModel.copyResponseToClipboard()
        }
      }
    }
  }

  private var statusBadge: some View {
    let label: String
    let tint: Color

    switch viewModel.connectionState {
    case .connected:
      label = "Connected"
      tint = CordycepsTheme.myceliumGlow
    case .retrying:
      label = "Retrying"
      tint = CordycepsTheme.capsuleAmber
    case .disconnected:
      label = "Disconnected"
      tint = CordycepsTheme.errorDot
    }

    return Text(label.uppercased())
      .font(.system(size: 11, weight: .bold, design: .rounded))
      .tracking(0.7)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        Capsule()
          .fill(tint.opacity(0.24))
          .overlay(Capsule().stroke(tint.opacity(0.86), lineWidth: 1))
      )
      .foregroundStyle(tint)
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(.title3, design: .rounded).weight(.semibold))
      .foregroundStyle(.white)
  }

  private func toLocal(_ iso: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: iso) else {
      return iso
    }
    return DateFormatter.cordyceps.string(from: date)
  }

  private func emptyState(_ text: String) -> some View {
    Text(text)
      .font(.system(.footnote, design: .rounded))
      .foregroundStyle(Color.white.opacity(0.70))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(CordycepsTheme.cardFill)
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
          )
      )
  }

  private func dangerZone(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(CordycepsTheme.capsuleAmber)

      Text(text)
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(CordycepsTheme.errorText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(CordycepsTheme.dangerFill)
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(CordycepsTheme.dangerStroke, lineWidth: 1)
        )
    )
  }

  private func inspectorInfoRow(_ key: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(key)
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.68))
      Text(value.isEmpty ? "n/a" : value)
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.90))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(CordycepsTheme.cardFill)
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
        )
    )
  }

  private func resultRow(_ key: String, value: String, emphasize: Bool = false, multiline: Bool = false) -> some View {
    HStack(alignment: multiline ? .top : .center, spacing: 10) {
      Text(key)
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.70))
        .frame(width: 92, alignment: .leading)

      Text(value)
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .foregroundStyle(emphasize ? CordycepsTheme.errorText : CordycepsTheme.myceliumGlow)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(CordycepsTheme.cardFill)
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
        )
    )
  }

  private func actionButton(
    _ title: String,
    icon: String,
    role: ButtonRoleStyle,
    loading: Bool = false,
    disabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if loading {
          ProgressView()
            .tint(role.foreground)
            .scaleEffect(0.9)
        } else {
          Image(systemName: icon)
        }
        Text(title)
          .lineLimit(1)
      }
      .font(.system(.footnote, design: .rounded).weight(.semibold))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .padding(.horizontal, 8)
    }
    .disabled(loading || disabled)
    .foregroundStyle(role.foreground)
    .background(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .fill(role.background)
        .overlay(
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(role.border, lineWidth: 1)
        )
    )
  }
}

private enum CordycepsTheme {
  static let soilBlack = Color(red: 0.04, green: 0.04, blue: 0.03)
  static let soilDeep = Color(red: 0.09, green: 0.08, blue: 0.05)
  static let forestNight = Color(red: 0.09, green: 0.14, blue: 0.09)

  static let myceliumGlow = Color(red: 0.62, green: 0.90, blue: 0.66)
  static let capsuleAmber = Color(red: 0.95, green: 0.68, blue: 0.32)
  static let sporePurple = Color(red: 0.52, green: 0.42, blue: 0.60)

  static let primaryButton = Color(red: 0.26, green: 0.64, blue: 0.35)
  static let buttonTextPrimary = Color(red: 0.05, green: 0.20, blue: 0.09)
  static let offlineButton = Color(red: 0.28, green: 0.31, blue: 0.27)

  static let cardFill = Color.white.opacity(0.07)
  static let strokeSoft = Color.white.opacity(0.16)

  static let dangerFill = Color(red: 0.40, green: 0.14, blue: 0.10).opacity(0.30)
  static let dangerStroke = Color(red: 0.92, green: 0.52, blue: 0.46).opacity(0.56)
  static let errorText = Color(red: 1.0, green: 0.78, blue: 0.74)
  static let errorDot = Color(red: 0.92, green: 0.47, blue: 0.46)

  static let resultText = Color(red: 0.90, green: 0.95, blue: 0.91)
}

private struct CordycepsCard<Content: View>: View {
  let tint: LinearGradient?
  @ViewBuilder var content: Content

  init(tint: LinearGradient? = nil, @ViewBuilder content: () -> Content) {
    self.tint = tint
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(CordycepsTheme.cardFill)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
        )
        .overlay {
          if let tint {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(tint)
          }
        }
    )
    .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 10)
  }
}

private enum ButtonRoleStyle {
  case normal
  case primary
  case warning
  case danger

  var background: Color {
    switch self {
    case .normal:
      return CordycepsTheme.cardFill
    case .primary:
      return CordycepsTheme.primaryButton.opacity(0.95)
    case .warning:
      return CordycepsTheme.capsuleAmber.opacity(0.95)
    case .danger:
      return Color(red: 0.76, green: 0.28, blue: 0.25).opacity(0.95)
    }
  }

  var foreground: Color {
    switch self {
    case .normal:
      return .white
    case .primary:
      return CordycepsTheme.buttonTextPrimary
    case .warning:
      return Color(red: 0.29, green: 0.17, blue: 0.06)
    case .danger:
      return Color(red: 0.25, green: 0.06, blue: 0.05)
    }
  }

  var border: Color {
    switch self {
    case .normal:
      return CordycepsTheme.strokeSoft
    case .primary:
      return CordycepsTheme.myceliumGlow.opacity(0.9)
    case .warning:
      return CordycepsTheme.capsuleAmber
    case .danger:
      return Color(red: 0.95, green: 0.67, blue: 0.62)
    }
  }
}

private extension View {
  func cordycepsFieldStyle() -> some View {
    self
      .font(.system(.footnote, design: .rounded).weight(.medium))
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.black.opacity(0.30))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(CordycepsTheme.strokeSoft, lineWidth: 1)
          )
      )
      .foregroundStyle(Color.white)
  }
}

#Preview {
  ContentView()
}
