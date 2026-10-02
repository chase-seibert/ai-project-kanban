import CryptoKit
import Darwin
import Foundation
import Network
import Observation

private struct SavedDevice: Codable, Sendable {
  var id: UUID
  var name: String
  var key: Data
}

private struct SavedDeviceRegistry: Codable, Sendable {
  var libraryID: UUID
  var devices: [SavedDevice]
}

private struct StoredGitReceipt: Codable, Sendable {
  var digest: String
  var response: SyncDirectResponse
}

private struct PendingPhone: Sendable {
  var offer: SyncPairingOffer
  var status: SyncPairingStatus
}

/// Mac-owned listener. All command effects pass through LibraryRepository; polling is read-only.
@MainActor @Observable final class SyncServer {
  static let port: NWEndpoint.Port = 47_928
  private static let keychainService = "com.cseibert.StageChase.sync"
  private let repository: LibraryRepository
  private var listener: NWListener?
  private var pathMonitor: NWPathMonitor?
  private var isStarting = false
  private var startupGeneration = UUID()
  private let instanceID = UUID()
  private var loopbackProbeID: UUID?
  private var loopbackConnection: NWConnection?
  private var pairingKey = SyncCrypto.randomSecret()
  private var pairingExpiresAt = Date().addingTimeInterval(5 * 60)
  private var devices: [UUID: SavedDevice] = [:]
  private var gitReceipts: [UUID: StoredGitReceipt] = [:]
  private let gitService = GitService()
  private var pending: PendingPhone?
  private var activeConnections = 0
  private var pairingAttempts: [Date] = []
  var status = "Off"
  var portRegistrationStatus = "Not verified"
  var address: String?
  var pairingCode: String?
  var pendingDeviceName: String?
  var error: String?
  var lastPhoneContactAt: Date?
  var lastPhoneAddress: String?
  var lastRequestResult = "No phone request received yet."
  var networkEvents: [SyncNetworkEvent] = []
  var eventLogError: String?
  var onLibraryChanged: ((Library) -> Void)?
  var onPhoneCodexAction: ((UUID, Int, SyncPhoneCodexAction) async throws -> String)?
  var onPhoneModelCatalogRequest:
    (() async throws -> (CodexModelConfiguration, [CodexModelOption]))?
  private let networkEventsURL: URL
  private let gitReceiptsURL: URL
  var activeConnectionCount: Int { activeConnections }

  init(repository: LibraryRepository) {
    self.repository = repository
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!.appendingPathComponent("StageChase", isDirectory: true)
    networkEventsURL = base.appendingPathComponent("MacSyncNetworkEvents-v1.json")
    gitReceiptsURL = base.appendingPathComponent("PhoneGitReceipts-v1.json")
    if let data = try? Data(contentsOf: gitReceiptsURL),
      let receipts = try? JSONDecoder.syncDecoder.decode([UUID: StoredGitReceipt].self, from: data)
    {
      gitReceipts = receipts
    }
    do {
      networkEvents = try SyncNetworkEventJournal.load(from: networkEventsURL)
      let lastPhoneEvent = networkEvents.first { $0.direction == "Phone → Mac" }
      lastPhoneContactAt = lastPhoneEvent?.date
      lastPhoneAddress = lastPhoneEvent?.remoteAddress
      lastRequestResult =
        lastPhoneEvent.map {
          "\($0.operation) · \($0.outcome) · \($0.detail)"
        } ?? lastRequestResult
    } catch let caught {
      eventLogError = "Previous connection log could not be read: \(caught.localizedDescription)"
    }
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
  }

  static func hasSavedPhonePairing() -> Bool {
    guard let data = try? KeychainVault.read(service: keychainService, account: "devices"),
      let registry = try? JSONDecoder().decode(SavedDeviceRegistry.self, from: data)
    else { return false }
    return !registry.devices.isEmpty
  }

