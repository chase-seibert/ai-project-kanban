import Foundation
import Network
import Observation
import UIKit

private struct StoredPhonePairing: Codable {
  var endpoint: String
  var credential: SyncClientCredential
  var lastSequence: UInt64 = 0
  var lastServerSequence: UInt64 = 0
}

private struct PhoneOutbox: Codable {
  var operations: [SyncEnvelope] = []
  var conflictedOperationID: UUID?
}

/// Phone-side paired client. Pairing credentials live in Keychain; outbox and replica are separate.
@MainActor @Observable final class SyncClient {
  private static let keychainService = "com.cseibert.StageChase.phone-sync"
  private static let automaticSyncPreferenceKey = "phoneAutomaticSyncEnabled"
  @ObservationIgnored private let preferences: UserDefaults
  var endpoint = ""
  var pairingCode = ""
  var deviceName = UIDevice.current.name
  var automaticSyncEnabled: Bool {
    didSet { preferences.set(automaticSyncEnabled, forKey: Self.automaticSyncPreferenceKey) }
  }
  var status = "Not paired"
  var pairingInProgress = false
  var isSyncing = false
  var lastAttemptAt: Date?
  var lastResultMessage = "No sync attempted yet."
  var networkEvents: [SyncNetworkEvent] = []
  var eventLogError: String?
  var lastSuccessfulSync: Date?
  var credential: SyncClientCredential?
  var error: String?
  var outbox: [SyncEnvelope] = []
  var conflictedOperationID: UUID?
  private var lastSequence: UInt64 = 0
  private var lastServerSequence: UInt64 = 0
  private var outboxLoaded = true
  private let outboxURL: URL
  private let networkEventsURL: URL
  private var savedEndpoint = ""

  init(preferences: UserDefaults = .standard) {
    self.preferences = preferences
    automaticSyncEnabled =
      preferences.object(forKey: Self.automaticSyncPreferenceKey) as? Bool ?? true
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!.appendingPathComponent("StageChase", isDirectory: true)
    outboxURL = base.appendingPathComponent("PhoneSyncOutbox-v1.json")
    networkEventsURL = base.appendingPathComponent("PhoneSyncNetworkEvents-v1.json")
    do {
      if let data = try KeychainVault.read(service: Self.keychainService, account: "pairing") {
        let saved = try JSONDecoder().decode(StoredPhonePairing.self, from: data)
        endpoint = saved.endpoint
        savedEndpoint = saved.endpoint
        credential = saved.credential
        lastSequence = max(saved.lastSequence, outbox.map(\.clientSequence).max() ?? 0)
        lastServerSequence = saved.lastServerSequence
        status = "Paired · waiting for Mac"
      }
    } catch let caught { self.error = caught.localizedDescription }
    if FileManager.default.fileExists(atPath: outboxURL.path) {
      do {
        let data = try Data(contentsOf: outboxURL)
        let saved = try JSONDecoder().decode(PhoneOutbox.self, from: data)
        outbox = saved.operations
        conflictedOperationID = saved.conflictedOperationID
      } catch let caught {
        outboxLoaded = false
        self.error =
          "The offline queue could not be read and was left untouched: \(caught.localizedDescription)"
      }
    }
    lastSequence = max(lastSequence, outbox.map(\.clientSequence).max() ?? 0)
    do {
      networkEvents = try SyncNetworkEventJournal.load(from: networkEventsURL)
      lastAttemptAt = networkEvents.first?.date
      if let event = networkEvents.first {
        lastResultMessage = "\(event.operation) · \(event.outcome) · \(event.detail)"
      }
    } catch let caught {
      eventLogError = "Previous connection log could not be read: \(caught.localizedDescription)"
    }
  }

  var isPaired: Bool { credential != nil }
  var hasUnsavedEndpoint: Bool { isPaired && endpoint != savedEndpoint }
  var lastCompletedSyncAt: Date? {
    lastSuccessfulSync
      ?? networkEvents.first {
        $0.operation == "Sync result" && $0.outcome == "Complete"
      }?.date
  }

