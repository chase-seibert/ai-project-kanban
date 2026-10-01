import CryptoKit
import Foundation

/// Versioned, intentionally narrow protocol for a phone replica of one Mac library.
public enum SyncProtocol {
  public static let version = 1
  public static let maximumMessageBytes = 1_048_576
  public static let maximumPairingSecretBytes = 64
}

public struct SyncEnvelope: Codable, Equatable, Sendable {
  public var version: Int
  public var libraryID: UUID
  public var deviceID: UUID
  public var operationID: UUID
  public var clientSequence: UInt64
  public var expectedRevision: Int?
  public var command: SyncCommand

  public init(
    libraryID: UUID, deviceID: UUID, clientSequence: UInt64 = 1,
    operationID: UUID = UUID(), expectedRevision: Int? = nil, command: SyncCommand
  ) {
    version = SyncProtocol.version
    self.libraryID = libraryID
    self.deviceID = deviceID
    self.operationID = operationID
    self.clientSequence = clientSequence
    self.expectedRevision = expectedRevision
    self.command = command
  }
}

/// The wire command allowlist does not expose `Mutation` or server-owned fields.
public enum SyncCommand: Codable, Equatable, Sendable {
  case createTask(id: UUID, projectID: UUID, title: String, notes: String, stage: WorkflowStage)
  case editTask(id: UUID, title: String, notes: String)
  case moveTask(id: UUID, stage: WorkflowStage)
  case reorderTask(id: UUID, beforeID: UUID, orderDigest: String)
}

public enum SyncCommandResult: Codable, Equatable, Sendable {
  case applied(sequence: UInt64, snapshot: SyncSnapshot)
  case conflict(current: SyncSnapshot)
  case rejected(message: String)
}

public enum SyncCommandValidator {
  public static func orderDigest(
    projectID: UUID, stage: WorkflowStage, in library: Library
  ) -> String {
    let ids = library.items(in: projectID, stage: stage, completed: true)
      .map { "\($0.id.uuidString):\($0.revision)" }.joined(separator: "|")
    return SHA256.hash(data: Data(ids.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  public static func mutation(for envelope: SyncEnvelope, in library: Library) throws -> Mutation {
    guard envelope.version == SyncProtocol.version else {
      throw BoardError.invalid("This phone uses an unsupported synchronization protocol version.")
    }
    switch envelope.command {
    case .createTask(let id, let projectID, let title, let notes, let stage):
      guard envelope.expectedRevision == nil,
        library.projects.contains(where: { $0.id == projectID })
      else { throw BoardError.invalid("The selected project is no longer available.") }
      var item = WorkItem(projectID: projectID, title: title, stage: stage)
      item.id = id
      item.notes = notes
      return .createTask(item)
    case .editTask(let id, let title, let notes):
      guard let revision = envelope.expectedRevision,
        let existing = library.tasks.first(where: { $0.id == id })
      else { throw BoardError.missing }
      guard !library.runs.contains(where: { $0.taskID == id && $0.status.isActive }) else {
        throw BoardError.busy
      }
      var item = existing
      item.title = title
      item.notes = notes
      return .editTask(item, expectedRevision: revision)
    case .moveTask(let id, let stage):
      guard let revision = envelope.expectedRevision,
        library.tasks.contains(where: { $0.id == id })
      else { throw BoardError.missing }
      return .move(id, stage, expectedRevision: revision)
    case .reorderTask(let id, let beforeID, let digest):
      guard let revision = envelope.expectedRevision,
        let item = library.tasks.first(where: { $0.id == id }),
        let target = library.tasks.first(where: { $0.id == beforeID }),
        item.projectID == target.projectID, item.stage == target.stage
      else { throw BoardError.missing }
      guard digest == orderDigest(projectID: item.projectID, stage: item.stage, in: library) else {
        throw BoardError.conflict
      }
      return .reorder(id, before: beforeID, expectedRevision: revision)
    }
  }
}

public struct SyncTask: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var projectID: UUID
  public var title: String
  public var notes: String
  public var stage: WorkflowStage
  public var rank: Int
  public var completed: Bool
  public var revision: Int
  public var createdAt: Date
  public var updatedAt: Date

  public init(_ item: WorkItem) {
    id = item.id
    projectID = item.projectID
    title = item.title
    notes = item.notes
    stage = item.stage
    rank = item.rank
    completed = item.completed
    revision = item.revision
    createdAt = item.createdAt
    updatedAt = item.updatedAt
  }
}

public struct SyncProject: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var automationEnabled: Bool
  public var usesWorktrees: Bool?
  public var modelOverride: CodexModelConfiguration?
  public var createdAt: Date

  public init(_ project: Project) {
    id = project.id
    name = project.name
    automationEnabled = project.automationEnabled
    usesWorktrees = project.usesWorktrees
    modelOverride = project.modelOverride
    createdAt = project.createdAt
  }
}

public struct SyncRun: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var taskID: UUID
  public var projectID: UUID
  public var kind: RunKind
  public var status: RunStatus
  public var summary: String
  public var updatedAt: Date

