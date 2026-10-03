import CryptoKit
import Foundation

/// Versioned, intentionally narrow protocol for a phone replica of one Mac library.
public enum SyncProtocol {
  // Version 4 adds shared task/project read markers and acknowledgment commands.
  // Older clients are rejected before any replica or outbox state is changed.
  public static let version = 4
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
  /// Phone edit time captured when the operation is queued, never when it reaches the Mac.
  public var editedAt: Date
  public var command: SyncCommand

  public init(
    libraryID: UUID, deviceID: UUID, clientSequence: UInt64 = 1,
    operationID: UUID = UUID(), expectedRevision: Int? = nil, editedAt: Date = .now,
    command: SyncCommand
  ) {
    version = SyncProtocol.version
    self.libraryID = libraryID
    self.deviceID = deviceID
    self.operationID = operationID
    self.clientSequence = clientSequence
    self.expectedRevision = expectedRevision
    self.editedAt = editedAt
    self.command = command
  }

  private enum CodingKeys: String, CodingKey {
    case version, libraryID, deviceID, operationID, clientSequence, expectedRevision, editedAt,
      command
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    libraryID = try values.decode(UUID.self, forKey: .libraryID)
    deviceID = try values.decode(UUID.self, forKey: .deviceID)
    operationID = try values.decode(UUID.self, forKey: .operationID)
    clientSequence = try values.decode(UInt64.self, forKey: .clientSequence)
    expectedRevision = try values.decodeIfPresent(Int.self, forKey: .expectedRevision)
    editedAt = try values.decodeIfPresent(Date.self, forKey: .editedAt) ?? .distantPast
    command = try values.decode(SyncCommand.self, forKey: .command)
  }
}

/// The wire command allowlist does not expose `Mutation` or server-owned fields.
public enum SyncCommand: Codable, Equatable, Sendable {
  case createTask(id: UUID, projectID: UUID, title: String, notes: String, stage: WorkflowStage)
  case editTask(id: UUID, title: String, notes: String)
  case moveTask(id: UUID, stage: WorkflowStage)
  case reorderTask(id: UUID, beforeID: UUID, orderDigest: String)
  case completeTask(id: UUID, completed: Bool)
  case deleteTask(id: UUID)
  case acknowledgeTaskChanges(taskID: UUID, marker: TaskChangeReadMarker)
  case acknowledgeProjectChanges(projectID: UUID, marker: TaskChangeReadMarker)
  case updateProjectCodexSettings(
    id: UUID, expectedProfile: CodexExecutionProfile,
    expectedModelOverride: CodexModelConfiguration?, profile: CodexExecutionProfile,
    modelOverride: CodexModelConfiguration?)
}

public enum SyncPhoneCodexAction: String, Codable, Sendable {
  case plan
  case run
}

/// Direct requests are initiated by a visible phone control. They are never part of background
/// refresh or the offline edit queue.
public enum SyncDirectRequest: Codable, Sendable {
  case readPlan(taskID: UUID, expectedRevision: Int)
  case modelCatalog
  case invokeCodex(
    requestID: UUID, taskID: UUID, expectedRevision: Int, action: SyncPhoneCodexAction)
  case gitStatus(
    requestID: UUID, projectID: UUID, taskID: UUID?, expectedRevision: Int?)
  case commitTask(requestID: UUID, projectID: UUID, taskID: UUID, expectedRevision: Int)
  case commitProject(requestID: UUID, projectID: UUID)
  case recordDeployedRevision(requestID: UUID, projectID: UUID)
}

public struct SyncGitStatus: Codable, Equatable, Sendable {
  public var branch: String?
  public var head: String?
  public var changedFileCount: Int
  public var stagedFileCount: Int
  public var unstagedFileCount: Int
  public var untrackedFileCount: Int
  public var isEmptyRepository: Bool

  public init(
    branch: String?, head: String?, changedFileCount: Int, stagedFileCount: Int,
    unstagedFileCount: Int, untrackedFileCount: Int, isEmptyRepository: Bool
  ) {
    self.branch = branch
    self.head = head
    self.changedFileCount = changedFileCount
    self.stagedFileCount = stagedFileCount
    self.unstagedFileCount = unstagedFileCount
    self.untrackedFileCount = untrackedFileCount
    self.isEmptyRepository = isEmptyRepository
  }
}