  func saveEndpoint() {
    do {
      _ = try Self.parseEndpoint(endpoint)
      guard let credential else { throw BoardError.invalid("Pair this phone with the Mac first.") }
      try save(
        endpoint: endpoint, credential: credential, lastSequence: lastSequence,
        lastServerSequence: lastServerSequence)
      savedEndpoint = endpoint
      status = "Address saved · not connected"
      error = nil
      lastResultMessage = "Saved the Mac address. Queued changes were preserved."
      recordLocalEvent(
        operation: "Address updated", result: "Saved",
        detail: "Changed the saved Mac address; pending edits were kept.")
    } catch let caught {
      error = caught.localizedDescription
    }
  }

  func clearNetworkEvents() {
    networkEvents = []
    do {
      try SyncNetworkEventJournal.save(networkEvents, at: networkEventsURL, protectForPhone: true)
      eventLogError = nil
    } catch let caught {
      eventLogError = "Could not clear the connection log: \(caught.localizedDescription)"
    }
  }

  func recordDiagnostic(_ detail: String) {
    let normalized = detail.lowercased()
    let outcome =
      normalized.hasPrefix("sync started")
      ? "Started"
      : (normalized.hasPrefix("sync failed") || normalized.hasPrefix("pairing failed")
        || normalized.hasPrefix("sync stopped") ? "Failed" : "Complete")
    appendEvent(
      SyncNetworkEvent(
        direction: "Phone", operation: "Sync result", requestBytes: 0, responseBytes: nil,
        outcome: outcome, detail: detail,
        elapsedMilliseconds: nil))
  }

  func pair() async throws -> UUID {
    guard !pairingInProgress else { throw BoardError.invalid("Pairing is already in progress.") }
    pairingInProgress = true
    defer { pairingInProgress = false }
    guard outboxLoaded else {
      throw BoardError.invalid("The existing offline queue could not be read. It was preserved.")
    }
    guard outbox.isEmpty else {
      throw BoardError.invalid(
        "Resolve the queued changes for this phone before creating another pairing.")
    }
    guard let secret = Data(base64Encoded: pairingCode.filter { !$0.isWhitespace }),
      secret.count >= 24
    else { throw BoardError.invalid("Enter the pairing code shown in Mac Settings.") }
    let route = try Self.parseEndpoint(endpoint)
    status = "Connecting to Mac…"
    error = nil
    let deviceID = UUID()
    let offer = SyncPairingOffer(
      deviceID: deviceID, deviceName: String(deviceName.prefix(80)),
      deviceKey: SyncCrypto.randomSecret())
    let request = SyncWireRequest.pairStart(try SyncCrypto.seal(offer, key: secret))
    guard
      case .pairPending(let requestID) = try await exchange(
        request, route: route, operation: "Pair phone")
    else {
      throw BoardError.invalid("The Mac did not accept the pairing request.")
    }
    status = "Pairing with Mac…"
    for _ in 0..<90 {
      try await Task.sleep(for: .seconds(1))
      let poll = SyncWireRequest.pairPoll(
        try SyncCrypto.seal(SyncPairingPoll(requestID: requestID), key: secret))
      switch try await exchange(poll, route: route, operation: "Pairing status") {
      case .pairStatus(let sealed):
        switch try SyncCrypto.open(sealed, key: secret, as: SyncPairingStatus.self) {
        case .waiting: continue
        case .rejected: throw BoardError.invalid("Pairing was declined on the Mac.")
        case .approved(let credential):
          guard credential.deviceID == deviceID else {
            throw BoardError.invalid("The Mac returned a different device identity.")
          }
          guard outbox.isEmpty else {
            throw BoardError.invalid(
              "This phone has unsent changes for its previous pairing. Keep them safely queued and resolve them before pairing another Mac."
            )
          }
          try save(
            endpoint: endpoint, credential: credential, lastSequence: 0, lastServerSequence: 0)
          savedEndpoint = endpoint
          self.credential = credential
          lastSequence = 0
          lastServerSequence = 0
          conflictedOperationID = nil
          try persistOutbox()
          pairingCode = ""
          status = "Paired · syncing"
          return credential.libraryID
        }
      case .error(let message): throw BoardError.invalid(message)
      default: throw BoardError.invalid("The Mac returned an invalid pairing response.")
      }
    }
    status = "Pairing timed out"
    throw BoardError.invalid("The Mac did not finish pairing before the request expired.")
  }