  public init(_ run: AgentRun) {
    id = run.id
    taskID = run.taskID
    projectID = run.projectID
    kind = run.kind
    status = run.status
    summary = run.summary
    updatedAt = run.updatedAt
  }
}

public struct SyncSnapshot: Codable, Equatable, Sendable {
  public var version: Int
  public var libraryID: UUID
  public var sequence: UInt64
  public var projects: [SyncProject]
  public var tasks: [SyncTask]
  public var runs: [SyncRun]
  public var activity: [Activity]

  public init(libraryID: UUID, sequence: UInt64, library: Library) {
    version = SyncProtocol.version
    self.libraryID = libraryID
    self.sequence = sequence
    projects = library.projects.map(SyncProject.init)
    tasks = library.tasks.map(SyncTask.init)
    runs = library.runs.map(SyncRun.init)
    let privatePaths =
      library.projects.map(\.directory).filter { !$0.isEmpty }
      + library.tasks.compactMap(\.planPath)
    activity = library.activity.suffix(200).map { entry in
      var safe = entry
      for path in privatePaths where !path.isEmpty {
        safe.message = safe.message.replacingOccurrences(of: path, with: "[private path]")
      }
      return safe
    }
  }

  public func replica() throws -> Library {
    guard version == SyncProtocol.version else {
      throw BoardError.invalid("The Mac uses an unsupported synchronization protocol version.")
    }
    var library = Library()
    library.projects = projects.map {
      var project = Project(name: $0.name)
      project.id = $0.id
      project.automationEnabled = $0.automationEnabled
      project.usesWorktrees = $0.usesWorktrees ?? false
      project.modelOverride = $0.modelOverride
      project.createdAt = $0.createdAt
      return project
    }
    library.tasks = tasks.map {
      var item = WorkItem(projectID: $0.projectID, title: $0.title, stage: $0.stage)
      item.id = $0.id
      item.notes = $0.notes
      item.rank = $0.rank
      item.completed = $0.completed
      item.revision = $0.revision
      item.createdAt = $0.createdAt
      item.updatedAt = $0.updatedAt
      return item
    }
    library.runs = runs.map { syncRun in
      var run = AgentRun(
        task: library.tasks.first(where: { $0.id == syncRun.taskID })
          ?? WorkItem(
            projectID: syncRun.projectID, title: "Unavailable task"), kind: syncRun.kind)
      run.id = syncRun.id
      run.taskID = syncRun.taskID
      run.projectID = syncRun.projectID
      run.status = syncRun.status
      run.summary = syncRun.summary
      run.updatedAt = syncRun.updatedAt
      return run
    }
    library.activity = activity
    try library.validate()
    return library
  }
}