public enum SyncDirectResponse: Codable, Sendable {
  case plan(String)
  case modelCatalog(globalConfiguration: CodexModelConfiguration, options: [CodexModelOption])
  case accepted(String)
  case gitStatus(SyncGitStatus)
  case rejected(String)
}

public enum SyncCommandResult: Codable, Equatable, Sendable {
  case applied(sequence: UInt64, snapshot: SyncSnapshot)
  case superseded(sequence: UInt64, current: SyncSnapshot)
  case conflict(current: SyncSnapshot)
  case rejected(message: String)
}

public enum SyncCommandValidator {
  public static func orderDigest(
    projectID: UUID, stage: WorkflowStage, in library: Library
  ) -> String {
    let section = WorkItem.legacySection(for: stage)
    let ids = library.items(in: projectID, section: section, completed: true)
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
      var item = existing
      item.title = title
      item.notes = notes
      return .syncEditTask(item, expectedRevision: revision)
    case .moveTask(let id, let stage):
      guard let revision = envelope.expectedRevision,
        library.tasks.contains(where: { $0.id == id })
      else { throw BoardError.missing }
      return .move(id, stage, expectedRevision: revision)
    case .reorderTask(let id, let beforeID, let digest):
      guard let revision = envelope.expectedRevision,
        let item = library.tasks.first(where: { $0.id == id }),
        let target = library.tasks.first(where: { $0.id == beforeID }),
        item.projectID == target.projectID, item.section == target.section
      else { throw BoardError.missing }
      guard digest == orderDigest(projectID: item.projectID, stage: item.stage, in: library) else {
        throw BoardError.conflict
      }
      return .reorder(id, before: beforeID, expectedRevision: revision)
    case .completeTask(let id, let completed):
      guard let revision = envelope.expectedRevision,
        library.tasks.contains(where: { $0.id == id })
      else { throw BoardError.missing }
      return .complete(id, completed, expectedRevision: revision)
    case .deleteTask(let id):
      guard let revision = envelope.expectedRevision,
        library.tasks.contains(where: { $0.id == id })
      else { throw BoardError.missing }
      return .deleteTask(id, expectedRevision: revision)
    case .acknowledgeTaskChanges, .acknowledgeProjectChanges:
      throw BoardError.invalid("Read acknowledgments are handled by the sync repository.")
    case .updateProjectCodexSettings(
      let id, let expectedProfile, let expectedModelOverride, let profile, let modelOverride):
      guard envelope.expectedRevision == nil,
        var project = library.projects.first(where: { $0.id == id })
      else { throw BoardError.missing }
      guard project.executionProfile == expectedProfile,
        project.modelOverride == expectedModelOverride
      else { throw BoardError.conflict }
      project.executionProfile = profile
      project.modelOverride = modelOverride
      return .editProject(project)
    }
  }
}