  func snapshot(cursor: UInt64) async throws -> SyncSnapshot? {
    guard let credential else { throw BoardError.invalid("Pair this phone with the Mac first.") }
    let route = try Self.parseEndpoint(endpoint)
    let body = try SyncCrypto.seal(SyncClientRequest.snapshot(cursor: cursor), key: credential.key)
    guard
      case .authenticated(let sealed) = try await exchange(
        .authenticated(deviceID: credential.deviceID, sealed: body), route: route,
        operation: "Refresh library")
    else { throw BoardError.invalid("The Mac returned an invalid sync response.") }
    let response = try SyncCrypto.open(sealed, key: credential.key, as: SyncServerResponse.self)
    let snapshot: SyncSnapshot
    switch response {
    case .snapshot(let value): snapshot = value
    case .unchanged(let sequence):
      lastServerSequence = sequence
      try save(
        endpoint: endpoint, credential: credential, lastSequence: lastSequence,
        lastServerSequence: sequence)
      lastSuccessfulSync = .now
      status = "Connected"
      return nil
    case .error(let message): throw BoardError.invalid(message)
    default: throw BoardError.invalid("The Mac returned an unexpected snapshot response.")
    }
    guard snapshot.libraryID == credential.libraryID else {
      throw BoardError.invalid("The Mac returned a snapshot for another library.")
    }
    lastServerSequence = snapshot.sequence
    try save(
      endpoint: endpoint, credential: credential, lastSequence: lastSequence,
      lastServerSequence: snapshot.sequence)
    lastSuccessfulSync = .now
    status = "Connected"
    return snapshot
  }

  func send(_ envelope: SyncEnvelope) async throws -> SyncCommandResult {
    guard let credential, envelope.libraryID == credential.libraryID,
      envelope.deviceID == credential.deviceID
    else { throw BoardError.invalid("This queued change belongs to another Mac library.") }
    let route = try Self.parseEndpoint(endpoint)
    let body = try SyncCrypto.seal(SyncClientRequest.command(envelope), key: credential.key)
    guard
      case .authenticated(let sealed) = try await exchange(
        .authenticated(deviceID: credential.deviceID, sealed: body), route: route,
        operation: "Send pending change")
    else { throw BoardError.invalid("The Mac returned an invalid command response.") }
    let response = try SyncCrypto.open(sealed, key: credential.key, as: SyncServerResponse.self)
    guard case .command(let result) = response else {
      throw BoardError.invalid("The Mac returned an unexpected command response.")
    }
    if case .applied(_, let snapshot) = result {
      lastServerSequence = max(lastServerSequence, snapshot.sequence)
      try save(
        endpoint: endpoint, credential: credential, lastSequence: lastSequence,
        lastServerSequence: lastServerSequence)
    }
    return result
  }

  /// Sends a user initiated request directly to the Mac. These controls stay out of the
  /// background refresh loop and offline edit queue.
  func requestDirect(_ direct: SyncDirectRequest) async throws -> SyncDirectResponse {
    guard let credential else { throw BoardError.invalid("Pair this phone with the Mac first.") }
    let route = try Self.parseEndpoint(endpoint)
    let body = try SyncCrypto.seal(SyncClientRequest.direct(direct), key: credential.key)
    guard
      case .authenticated(let sealed) = try await exchange(
        .authenticated(deviceID: credential.deviceID, sealed: body), route: route,
        operation: Self.directOperationName(direct))
    else { throw BoardError.invalid("The Mac returned an invalid direct response.") }
    let response = try SyncCrypto.open(sealed, key: credential.key, as: SyncServerResponse.self)
    guard case .direct(let result) = response else {
      throw BoardError.invalid("The Mac returned an unexpected direct response.")
    }
    if case .rejected(let message) = result { throw BoardError.invalid(message) }
    return result
  }

  private static func directOperationName(_ request: SyncDirectRequest) -> String {
    switch request {
    case .readPlan: "Read saved plan"
    case .modelCatalog: "Refresh Codex model list"
    case .invokeCodex(_, _, _, let action):
      action == .plan ? "Plan in Codex" : "Run with StageChase"
    }
  }