public enum SyncCrypto {
  public static func randomSecret(count: Int = 32) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
  }

  public static func deriveKey(secret: Data, salt: Data, context: String) -> Data {
    let input = SymmetricKey(data: secret)
    let key = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: input, salt: salt, info: Data(context.utf8), outputByteCount: 32)
    return key.withUnsafeBytes { Data($0) }
  }

  public static func seal<Payload: Encodable>(_ payload: Payload, key: Data) throws -> Data {
    guard key.count == 32 else { throw BoardError.invalid("Invalid synchronization key.") }
    let plaintext = try JSONEncoder.syncEncoder.encode(payload)
    guard plaintext.count <= SyncProtocol.maximumMessageBytes else {
      throw BoardError.invalid("The synchronization message is too large.")
    }
    let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key))
    guard let combined = box.combined else { throw BoardError.invalid("Could not seal message.") }
    return combined
  }

  public static func open<Payload: Decodable>(_ data: Data, key: Data, as: Payload.Type) throws
    -> Payload
  {
    guard key.count == 32, data.count <= SyncProtocol.maximumMessageBytes + 64 else {
      throw BoardError.invalid("Invalid synchronization message size or key.")
    }
    let box = try AES.GCM.SealedBox(combined: data)
    let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key))
    return try JSONDecoder.syncDecoder.decode(Payload.self, from: plaintext)
  }
}

public struct SyncPairingOffer: Codable, Sendable {
  public var requestID: UUID
  public var deviceID: UUID
  public var deviceName: String
  public var deviceKey: Data
  public init(requestID: UUID = UUID(), deviceID: UUID, deviceName: String, deviceKey: Data) {
    self.requestID = requestID
    self.deviceID = deviceID
    self.deviceName = String(deviceName.prefix(80))
    self.deviceKey = deviceKey
  }
}

public struct SyncPairingPoll: Codable, Sendable {
  public var requestID: UUID
  public init(requestID: UUID) { self.requestID = requestID }
}

public struct SyncClientCredential: Codable, Equatable, Sendable {
  public var deviceID: UUID
  public var libraryID: UUID
  public var key: Data
  public init(deviceID: UUID, libraryID: UUID, key: Data) {
    self.deviceID = deviceID
    self.libraryID = libraryID
    self.key = key
  }
}

public enum SyncPairingStatus: Codable, Sendable {
  case waiting
  case approved(SyncClientCredential)
  case rejected
}

public enum SyncClientRequest: Codable, Sendable {
  case snapshot(cursor: UInt64)
  case command(SyncEnvelope)
}

public enum SyncServerResponse: Codable, Sendable {
  case snapshot(SyncSnapshot)
  case unchanged(sequence: UInt64)
  case command(SyncCommandResult)
  case error(String)
}

public enum SyncWireRequest: Codable, Equatable, Sendable {
  case pairStart(Data)
  case pairPoll(Data)
  case authenticated(deviceID: UUID, sealed: Data)
}

public enum SyncWireResponse: Codable, Sendable {
  case pairPending(UUID)
  case pairStatus(Data)
  case authenticated(Data)
  case error(String)
}

public enum SyncFrame {
  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let payload = try JSONEncoder.syncEncoder.encode(value)
    guard !payload.isEmpty, payload.count <= SyncProtocol.maximumMessageBytes else {
      throw BoardError.invalid("The synchronization message is too large.")
    }
    var length = UInt32(payload.count).bigEndian
    var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
    frame.append(payload)
    return frame
  }

  public static func decode<T: Decodable>(_ data: Data, as: T.Type) throws -> T {
    guard data.count >= 4 else { throw BoardError.invalid("Incomplete synchronization frame.") }
    let length = data.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard length > 0, length <= SyncProtocol.maximumMessageBytes,
      data.count == Int(length) + 4
    else { throw BoardError.invalid("Invalid synchronization frame length.") }
    return try JSONDecoder.syncDecoder.decode(T.self, from: data.dropFirst(4))
  }
}

extension JSONEncoder {
  static var syncEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

extension JSONDecoder {
  static var syncDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