public struct SyncTask: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var projectID: UUID
  public var title: String
  public var notes: String
  public var stage: WorkflowStage
  public var section: WorkflowSection?
  public var status: TaskStatus?
  public var rank: Int
  public var completed: Bool
  public var priority: TaskPriority?
  public var revision: Int
  public var createdAt: Date
  public var updatedAt: Date

  public init(_ item: WorkItem) {
    id = item.id
    projectID = item.projectID
    title = item.title
    notes = item.notes
    stage = item.stage
    section = item.section
    status = item.status
    rank = item.rank
    completed = item.completed
    priority = item.priority
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
  /// Informational on iPhone; only the Mac runner can execute Codex work.
  public var executionProfile: CodexExecutionProfile?
  public var deployedCommitHash: String?
  public var deployedAt: Date?
  public var favoriteMakeTargets: [String]?
  public var createdAt: Date

  public init(_ project: Project) {
    id = project.id
    name = project.name
    automationEnabled = project.automationEnabled
    usesWorktrees = project.usesWorktrees
    modelOverride = project.modelOverride
    executionProfile = project.executionProfile
    deployedCommitHash = project.deployedCommitHash
    deployedAt = project.deployedAt
    favoriteMakeTargets = project.favoriteMakeTargets
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
  public var taskReadMarkers: [UUID: TaskChangeReadMarker]
  public var projectReadMarkers: [UUID: TaskChangeReadMarker]

  public init(
    libraryID: UUID, sequence: UInt64, library: Library,
    taskReadMarkers: [UUID: TaskChangeReadMarker] = [:],
    projectReadMarkers: [UUID: TaskChangeReadMarker] = [:]
  ) {
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
    self.taskReadMarkers = taskReadMarkers
    self.projectReadMarkers = projectReadMarkers
  }

  private enum CodingKeys: String, CodingKey {
    case version, libraryID, sequence, projects, tasks, runs, activity, taskReadMarkers,
      projectReadMarkers
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    libraryID = try values.decode(UUID.self, forKey: .libraryID)
    sequence = try values.decode(UInt64.self, forKey: .sequence)
    projects = try values.decode([SyncProject].self, forKey: .projects)
    tasks = try values.decode([SyncTask].self, forKey: .tasks)
    runs = try values.decode([SyncRun].self, forKey: .runs)
    activity = try values.decode([Activity].self, forKey: .activity)
    taskReadMarkers =
      try values.decodeIfPresent([UUID: TaskChangeReadMarker].self, forKey: .taskReadMarkers) ?? [:]
    projectReadMarkers =
      try values.decodeIfPresent([UUID: TaskChangeReadMarker].self, forKey: .projectReadMarkers)
      ?? [:]
  }

  public func replica() throws -> Library {
    guard version == SyncProtocol.version else {
      throw BoardError.invalid("The Mac uses an unsupported synchronization protocol version.")
    }
    guard taskReadMarkers.keys.allSatisfy({ id in tasks.contains(where: { $0.id == id }) }),
      projectReadMarkers.keys.allSatisfy({ id in projects.contains(where: { $0.id == id }) })
    else { throw BoardError.invalid("The Mac returned read markers for missing records.") }
    var library = Library()
    library.projects = projects.map {
      var project = Project(name: $0.name)
      project.id = $0.id
      project.automationEnabled = $0.automationEnabled
      project.usesWorktrees = $0.usesWorktrees ?? false
      project.modelOverride = $0.modelOverride
      project.executionProfile = $0.executionProfile ?? .workspaceAccessNoPrompts
      project.deployedCommitHash = $0.deployedCommitHash
      project.deployedAt = $0.deployedAt
      project.favoriteMakeTargets = $0.favoriteMakeTargets ?? []
      project.createdAt = $0.createdAt
      return project
    }
    library.tasks = tasks.map {
      var item = WorkItem(projectID: $0.projectID, title: $0.title, stage: $0.stage)
      item.section =
        $0.section ?? ($0.completed ? .implementing : WorkItem.legacySection(for: $0.stage))
      item.status = $0.status ?? ($0.completed ? .done : TaskStatus.legacyStatus(for: $0.stage))
      item.id = $0.id
      item.notes = $0.notes
      item.rank = $0.rank
      item.completed = $0.completed
      item.priority = $0.priority
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

/// A read-through point captures both activity time and ID so timestamp ties converge.
public struct TaskChangeReadMarker: Codable, Equatable, Sendable {
  public var date: Date
  /// Nil is used only for migrated date-only markers and acknowledges all events at that time.
  public var activityID: UUID?

  public init(date: Date, activityID: UUID? = nil) {
    self.date = date
    self.activityID = activityID
  }

  public func acknowledges(_ activity: Activity) -> Bool {
    if activity.date != date { return activity.date < date }
    guard let activityID else { return true }
    return activity.id.uuidString.lowercased() <= activityID.uuidString.lowercased()
  }

  public static func later(_ lhs: Self?, _ rhs: Self) -> Self {
    guard let lhs else { return rhs }
    if lhs.date != rhs.date { return lhs.date > rhs.date ? lhs : rhs }
    guard let lhsID = lhs.activityID else { return lhs }
    guard let rhsID = rhs.activityID else { return rhs }
    return lhsID.uuidString.lowercased() >= rhsID.uuidString.lowercased() ? lhs : rhs
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
  case fullSnapshot
  case command(SyncEnvelope)
  case direct(SyncDirectRequest)
}

public enum SyncServerResponse: Codable, Sendable {
  case snapshot(SyncSnapshot)
  case unchanged(sequence: UInt64)
  case command(SyncCommandResult)
  case direct(SyncDirectResponse)
  case error(String)
}

public enum SyncWireRequest: Codable, Equatable, Sendable {
  case pairStart(Data)
  case pairPoll(Data)
  case authenticated(deviceID: UUID, sealed: Data)
  case loopbackProbe(nonce: UUID)
}

public enum SyncWireResponse: Codable, Sendable {
  case pairPending(UUID)
  case pairStatus(Data)
  case authenticated(Data)
  case loopbackProbe(instanceID: UUID, nonce: UUID)
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