  func enqueue(_ command: SyncCommand, expectedRevision: Int? = nil) throws -> SyncEnvelope {
    guard outboxLoaded else { throw BoardError.invalid("The offline queue is unavailable.") }
    guard let credential else { throw BoardError.invalid("Pair this phone with the Mac first.") }
    guard outbox.count < 500 else {
      throw BoardError.invalid(
        "The offline queue is full. Reconnect to the Mac before adding more changes.")
    }
    lastSequence &+= 1
    let envelope = SyncEnvelope(
      libraryID: credential.libraryID, deviceID: credential.deviceID,
      clientSequence: lastSequence, expectedRevision: expectedRevision, command: command)
    try save(
      endpoint: endpoint, credential: credential, lastSequence: lastSequence,
      lastServerSequence: lastServerSequence)
    outbox.append(envelope)
    do { try persistOutbox() } catch {
      outbox.removeAll { $0.operationID == envelope.operationID }
      throw error
    }
    return envelope
  }

  func acknowledge(_ operationID: UUID) throws {
    let previous = outbox
    let previousConflict = conflictedOperationID
    outbox.removeAll { $0.operationID == operationID }
    if conflictedOperationID == operationID { conflictedOperationID = nil }
    do { try persistOutbox() } catch {
      outbox = previous
      conflictedOperationID = previousConflict
      throw error
    }
  }

  func markConflict(_ operationID: UUID) throws {
    let previous = conflictedOperationID
    conflictedOperationID = operationID
    do { try persistOutbox() } catch {
      conflictedOperationID = previous
      throw error
    }
  }

  func unpair() throws {
    try KeychainVault.delete(service: Self.keychainService, account: "pairing")
    credential = nil
    status = "Not paired"
    lastSuccessfulSync = nil
    error = nil
  }

  private func save(
    endpoint: String, credential: SyncClientCredential, lastSequence: UInt64,
    lastServerSequence: UInt64
  ) throws {
    let saved = StoredPhonePairing(
      endpoint: endpoint, credential: credential, lastSequence: lastSequence,
      lastServerSequence: lastServerSequence)
    try KeychainVault.save(
      try JSONEncoder.syncEncoder.encode(saved), service: Self.keychainService,
      account: "pairing")
  }

  private func persistOutbox() throws {
    guard outboxLoaded else {
      throw BoardError.invalid("The unreadable offline queue was preserved.")
    }
    let parent = outboxURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let data = try JSONEncoder.syncEncoder.encode(
      PhoneOutbox(operations: outbox, conflictedOperationID: conflictedOperationID))
    guard data.count <= 4_194_304 else {
      throw BoardError.invalid(
        "The offline queue exceeds its 4 MB safety limit. Reconnect and sync before editing more.")
    }
    try data.write(to: outboxURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outboxURL.path)
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: outboxURL.path)
    #endif
  }

  private func exchange(
    _ request: SyncWireRequest, route: (String, NWEndpoint.Port), operation: String
  ) async throws -> SyncWireResponse {
    let frame = try SyncFrame.encode(request)
    let startedAt = Date()
    lastAttemptAt = startedAt
    do {
      let response = try await NWOneShotExchange(host: route.0, port: route.1).run(frame)
      let decoded = try SyncFrame.decode(response, as: SyncWireResponse.self)
      let rejectedMessage: String?
      if case .error(let message) = decoded {
        rejectedMessage = message
      } else {
        rejectedMessage = nil
      }
      appendEvent(
        SyncNetworkEvent(
          direction: "Phone → Mac", remoteAddress: "\(route.0):\(route.1.rawValue)",
          operation: operation, requestBytes: frame.count,
          responseBytes: response.count,
          outcome: rejectedMessage == nil ? "Response received" : "Rejected",
          detail: rejectedMessage ?? "Framed response received; operation result is shown above.",
          elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)))
      lastResultMessage = rejectedMessage ?? "\(operation): framed response received."
      return decoded
    } catch {
      appendEvent(
        SyncNetworkEvent(
          direction: "Phone → Mac", remoteAddress: "\(route.0):\(route.1.rawValue)",
          operation: operation, requestBytes: frame.count,
          responseBytes: nil, outcome: "Failed", detail: error.localizedDescription,
          elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)))
      lastResultMessage = "\(operation) failed: \(error.localizedDescription)"
      throw error
    }
  }

  private func recordLocalEvent(operation: String, result: String, detail: String) {
    appendEvent(
      SyncNetworkEvent(
        direction: "Phone", operation: operation, requestBytes: 0, responseBytes: nil,
        outcome: result, detail: detail, elapsedMilliseconds: nil))
  }

  private func appendEvent(_ event: SyncNetworkEvent) {
    do {
      networkEvents = try SyncNetworkEventJournal.append(
        event, to: networkEvents, at: networkEventsURL, protectForPhone: true)
      eventLogError = nil
    } catch let caught {
      networkEvents.insert(event, at: 0)
      networkEvents = Array(networkEvents.prefix(SyncNetworkEventJournal.maximumEvents))
      eventLogError = "Connection event could not be saved: \(caught.localizedDescription)"
    }
  }

  private static func parseEndpoint(_ value: String) throws -> (String, NWEndpoint.Port) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.contains("://") ? trimmed : "stagechase://\(trimmed)"
    guard let components = URLComponents(string: normalized),
      ["stagechase", "tcp"].contains(components.scheme?.lowercased() ?? ""),
      let host = components.host, !host.isEmpty,
      let rawPort = components.port, let port = NWEndpoint.Port(rawValue: UInt16(rawPort))
    else { throw BoardError.invalid("Enter the local address shown in Mac Settings.") }
    return (host, port)
  }
}