  func start() async {
    guard listener == nil, !isStarting else { return }
    isStarting = true
    let generation = UUID()
    startupGeneration = generation
    defer {
      if startupGeneration == generation { isStarting = false }
    }
    do {
      let state = try await repository.syncStateSnapshot()
      guard startupGeneration == generation else { return }
      try loadDevices(for: state.libraryID)
      pairingKey = SyncCrypto.randomSecret()
      renewPairingCode()
      let listener = try NWListener(using: .tcp, on: Self.port)
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor [weak self] in self?.accept(connection) }
      }
      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor [weak self] in
          guard let self, self.startupGeneration == generation else { return }
          switch state {
          case .ready:
            self.status = "Available on this Wi-Fi network"
            self.address = Self.localAddress().map { "\($0):\(Self.port.rawValue)" }
            self.error = nil
            self.verifyPortRegistration()
            self.recordNetworkEvent(
              SyncNetworkEvent(
                direction: "Mac", operation: "Listener ready", requestBytes: 0,
                responseBytes: nil, outcome: "Listening",
                detail: self.address ?? "Listening, but no local IPv4 address was found.",
                elapsedMilliseconds: nil))
          case .waiting(let failure):
            self.status = "Waiting for network"
            self.error = failure.localizedDescription
            self.verifyPortRegistration()
            self.recordNetworkEvent(
              SyncNetworkEvent(
                direction: "Mac", operation: "Listener state", requestBytes: 0,
                responseBytes: nil, outcome: "Waiting", detail: failure.localizedDescription,
                elapsedMilliseconds: nil))
          case .failed(let failure):
            let detail = Self.listenerErrorMessage(failure)
            self.status = "Unavailable"
            self.error = detail
            self.verifyPortRegistration()
            self.recordNetworkEvent(
              SyncNetworkEvent(
                direction: "Mac", operation: "Listener failed", requestBytes: 0,
                responseBytes: nil, outcome: "Failed", detail: detail,
                elapsedMilliseconds: nil))
            self.listener?.cancel()
            self.listener = nil
          case .cancelled:
            if self.status != "Unavailable" {
              self.status = "Off"
              self.address = nil
              self.portRegistrationStatus = "Not verified"
            }
          default: break
          }
        }
      }
      self.listener = listener
      status = "Starting"
      listener.start(queue: DispatchQueue(label: "com.cseibert.StageChase.sync-listener"))
      let monitor = NWPathMonitor()
      monitor.pathUpdateHandler = { [weak self] path in
        Task { @MainActor [weak self] in
          guard let self, self.listener != nil else { return }
          guard path.status == .satisfied else {
            self.status = "Waiting for network"
            self.address = nil
            return
          }
          let refreshedAddress = Self.localAddress().map { "\($0):\(Self.port.rawValue)" }
          if refreshedAddress != self.address {
            self.address = refreshedAddress
            self.recordNetworkEvent(
              SyncNetworkEvent(
                direction: "Mac", operation: "Network address", requestBytes: 0,
                responseBytes: nil, outcome: refreshedAddress == nil ? "Unavailable" : "Updated",
                detail: refreshedAddress ?? "No local IPv4 address found.", elapsedMilliseconds: nil
              ))
          }
          if self.status == "Waiting for network" {
            self.status = "Available on this Wi-Fi network"
          }
        }
      }
      pathMonitor = monitor
      monitor.start(queue: DispatchQueue(label: "com.cseibert.StageChase.sync-path"))
    } catch {
      guard startupGeneration == generation else { return }
      let detail = Self.listenerErrorMessage(error)
      self.error = detail
      status = "Unavailable"
      recordNetworkEvent(
        SyncNetworkEvent(
          direction: "Mac", operation: "Listener failed", requestBytes: 0,
          responseBytes: nil, outcome: "Failed", detail: detail, elapsedMilliseconds: nil))
      verifyPortRegistration()
    }
  }

  func stop() {
    startupGeneration = UUID()
    loopbackProbeID = nil
    loopbackConnection?.cancel()
    loopbackConnection = nil
    isStarting = false
    recordNetworkEvent(
      SyncNetworkEvent(
        direction: "Mac", operation: "Listener stopped", requestBytes: 0, responseBytes: nil,
        outcome: "Disabled", detail: "Local sync was disabled by the Mac user.",
        elapsedMilliseconds: nil))
    listener?.cancel()
    listener = nil
    pathMonitor?.cancel()
    pathMonitor = nil
    pairingCode = nil
    pending = nil
    pendingDeviceName = nil
    address = nil
    status = "Off"
    portRegistrationStatus = "Not verified"
  }

  private static func listenerErrorMessage(_ error: Error) -> String {
    if let networkError = error as? NWError,
      case .posix(let code) = networkError,
      code == .EADDRINUSE
    {
      return
        "Port \(Self.port.rawValue) is already in use, usually by another StageChase instance. Quit the other instance, then retry."
    }
    return error.localizedDescription
  }

  func renewPairingCode() {
    pairingKey = SyncCrypto.randomSecret()
    pairingCode = pairingKey.base64EncodedString()
    pairingExpiresAt = Date().addingTimeInterval(5 * 60)
    pending = nil
    pendingDeviceName = nil
    pairingAttempts = []
  }

  func revokeAllPhones() {
    do {
      devices.removeAll()
      let state = try loadRegistry().libraryID
      try saveDevices(libraryID: state, devices: [])
      pending = nil
      pendingDeviceName = nil
    } catch let caught { self.error = caught.localizedDescription }
  }

  private func accept(_ connection: NWConnection) {
    guard activeConnections < 8 else {
      connection.cancel()
      return
    }
    activeConnections += 1
    let connectionQueue = DispatchQueue(label: "com.cseibert.StageChase.sync-connection")
    let server = self
    let startedAt = Date()
    connection.stateUpdateHandler = { state in
      if case .ready = state {
        Self.receiveFrame(connection, buffer: Data()) { result in
          Task { @MainActor in
            let reply: SyncWireResponse
            var operation = "Read request"
            var requestBytes = 0
            var isLoopbackProbe = false
            var failureDetail: String?
            do {
              switch result {
              case .success(let data):
                requestBytes = data.count
                guard data.count <= SyncProtocol.maximumMessageBytes else {
                  throw BoardError.invalid("Request too large.")
                }
                let request = try SyncFrame.decode(data, as: SyncWireRequest.self)
                operation = Self.operationName(for: request)
                if case .loopbackProbe = request { isLoopbackProbe = true }
                reply = try await server.handle(request)
              case .failure(let error):
                failureDetail = error.localizedDescription
                reply = .error("Invalid synchronization request.")
              }
            } catch let caught {
              failureDetail = caught.localizedDescription
              reply = .error("Synchronization request could not be processed.")
            }
            let bytes = (try? SyncFrame.encode(reply)) ?? Data()
            let outcome: String
            let detail: String
            switch reply {
            case .error(let message):
              outcome = "Rejected"
              detail = failureDetail ?? message
            case .loopbackProbe(let instanceID, _):
              outcome = instanceID == server.instanceID ? "Verified" : "Instance mismatch"
              detail = "Loopback probe response sent by StageChase instance \(instanceID)."
            case .pairPending:
              outcome = "Paired"
              detail = "Temporary code accepted; phone credential issued."
            case .pairStatus:
              outcome = "Pair status returned"
              detail = "Pairing response sent."
            case .authenticated:
              outcome = "Completed"
              detail = server.lastRequestResult
            }
            if !isLoopbackProbe {
              server.lastPhoneContactAt = .now
              server.lastPhoneAddress = String(describing: connection.endpoint)
            }
            server.lastRequestResult = "\(operation) · \(outcome) · \(detail)"
            let remoteAddress = String(describing: connection.endpoint)
            server.recordNetworkEvent(
              SyncNetworkEvent(
                direction: isLoopbackProbe ? "Mac loopback" : "Phone → Mac",
                remoteAddress: remoteAddress,
                operation: operation, requestBytes: requestBytes,
                responseBytes: bytes.isEmpty ? nil : bytes.count, outcome: outcome,
                detail: detail,
                elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)))
            if bytes.isEmpty {
              connection.cancel()
            } else {
              connection.send(
                content: bytes, completion: .contentProcessed { _ in connection.cancel() })
            }
            server.activeConnections = max(0, server.activeConnections - 1)
          }
        }
      }
    }
    connection.start(queue: connectionQueue)
  }

  private func handle(_ request: SyncWireRequest) async throws -> SyncWireResponse {
    if case .loopbackProbe(let nonce) = request {
      return .loopbackProbe(instanceID: instanceID, nonce: nonce)
    }
    let currentLibrary = try await repository.syncStateSnapshot()
    if devicesLibraryID != currentLibrary.libraryID {
      try loadDevices(for: currentLibrary.libraryID)
    }
    switch request {
    case .pairStart(let sealed):
      guard Date() < pairingExpiresAt, pairingCode != nil else {
        return .error("Pairing code expired.")
      }
      pairingAttempts = pairingAttempts.filter { Date().timeIntervalSince($0) < 60 }
      guard pairingAttempts.count < 5 else {
        return .error("Too many pairing attempts. Generate a new code and try later.")
      }
      pairingAttempts.append(.now)
      let offer = try SyncCrypto.open(sealed, key: pairingKey, as: SyncPairingOffer.self)
      guard offer.deviceKey.count == 32, offer.requestID != UUID.zero,
        devices[offer.deviceID] == nil, pending == nil
      else { return .error("Pairing request is invalid or already handled.") }
      let saved = SavedDevice(
        id: offer.deviceID, name: offer.deviceName, key: offer.deviceKey)
      let updatedDevices = Array(devices.values) + [saved]
      try saveDevices(libraryID: currentLibrary.libraryID, devices: updatedDevices)
      devices[saved.id] = saved
      let credential = SyncClientCredential(
        deviceID: saved.id, libraryID: currentLibrary.libraryID, key: saved.key)
      pending = PendingPhone(offer: offer, status: .approved(credential))
      pendingDeviceName = saved.name
      pairingCode = nil
      lastRequestResult = "Pair phone · code accepted; device credential stored."
      return .pairPending(offer.requestID)
    case .pairPoll(let sealed):
      guard Date() < pairingExpiresAt || pending?.status.isApproved == true else {
        return .error("Pairing code expired.")
      }
      let poll = try SyncCrypto.open(sealed, key: pairingKey, as: SyncPairingPoll.self)
      guard let pending, pending.offer.requestID == poll.requestID else {
        return .error("Pairing request was not found.")
      }
      lastRequestResult = "Pairing status · credential returned."
      return .pairStatus(try SyncCrypto.seal(pending.status, key: pairingKey))
    case .authenticated(let deviceID, let sealed):
      guard let device = devices[deviceID] else { return .error("This phone is no longer paired.") }
      let request = try SyncCrypto.open(sealed, key: device.key, as: SyncClientRequest.self)
      let state = currentLibrary
      let response: SyncServerResponse
      switch request {
      case .snapshot(let cursor):
        let isUnchanged = state.sequence == cursor
        lastRequestResult =
          isUnchanged
          ? "Refresh library · no new changes; server sequence \(state.sequence)."
          : "Refresh library · sent \(state.library.projects.count) projects and \(state.library.tasks.count) tasks at sequence \(state.sequence)."
        response =
          isUnchanged
          ? .unchanged(sequence: state.sequence)
          : .snapshot(
            SyncSnapshot(
              libraryID: state.libraryID, sequence: state.sequence, library: state.library))
      case .fullSnapshot:
        lastRequestResult =
          "Refresh everything · sent full library with \(state.library.projects.count) projects and \(state.library.tasks.count) tasks at sequence \(state.sequence)."
        response = .snapshot(
          SyncSnapshot(
            libraryID: state.libraryID, sequence: state.sequence, library: state.library))
      case .command(let envelope):
        guard envelope.deviceID == deviceID else { return .error("Invalid device identity.") }
        let result = try await repository.applyRemote(envelope)
        switch result {
        case .applied(let sequence, _):
          lastRequestResult = "Pending change · accepted at sequence \(sequence)."
          let updated = try await repository.syncStateSnapshot()
          onLibraryChanged?(updated.library)
        case .superseded(let sequence, _):
          lastRequestResult =
            "Pending change · superseded by newer Mac task at sequence \(sequence)."
        case .conflict:
          lastRequestResult = "Pending change · conflict; Mac state returned without applying edit."
        case .rejected(let message):
          lastRequestResult = "Pending change · rejected: \(message)"
        }
        response = .command(result)
      case .direct(let direct):
        do { response = .direct(try await handleDirect(direct, library: state.library)) } catch {
          response = .direct(.rejected(sanitized(error, library: state.library)))
        }
      }
      return .authenticated(try SyncCrypto.seal(response, key: device.key))
    case .loopbackProbe(let nonce):
      return .loopbackProbe(instanceID: instanceID, nonce: nonce)
    }
  }

  private func handleDirect(
    _ request: SyncDirectRequest, library: Library
  ) async throws -> SyncDirectResponse {
    switch request {
    case .readPlan(let taskID, let expectedRevision):
      guard let item = library.tasks.first(where: { $0.id == taskID }),
        item.revision == expectedRevision,
        let project = library.projects.first(where: { $0.id == item.projectID }),
        let path = item.planPath
      else {
        return .rejected("The task changed or no saved plan is attached. Refresh and try again.")
      }
      do {
        let url = try PlanFileStore.resolve(projectDirectory: project.directory, relativePath: path)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty, data.count <= 512_000,
          let markdown = String(data: data, encoding: .utf8),
          !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          return .rejected("The saved plan is empty, too large, or is not UTF-8 Markdown.")
        }
        return .plan(markdown)
      } catch {
        return .rejected("Could not read the saved plan: \(error.localizedDescription)")
      }
    case .modelCatalog:
      do {
        guard let onPhoneModelCatalogRequest else {
          return .rejected("Model discovery is unavailable on the Mac.")
        }
        let (configuration, options) = try await onPhoneModelCatalogRequest()
        return .modelCatalog(globalConfiguration: configuration, options: options)
      } catch {
        return .rejected("Could not refresh the model list: \(error.localizedDescription)")
      }
    case .invokeCodex(_, let taskID, let expectedRevision, let action):
      guard let item = library.tasks.first(where: { $0.id == taskID }),
        item.revision == expectedRevision
      else { return .rejected("The task changed on the Mac. Refresh and try again.") }
      do {
        guard let onPhoneCodexAction else {
          return .rejected("The Mac Codex action handler is unavailable.")
        }
        return .accepted(try await onPhoneCodexAction(taskID, expectedRevision, action))
      } catch {
        return .rejected(error.localizedDescription)
      }
    case .gitStatus(_, let projectID, let taskID, let expectedRevision):
      return try await gitStatus(
        projectID: projectID, taskID: taskID, expectedRevision: expectedRevision,
        library: library)
    case .commitTask(let requestID, let projectID, let taskID, let expectedRevision):
      return try await idempotentGitRequest(request, requestID: requestID) {
        guard
          let item = library.tasks.first(where: {
            $0.id == taskID && $0.projectID == projectID && $0.revision == expectedRevision
          }), let project = library.projects.first(where: { $0.id == projectID })
        else { return .rejected("The task changed on the Mac. Refresh and try again.") }
        guard !project.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return .rejected("Choose a project folder on the Mac before requesting Git actions.")
        }
        let folder = taskFolder(taskID: taskID, project: project, library: library)
        let result = try await gitService.commitAll(in: folder, taskTitle: item.title)
        return .accepted(
          "Committed \(result.hash.prefix(12)) · \(GitService.commitMessage(item.title))")
      }
    case .commitProject(let requestID, let projectID):
      return try await idempotentGitRequest(request, requestID: requestID) {
        guard let project = library.projects.first(where: { $0.id == projectID }),
          let latestTask = library.latestCompletedTask(in: projectID)
        else {
          return .rejected("Complete a task in this project before committing project changes.")
        }
        guard !project.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return .rejected("Choose a project folder on the Mac before requesting Git actions.")
        }
        let result = try await gitService.commitAll(
          in: URL(fileURLWithPath: project.directory), taskTitle: latestTask.title)
        return .accepted(
          "Committed \(result.hash.prefix(12)) · \(GitService.commitMessage(latestTask.title))")
      }
    case .recordDeployedRevision(let requestID, let projectID):
      return try await idempotentGitRequest(request, requestID: requestID) {
        guard var project = library.projects.first(where: { $0.id == projectID }) else {
          return .rejected("The project is no longer available.")
        }
        guard !project.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          return .rejected("Choose a project folder on the Mac before requesting Git actions.")
        }
        let status = try await gitService.status(in: URL(fileURLWithPath: project.directory))
        guard let head = status.head else {
          return .rejected("This repository has no commit to record as deployed.")
        }
        project.deployedCommitHash = head
        project.deployedAt = .now
        _ = try await repository.apply(.editProject(project))
        let updated = try await repository.syncStateSnapshot()
        onLibraryChanged?(updated.library)
        return .accepted("Recorded deployed revision \(head.prefix(12)).")
      }
    }
  }

  private func taskFolder(taskID: UUID, project: Project, library: Library) -> URL {
    if let path = library.latestRun(for: taskID)?.workDirectory {
      let url = URL(fileURLWithPath: path)
      if url.standardizedFileURL.path
        != URL(fileURLWithPath: project.directory).standardizedFileURL.path
      {
        return url
      }
    }
    return URL(fileURLWithPath: project.directory)
  }

  private func sanitized(_ error: Error, library: Library) -> String {
    var message = error.localizedDescription
    let privatePaths =
      library.projects.map(\.directory).filter { !$0.isEmpty }
      + library.tasks.compactMap { library.latestRun(for: $0.id)?.workDirectory }
    for path in privatePaths where !path.isEmpty {
      message = message.replacingOccurrences(of: path, with: "[private path]")
    }
    return String(message.prefix(800))
  }

  private func gitStatus(
    projectID: UUID, taskID: UUID?, expectedRevision: Int?, library: Library
  ) async throws -> SyncDirectResponse {
    guard let project = library.projects.first(where: { $0.id == projectID }),
      !project.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return .rejected("Choose a project folder on the Mac before requesting Git status.")
    }
    if let taskID {
      guard
        library.tasks.contains(where: {
          $0.id == taskID && $0.projectID == projectID && $0.revision == expectedRevision
        })
      else { return .rejected("The task changed on the Mac. Refresh and try again.") }
    } else if expectedRevision != nil {
      return .rejected("The Git status request is invalid.")
    }
    let folder =
      taskID.map { taskFolder(taskID: $0, project: project, library: library) }
      ?? URL(fileURLWithPath: project.directory)
    let status = try await gitService.status(in: folder)
    return .gitStatus(
      SyncGitStatus(
        branch: status.branch, head: status.head, changedFileCount: status.changedFileCount,
        stagedFileCount: status.stagedFileCount, unstagedFileCount: status.unstagedFileCount,
        untrackedFileCount: status.untrackedFileCount, isEmptyRepository: status.isEmptyRepository))
  }

  private func idempotentGitRequest(
    _ request: SyncDirectRequest, requestID: UUID,
    action: () async throws -> SyncDirectResponse
  ) async throws -> SyncDirectResponse {
    let digest = try SHA256.hash(data: JSONEncoder.syncEncoder.encode(request))
      .map { String(format: "%02x", $0) }.joined()
    if let receipt = gitReceipts[requestID] {
      guard receipt.digest == digest else {
        return .rejected("This Git operation ID was already used for different content.")
      }
      return receipt.response
    }
    let response = try await action()
    if case .rejected = response { return response }
    gitReceipts[requestID] = StoredGitReceipt(digest: digest, response: response)
    if gitReceipts.count > 2_000 {
      for key in gitReceipts.keys.prefix(gitReceipts.count - 2_000) {
        gitReceipts.removeValue(forKey: key)
      }
    }
    try JSONEncoder.syncEncoder.encode(gitReceipts).write(to: gitReceiptsURL, options: .atomic)
    return response
  }

  private var devicesLibraryID: UUID? {
    try? loadRegistry().libraryID
  }

  private func loadDevices(for libraryID: UUID) throws {
    guard let data = try KeychainVault.read(service: Self.keychainService, account: "devices")
    else {
      devices = [:]
      try saveDevices(libraryID: libraryID, devices: [])
      return
    }
    let registry = try JSONDecoder().decode(SavedDeviceRegistry.self, from: data)
    if registry.libraryID != libraryID {
      devices = [:]
      try saveDevices(libraryID: libraryID, devices: [])
    } else {
      devices = Dictionary(uniqueKeysWithValues: registry.devices.map { ($0.id, $0) })
    }
  }

  private func loadRegistry() throws -> SavedDeviceRegistry {
    guard let data = try KeychainVault.read(service: Self.keychainService, account: "devices")
    else {
      throw BoardError.invalid("The paired phone registry is unavailable.")
    }
    return try JSONDecoder().decode(SavedDeviceRegistry.self, from: data)
  }

  private func saveDevices(libraryID: UUID, devices: [SavedDevice]) throws {
    let registry = SavedDeviceRegistry(libraryID: libraryID, devices: devices)
    try KeychainVault.save(
      JSONEncoder.syncEncoder.encode(registry), service: Self.keychainService,
      account: "devices")
  }

  func clearNetworkEvents() {
    networkEvents = []
    do {
      try SyncNetworkEventJournal.save(networkEvents, at: networkEventsURL)
      eventLogError = nil
      lastPhoneContactAt = nil
      lastPhoneAddress = nil
      lastRequestResult = "No phone request received yet."
    } catch let caught {
      eventLogError = "Could not clear the connection log: \(caught.localizedDescription)"
    }
  }

  private func recordNetworkEvent(_ event: SyncNetworkEvent) {
    do {
      networkEvents = try SyncNetworkEventJournal.append(
        event, to: networkEvents, at: networkEventsURL)
      eventLogError = nil
    } catch let caught {
      networkEvents.insert(event, at: 0)
      networkEvents = Array(networkEvents.prefix(SyncNetworkEventJournal.maximumEvents))
      eventLogError = "Connection event could not be saved: \(caught.localizedDescription)"
    }
  }

  private nonisolated static func operationName(for request: SyncWireRequest) -> String {
    switch request {
    case .pairStart: "Pair phone"
    case .pairPoll: "Pairing status"
    case .authenticated: "Sync request"
    case .loopbackProbe: "Verify local port registration"
    }
  }

  func verifyPortRegistration() {
    guard status != "Off" else {
      portRegistrationStatus = "Listener is not running"
      return
    }
    let probeID = UUID()
    loopbackProbeID = probeID
    let nonce = UUID()
    let connection = NWConnection(
      host: NWEndpoint.Host("127.0.0.1"), port: Self.port, using: .tcp)
    loopbackConnection?.cancel()
    loopbackConnection = connection
    portRegistrationStatus = "Checking this StageChase instance…"
    let queue = DispatchQueue(label: "com.cseibert.StageChase.loopback-probe")
    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .ready:
        guard let frame = try? SyncFrame.encode(SyncWireRequest.loopbackProbe(nonce: nonce)) else {
          Task { @MainActor in
            self?.finishPortRegistration(
              probeID: probeID, connection: connection,
              status: "Could not create the loopback verification request.")
          }
          return
        }
        connection.send(
          content: frame,
          completion: .contentProcessed { error in
            if let error {
              Task { @MainActor in
                self?.finishPortRegistration(
                  probeID: probeID, connection: connection,
                  status: "Port check failed: \(error.localizedDescription)")
              }
              return
            }
            Self.receiveFrame(connection, buffer: Data()) { result in
              let response: SyncWireResponse
              do {
                response = try SyncFrame.decode(try result.get(), as: SyncWireResponse.self)
              } catch {
                Task { @MainActor in
                  self?.finishPortRegistration(
                    probeID: probeID, connection: connection,
                    status: "Another service answered on port \(Self.port.rawValue).")
                }
                return
              }
              Task { @MainActor in
                guard let self else { return }
                switch response {
                case .loopbackProbe(let responseInstanceID, let responseNonce):
                  guard responseNonce == nonce else {
                    self.finishPortRegistration(
                      probeID: probeID, connection: connection,
                      status: "A different service answered on port \(Self.port.rawValue).")
                    return
                  }
                  guard responseInstanceID == self.instanceID else {
                    self.finishPortRegistration(
                      probeID: probeID, connection: connection,
                      status: "Another StageChase instance answered on port \(Self.port.rawValue).")
                    return
                  }
                  self.finishPortRegistration(
                    probeID: probeID, connection: connection,
                    status:
                      "Verified · this StageChase instance is receiving requests on port \(Self.port.rawValue)."
                  )
                default:
                  self.finishPortRegistration(
                    probeID: probeID, connection: connection,
                    status: "A different service answered on port \(Self.port.rawValue).")
                }
              }
            }
          })
      case .waiting(let error), .failed(let error):
        Task { @MainActor in
          self?.finishPortRegistration(
            probeID: probeID, connection: connection,
            status: "Could not reach port \(Self.port.rawValue): \(error.localizedDescription)")
        }
      default:
        break
      }
    }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 5) { [weak self] in
      Task { @MainActor in
        self?.finishPortRegistration(
          probeID: probeID, connection: connection,
          status: "Port verification timed out after five seconds.")
      }
    }
  }

  private func finishPortRegistration(
    probeID: UUID, connection: NWConnection, status: String
  ) {
    guard loopbackProbeID == probeID else { return }
    loopbackProbeID = nil
    portRegistrationStatus = status
    connection.cancel()
    loopbackConnection = nil
  }

  nonisolated private static func receiveFrame(
    _ connection: NWConnection, buffer: Data,
    completion: @escaping @Sendable (Result<Data, Error>) -> Void
  ) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      data, _, isComplete, error in
      var bytes = buffer
      if let data { bytes.append(data) }
      if bytes.count >= 4 {
        let length = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= SyncProtocol.maximumMessageBytes else {
          completion(.failure(BoardError.invalid("Invalid synchronization frame size.")))
          return
        }
        if bytes.count >= Int(length) + 4 {
          completion(.success(Data(bytes.prefix(Int(length) + 4))))
          return
        }
      }
      if let error {
        completion(.failure(error))
        return
      }
      if isComplete {
        completion(.failure(BoardError.invalid("Incomplete synchronization frame.")))
        return
      }
      receiveFrame(connection, buffer: bytes, completion: completion)
    }
  }

  private static func localAddress() -> String? {
    var address: String?
    var fallback: String?
    var interfaces: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
    defer { freeifaddrs(interfaces) }
    for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
      guard let raw = item.pointee.ifa_addr, raw.pointee.sa_family == UInt8(AF_INET),
        let name = String(validatingCString: item.pointee.ifa_name), name != "lo0"
      else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(
        raw, socklen_t(raw.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
        NI_NUMERICHOST) == 0
      {
        let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let value = String(bytes: bytes, encoding: .utf8) else { continue }
        if name == "en0" {
          address = value
          break
        }
        if fallback == nil { fallback = value }
      }
    }
    return address ?? fallback
  }
}

extension SyncPairingStatus {
  fileprivate var isApproved: Bool { if case .approved = self { true } else { false } }
}

extension UUID {
  fileprivate static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
