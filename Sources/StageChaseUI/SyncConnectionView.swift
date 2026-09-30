import SwiftUI

struct SyncConnectionView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Form {
      #if os(macOS)
        macConnection
      #else
        phoneConnection
      #endif
      SyncNetworkEventSection(
        events: networkEvents, logError: eventLogError, clear: clearEvents)
    }
    .formStyle(.grouped)
    #if os(macOS)
      .frame(minWidth: 640, minHeight: 680)
    #endif
  }

  #if os(macOS)
    @ViewBuilder private var macConnection: some View {
      Section("Mac listener") {
        if let server = model.syncServer, server.status != "Off" {
          LabeledContent("Listener", value: server.status)
          LabeledContent("Active requests", value: "\(server.activeConnectionCount)")
          if let address = server.address {
            LabeledContent("Address", value: "stagechase://\(address)")
              .textSelection(.enabled)
          } else {
            Text("No local IPv4 address is available. Check the Mac’s Wi-Fi connection.")
              .foregroundStyle(.orange)
          }
          if let code = server.pairingCode {
            LabeledContent("Temporary pairing code", value: code).textSelection(.enabled)
            Text(
              "Anyone with this code can pair for five minutes. Share it only with the intended phone."
            )
            .stageFont(.caption).foregroundStyle(.secondary)
          } else {
            Text(
              "The temporary code was used or expired. Generate a new code to pair another phone."
            )
            .stageFont(.caption).foregroundStyle(.secondary)
          }
          Button("Generate a new pairing code") { server.renewPairingCode() }
          if let phone = server.pendingDeviceName {
            LabeledContent("Paired phone", value: phone)
          }
          LabeledContent("Last request result", value: server.lastRequestResult)
          if let date = server.lastPhoneContactAt {
            LabeledContent(
              "Last phone contact", value: date.formatted(date: .abbreviated, time: .standard))
          }
          if let address = server.lastPhoneAddress {
            LabeledContent("Phone address", value: address)
          }
          if let error = server.error {
            Text(error).foregroundStyle(.red).stageFont(.callout)
          }
          if let error = server.eventLogError {
            Text(error).foregroundStyle(.orange).stageFont(.caption)
          }
          if server.status == "Unavailable" {
            Button("Retry listener") { Task { await model.startLocalSync() } }
          }
          Button("Disable local sync", role: .destructive) { model.stopLocalSync() }
          Button("Revoke all paired phones", role: .destructive) { server.revokeAllPhones() }
        } else {
          Text(
            "The Mac app must stay open and local sync must be enabled for the phone to connect."
          )
          .foregroundStyle(.secondary)
          if let error = model.syncServer?.error {
            Text(error).foregroundStyle(.red).stageFont(.callout)
          }
          Button("Enable local Wi-Fi sync") { Task { await model.startLocalSync() } }
            .buttonStyle(.borderedProminent)
        }
      }
    }

    private var networkEvents: [SyncNetworkEvent] { model.syncServer?.networkEvents ?? [] }
    private var eventLogError: String? { model.syncServer?.eventLogError }

    private func clearEvents() { model.syncServer?.clearNetworkEvents() }
  #else
    @ViewBuilder private var phoneConnection: some View {
      @Bindable var sync = model.syncClient
      Section("Sync behavior") {
        Toggle("Automatic syncing", isOn: $sync.automaticSyncEnabled)
        Text(
          sync.automaticSyncEnabled
            ? "Refreshes while the app is open and sends phone edits automatically."
            : "Sync only with Sync Now or pull to refresh. Phone edits stay queued until then."
        )
        .stageFont(.caption).foregroundStyle(.secondary)
      }
      if sync.isPaired {
        Section("Connection to Mac") {
          LabeledContent("State", value: sync.status)
          TextField("Mac address", text: $sync.endpoint)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
          if sync.hasUnsavedEndpoint {
            Button("Save Mac address") { sync.saveEndpoint() }
              .buttonStyle(.borderedProminent)
            Text("Pending local changes will be kept when the address is changed.")
              .stageFont(.caption).foregroundStyle(.secondary)
          }
          if sync.isSyncing {
            ProgressView(sync.status)
          }
          Button {
            Task { await model.refreshFromMac(manual: true) }
          } label: {
            if sync.isSyncing {
              Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
            } else {
              Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(sync.isSyncing || sync.hasUnsavedEndpoint)
          Text(
            "Sync uses a short connection for each request; the state above reports the latest check, not an always-open socket."
          )
          .stageFont(.caption).foregroundStyle(.secondary)
          LabeledContent("Pending local changes", value: "\(sync.outbox.count)")
          if let date = sync.lastAttemptAt {
            LabeledContent(
              "Last attempt", value: date.formatted(date: .abbreviated, time: .standard))
          }
          if let date = sync.lastSuccessfulSync {
            LabeledContent(
              "Last successful sync", value: date.formatted(date: .abbreviated, time: .standard))
          } else if let date = sync.lastCompletedSyncAt {
            LabeledContent(
              "Last successful sync", value: date.formatted(date: .abbreviated, time: .standard))
          }
          LabeledContent("Result", value: sync.lastResultMessage)
          if let error = sync.error {
            Text(error).foregroundStyle(.red).stageFont(.callout)
          }
          if let error = sync.eventLogError {
            Text(error).foregroundStyle(.orange).stageFont(.caption)
          }
          Button("Unpair this phone", role: .destructive) {
            Task { await model.unpairPhone() }
          }
          .disabled(!sync.outbox.isEmpty || sync.isSyncing)
        }
      } else {
        Section("Pair with Mac") {
          TextField("Mac address (stagechase://host:47928)", text: $sync.endpoint)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
          TextField("Temporary pairing code", text: $sync.pairingCode)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
          TextField("This phone’s name", text: $sync.deviceName)
          if sync.pairingInProgress {
            ProgressView(sync.status)
          } else {
            Button("Request pairing") { Task { await model.pairPhone() } }
              .buttonStyle(.borderedProminent)
          }
          Text(
            "The temporary code pairs this phone automatically. Keep both apps open on the same Wi-Fi network."
          )
          .stageFont(.caption).foregroundStyle(.secondary)
          if let error = sync.error {
            Text(error).foregroundStyle(.red).stageFont(.callout)
          }
          if !sync.outbox.isEmpty {
            Text("Queued changes from the prior pairing remain preserved on this phone.")
              .foregroundStyle(.orange).stageFont(.caption)
          }
        }
      }
    }

    private var networkEvents: [SyncNetworkEvent] { model.syncClient.networkEvents }
    private var eventLogError: String? { model.syncClient.eventLogError }

    private func clearEvents() { model.syncClient.clearNetworkEvents() }
  #endif
}

private struct SyncNetworkEventSection: View {
  let events: [SyncNetworkEvent]
  let logError: String?
  let clear: () -> Void

  var body: some View {
    Section {
      if let logError {
        Text(logError).foregroundStyle(.orange).stageFont(.caption)
      }
      if events.isEmpty {
        Text("No connection events yet.").foregroundStyle(.secondary)
      } else {
        ForEach(events) { event in
          VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
              Text(event.operation).stageFont(.callout, weight: .semibold)
              Spacer()
              Text(event.date.formatted(date: .abbreviated, time: .standard))
                .stageFont(.caption2).foregroundStyle(.secondary)
            }
            Text("\(event.direction) · \(event.outcome) · \(event.byteSummary)")
              .stageFont(.caption).foregroundStyle(.secondary)
            if let remoteAddress = event.remoteAddress {
              Text(remoteAddress).stageFont(.caption2).foregroundStyle(.secondary)
            }
            Text(event.detail).stageFont(.caption)
            if let elapsed = event.elapsedMilliseconds {
              Text("Elapsed: \(elapsed) ms").stageFont(.caption2).foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 4)
        }
        Button("Clear connection log", role: .destructive, action: clear)
      }
    } header: {
      Text("Recent network exchanges")
    } footer: {
      Text(
        "Shows framed message byte counts and outcomes only, not lower-level TCP packet sizes. Message contents, task text, and credentials are never recorded. Up to 200 events are kept on this device."
      )
    }
  }
}

extension SyncNetworkEvent {
  fileprivate var byteSummary: String {
    let response = responseBytes.map { "\($0) B response" } ?? "no response"
    return "\(requestBytes) B request · \(response)"
  }
}