private final class NWOneShotExchange: @unchecked Sendable {
  private let connection: NWConnection
  private let remoteAddress: String
  private let queue = DispatchQueue(label: "com.cseibert.StageChase.phone-sync")
  private let lock = NSLock()
  private var buffer = Data()
  private var finished = false
  private var waitingError: String?

  init(host: String, port: NWEndpoint.Port) {
    remoteAddress = "\(host):\(port.rawValue)"
    connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
  }

  func run(_ request: Data) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let timeout = DispatchWorkItem { [weak self] in
        guard let self else { return }
        let detail = self.waitingError.map { " Network.framework reports: \($0)." } ?? ""
        self.finish(
          .failure(
            BoardError.invalid(
              "Could not reach Mac at \(self.remoteAddress) before the connection timed out. Check that the Mac app has local sync enabled and that this address and port are current.\(detail)"
            )),
          continuation)
      }
      queue.asyncAfter(deadline: .now() + 10, execute: timeout)
      connection.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          self.connection.send(
            content: request,
            completion: .contentProcessed { error in
              if let error {
                self.finish(.failure(error), continuation)
              } else {
                self.receive(continuation)
              }
            })
        case .waiting(let error): self.waitingError = error.localizedDescription
        case .failed(let error):
          self.finish(
            .failure(
              BoardError.invalid(
                "Could not connect to Mac at \(self.remoteAddress): \(error.localizedDescription)")),
            continuation)
        case .cancelled:
          self.finish(.failure(BoardError.invalid("Connection closed.")), continuation)
        default: break
        }
      }
      connection.start(queue: queue)
    }
  }

  private func receive(_ continuation: CheckedContinuation<Data, Error>) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, complete, error in
      guard let self else { return }
      if let error {
        self.finish(.failure(error), continuation)
        return
      }
      if let data { self.buffer.append(data) }
      if self.buffer.count >= 4 {
        let length = self.buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= SyncProtocol.maximumMessageBytes else {
          self.finish(.failure(BoardError.invalid("Invalid response frame.")), continuation)
          return
        }
        if self.buffer.count >= Int(length) + 4 {
          self.finish(.success(Data(self.buffer.prefix(Int(length) + 4))), continuation)
          return
        }
      }
      if complete {
        self.finish(.failure(BoardError.invalid("Incomplete response frame.")), continuation)
      } else {
        self.receive(continuation)
      }
    }
  }

  private func finish(
    _ result: Result<Data, Error>, _ continuation: CheckedContinuation<Data, Error>
  ) {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    finished = true
    lock.unlock()
    connection.cancel()
    continuation.resume(with: result)
  }
}
