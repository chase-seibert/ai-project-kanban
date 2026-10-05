import CryptoKit
import Foundation
import SwiftData

public enum StageSchemaV1: VersionedSchema {
  public static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
  public static var models: [any PersistentModel.Type] { [Entry.self] }
  @Model public final class Entry {
    @Attribute(.unique) public var key: String
    public var kind: String
    public var projectID: UUID?
    public var payload: Data
    public init(key: String, kind: String, projectID: UUID?, payload: Data) {
      self.key = key
      self.kind = kind
      self.projectID = projectID
      self.payload = payload
    }
  }
}

enum StageMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] { [StageSchemaV1.self] }
  static var stages: [MigrationStage] { [] }
}

private struct StoredSyncReceipt: Codable, Sendable {
  var payloadDigest: String
  var sequence: UInt64
  var deviceID: UUID
  var clientSequence: UInt64
  var superseded: Bool = false

  private enum CodingKeys: String, CodingKey {
    case payloadDigest, sequence, deviceID, clientSequence, superseded
  }

  init(
    payloadDigest: String, sequence: UInt64, deviceID: UUID, clientSequence: UInt64,
    superseded: Bool = false
  ) {
    self.payloadDigest = payloadDigest
    self.sequence = sequence
    self.deviceID = deviceID
    self.clientSequence = clientSequence
    self.superseded = superseded
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    payloadDigest = try values.decode(String.self, forKey: .payloadDigest)
    sequence = try values.decode(UInt64.self, forKey: .sequence)
    deviceID = try values.decode(UUID.self, forKey: .deviceID)
    clientSequence = try values.decode(UInt64.self, forKey: .clientSequence)
    superseded = try values.decodeIfPresent(Bool.self, forKey: .superseded) ?? false
  }
}

private struct StoredTaskEditVersion: Codable, Sendable {
  var editedAt: Date
  var deviceID: UUID
  var clientSequence: UInt64
}

private struct StoredSyncState: Codable, Sendable {
  var libraryID = UUID()
  var sequence: UInt64 = 0
  var deviceHighWater: [UUID: UInt64] = [:]
  var receipts: [UUID: StoredSyncReceipt] = [:]
  var phoneTaskVersions: [UUID: StoredTaskEditVersion] = [:]
  var taskReadMarkers: [UUID: TaskChangeReadMarker] = [:]
  var projectReadMarkers: [UUID: TaskChangeReadMarker] = [:]

  private enum CodingKeys: String, CodingKey {
    case libraryID, sequence, deviceHighWater, receipts, phoneTaskVersions, taskReadMarkers,
      projectReadMarkers
  }

  init() {}

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    libraryID = try values.decodeIfPresent(UUID.self, forKey: .libraryID) ?? UUID()
    sequence = try values.decodeIfPresent(UInt64.self, forKey: .sequence) ?? 0
    deviceHighWater =
      try values.decodeIfPresent([UUID: UInt64].self, forKey: .deviceHighWater) ?? [:]
    receipts = try values.decodeIfPresent([UUID: StoredSyncReceipt].self, forKey: .receipts) ?? [:]
    phoneTaskVersions =
      try values.decodeIfPresent(
        [UUID: StoredTaskEditVersion].self, forKey: .phoneTaskVersions) ?? [:]
    taskReadMarkers =
      try values.decodeIfPresent([UUID: TaskChangeReadMarker].self, forKey: .taskReadMarkers) ?? [:]
    projectReadMarkers =
      try values.decodeIfPresent([UUID: TaskChangeReadMarker].self, forKey: .projectReadMarkers)
      ?? [:]
  }
}

private struct StoredMCPState: Codable, Sendable {
  var receipts: [UUID: String] = [:]
}

public struct MCPApplyResult: Sendable {
  public var library: Library
  public var replayed: Bool
}

public struct SyncLibraryState: Sendable {
  public var libraryID: UUID
  public var sequence: UInt64
  public var library: Library
  public var taskReadMarkers: [UUID: TaskChangeReadMarker]
  public var projectReadMarkers: [UUID: TaskChangeReadMarker]
}

/// One durable row per entity; mutations update only changed rows in a single SQLite transaction.
/// All decoding and persistence runs on this actor, not the main UI executor.
public actor LibraryRepository {
  private let container: ModelContainer
  private var cached: Library?
  private var syncState: StoredSyncState?
  private var mcpState: StoredMCPState?
  private let legacyURL: URL?
  private let recoverActiveRuns: Bool
  public init(
    url: URL? = nil, legacyURL: URL? = nil, inMemory: Bool = false,
    recoverActiveRuns: Bool = true
  ) throws {
    let schema = Schema(versionedSchema: StageSchemaV1.self)
    let config: ModelConfiguration
    if let url {
      config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    } else {
      config = ModelConfiguration(
        schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
    }
    container = try ModelContainer(
      for: schema, migrationPlan: StageMigrationPlan.self, configurations: [config])
    self.legacyURL = legacyURL
    self.recoverActiveRuns = recoverActiveRuns
  }

  public func load() throws -> Library {
    if let cached { return cached }
    let context = ModelContext(container)
    let entries = try context.fetch(FetchDescriptor<StageSchemaV1.Entry>())
    var library = Library()
    let decoder = JSONDecoder()
    for entry in entries {
      switch entry.kind {
      case "project": library.projects.append(try decoder.decode(Project.self, from: entry.payload))
      case "task": library.tasks.append(try decoder.decode(WorkItem.self, from: entry.payload))
      case "run": library.runs.append(try decoder.decode(AgentRun.self, from: entry.payload))
      case "activity":
        library.activity.append(try decoder.decode(Activity.self, from: entry.payload))
      case "metadata":
        if entry.key == "sync-state" {
          syncState = try decoder.decode(StoredSyncState.self, from: entry.payload)
        } else if entry.key == "mcp-state" {
          mcpState = try decoder.decode(StoredMCPState.self, from: entry.payload)
        }
      default:
        throw BoardError.invalid("Unknown record in the library. Your data has not been changed.")
      }
    }
    if entries.isEmpty {
      if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) {
        library = try LegacyImport.decode(Data(contentsOf: legacyURL))
        let backup = legacyURL.appendingPathExtension("pre-v2-backup")
        if !FileManager.default.fileExists(atPath: backup.path) {
          try FileManager.default.copyItem(at: legacyURL, to: backup)
        }
      }
      try persist(library)
    }
    library.projects.sort { $0.createdAt < $1.createdAt }
    library.activity.sort { $0.date < $1.date }
    // Never silently restart a paid/side-effectful operation after a crash.
    var recovered = false
    if recoverActiveRuns {
      for index in library.runs.indices
      where [.running, .needsInput, .queued].contains(library.runs[index].status) {
        if library.runs[index].source == .codexDesktop {
          library.runs[index].status = .stale
          library.runs[index].liveState = .stale
          library.runs[index].summary =
            "Codex Desktop state is unverified after restart. Refresh or relink to confirm it."
        } else {
          library.runs[index].status = .interrupted
          library.runs[index].summary = "Runner stopped. Review the session, then retry explicitly."
        }
        recovered = true
      }
    }
    try library.validate()
    if syncState == nil { syncState = StoredSyncState() }
    if recovered { syncState?.sequence &+= 1 }
    if recovered || entries.isEmpty || syncState != nil {
      try persist(library, syncState: syncState)
    }
    cached = library
    return library
  }

  /// Explicitly rereads the current persisted library without crash recovery or writes.
  /// This is used by user-triggered refresh actions when another repository client may
  /// have changed the shared SwiftData store since this actor last loaded it.
  public func refresh() throws -> Library {
    let context = ModelContext(container)
    let entries = try context.fetch(FetchDescriptor<StageSchemaV1.Entry>())
    var library = Library()
    let decoder = JSONDecoder()
    var refreshedSyncState: StoredSyncState?
    var refreshedMCPState: StoredMCPState?
    for entry in entries {
      switch entry.kind {
      case "project": library.projects.append(try decoder.decode(Project.self, from: entry.payload))
      case "task": library.tasks.append(try decoder.decode(WorkItem.self, from: entry.payload))
      case "run": library.runs.append(try decoder.decode(AgentRun.self, from: entry.payload))
      case "activity":
        library.activity.append(try decoder.decode(Activity.self, from: entry.payload))
      case "metadata":
        if entry.key == "sync-state" {
          refreshedSyncState = try decoder.decode(StoredSyncState.self, from: entry.payload)
        } else if entry.key == "mcp-state" {
          refreshedMCPState = try decoder.decode(StoredMCPState.self, from: entry.payload)
        }
      default:
        throw BoardError.invalid("Unknown record in the library. Your data has not been changed.")
      }
    }
    library.projects.sort { $0.createdAt < $1.createdAt }
    library.activity.sort { $0.date < $1.date }
    try library.validate()
    cached = library
    syncState = refreshedSyncState
    mcpState = refreshedMCPState
    return library
  }

  public func apply(_ command: Mutation) throws -> Library {
    let current = try load()
    let library = try BoardReducer.apply(command, to: current)
    var nextSyncState = syncState ?? StoredSyncState()
    Self.clearPhoneVersions(forChangedTasksFrom: current, to: library, in: &nextSyncState)
    nextSyncState.sequence &+= 1
    try persist(library, syncState: nextSyncState)
    Self.removeDeletedAttachmentFiles(from: current, keeping: library)
    cached = library
    syncState = nextSyncState
    return library
  }

  /// Commits a local MCP mutation and its replay receipt in the same SwiftData save.
  public func applyMCP(
    _ command: Mutation, operationID: UUID, fingerprint: String
  ) throws -> MCPApplyResult {
    let current = try load()
    var state = mcpState ?? StoredMCPState()
    if let prior = state.receipts[operationID] {
      guard prior == fingerprint else {
        throw BoardError.invalid("This operation ID was already used for different content.")
      }
      return MCPApplyResult(library: current, replayed: true)
    }
    let updated = try BoardReducer.apply(command, to: current)
    state.receipts[operationID] = fingerprint
    if state.receipts.count > 2_000 {
      // Stable deterministic eviction bounds metadata growth without exposing the map order.
      for key in state.receipts.keys.sorted(by: { $0.uuidString < $1.uuidString })
        .prefix(state.receipts.count - 2_000)
      {
        state.receipts.removeValue(forKey: key)
      }
    }
    var nextSyncState = syncState ?? StoredSyncState()
    Self.clearPhoneVersions(forChangedTasksFrom: current, to: updated, in: &nextSyncState)
    nextSyncState.sequence &+= 1
    try persist(updated, syncState: nextSyncState, mcpState: state)
    Self.removeDeletedAttachmentFiles(from: current, keeping: updated)
    cached = updated
    syncState = nextSyncState
    mcpState = state
    return MCPApplyResult(library: updated, replayed: false)
  }

  public func syncStateSnapshot() throws -> SyncLibraryState {
    let library = try load()
    let state = syncState ?? StoredSyncState()
    return SyncLibraryState(
      libraryID: state.libraryID, sequence: state.sequence, library: library,
      taskReadMarkers: state.taskReadMarkers, projectReadMarkers: state.projectReadMarkers)
  }

  /// Persists a Mac-side read action in the same durable metadata used by phone snapshots.
  public func acknowledgeTaskRead(_ taskID: UUID, marker: TaskChangeReadMarker) throws {
    var state = syncState ?? StoredSyncState()
    let current = try load()
    guard current.tasks.contains(where: { $0.id == taskID }),
      current.activity.contains(where: {
        $0.taskID == taskID && $0.taskChange != nil && Self.marker($0, isValidFor: marker)
      })
    else { return }
    state.taskReadMarkers[taskID] = .later(state.taskReadMarkers[taskID], marker)
    state.sequence &+= 1
    try persist(current, syncState: state)
    syncState = state
  }

  public func acknowledgeProjectRead(_ projectID: UUID, marker: TaskChangeReadMarker) throws {
    var state = syncState ?? StoredSyncState()
    let current = try load()
    guard current.projects.contains(where: { $0.id == projectID }),
      current.activity.contains(where: {
        $0.projectID == projectID && $0.taskChange != nil && Self.marker($0, isValidFor: marker)
      })
    else { return }
    state.projectReadMarkers[projectID] = .later(state.projectReadMarkers[projectID], marker)
    state.sequence &+= 1
    try persist(current, syncState: state)
    syncState = state
  }

  /// Replica application persists downloaded Mac state without performing local-run recovery.
  public func replaceReplica(
    _ library: Library, libraryID: UUID, sequence: UInt64,
    taskReadMarkers: [UUID: TaskChangeReadMarker] = [:],
    projectReadMarkers: [UUID: TaskChangeReadMarker] = [:]
  ) throws {
    guard !recoverActiveRuns else {
      throw BoardError.invalid("Replica data requires a non-recovering repository.")
    }
    try library.validate()
    let existing = try load()
    if let currentState = syncState, currentState.libraryID != libraryID,
      !existing.projects.isEmpty
    {
      throw BoardError.invalid("This replica belongs to a different Mac library.")
    }
    var nextState = syncState ?? StoredSyncState()
    nextState.libraryID = libraryID
    nextState.sequence = sequence
    nextState.taskReadMarkers = taskReadMarkers
    nextState.projectReadMarkers = projectReadMarkers
    try persist(library, syncState: nextState)
    Self.removeDeletedAttachmentFiles(from: existing, keeping: library)
    cached = library
    syncState = nextState
  }

  /// Validates and commits an idempotent phone command with its receipt in the same store save.
  public func applyRemote(_ envelope: SyncEnvelope) throws -> SyncCommandResult {
    let current = try load()
    guard var state = syncState else { throw BoardError.invalid("Sync metadata is unavailable.") }
    guard envelope.libraryID == state.libraryID else {
      return .rejected(message: "This phone is paired with a different Mac library.")
    }
    guard envelope.version == SyncProtocol.version else {
      return .rejected(message: "This phone uses an unsupported synchronization version.")
    }
    let digest = try Self.digest(envelope)
    if let receipt = state.receipts[envelope.operationID] {
      guard receipt.payloadDigest == digest, receipt.deviceID == envelope.deviceID,
        receipt.clientSequence == envelope.clientSequence
      else {
        return .rejected(message: "This operation ID was already used for different content.")
      }
      let snapshot = SyncSnapshot(
        libraryID: state.libraryID, sequence: state.sequence, library: current,
        taskReadMarkers: state.taskReadMarkers, projectReadMarkers: state.projectReadMarkers)
      return receipt.superseded
        ? .superseded(sequence: receipt.sequence, current: snapshot)
        : .applied(sequence: receipt.sequence, snapshot: snapshot)
    }
    let highWater = state.deviceHighWater[envelope.deviceID, default: 0]
    guard envelope.clientSequence > highWater else {
      return .rejected(
        message: "The phone’s queued operation sequence is out of date. Refresh and retry.")
    }
    if case .acknowledgeTaskChanges(let taskID, let marker) = envelope.command {
      return try applyReadAcknowledgment(
        envelope, digest: digest, current: current, state: &state,
        taskID: taskID, projectID: nil, marker: marker)
    }
    if case .acknowledgeProjectChanges(let projectID, let marker) = envelope.command {
      return try applyReadAcknowledgment(
        envelope, digest: digest, current: current, state: &state,
        taskID: nil, projectID: projectID, marker: marker)
    }
    do {
      var commandEnvelope = envelope
      let mutation = try SyncCommandValidator.mutation(for: commandEnvelope, in: current)
      var updated: Library
      do {
        updated = try BoardReducer.apply(mutation, to: current)
      } catch BoardError.conflict {
        guard let taskID = Self.lastWriteWinsTaskID(in: envelope.command),
          let task = current.tasks.first(where: { $0.id == taskID })
        else {
          return .conflict(current: Self.snapshot(for: current, state: state))
        }
        let incomingTime = min(envelope.editedAt, Date.now.addingTimeInterval(300))
        let currentPhoneVersion = state.phoneTaskVersions[taskID]
        let incomingWins: Bool
        if incomingTime != task.updatedAt {
          incomingWins = incomingTime > task.updatedAt
        } else if let currentPhoneVersion, currentPhoneVersion.editedAt == incomingTime {
          let incomingDevice = envelope.deviceID.uuidString
          let currentDevice = currentPhoneVersion.deviceID.uuidString
          incomingWins =
            incomingDevice == currentDevice
            ? envelope.clientSequence > currentPhoneVersion.clientSequence
            : incomingDevice > currentDevice
        } else {
          // Exact timestamp ties favor the Mac-authored state deterministically.
          incomingWins = false
        }
        if !incomingWins {
          return try persistSuperseded(envelope, digest: digest, current: current, state: &state)
        }
        commandEnvelope.expectedRevision = task.revision
        var resolved: Library
        do {
          let rebased = try SyncCommandValidator.mutation(for: commandEnvelope, in: current)
          resolved = try BoardReducer.apply(rebased, to: current)
        } catch {
          return try persistSuperseded(envelope, digest: digest, current: current, state: &state)
        }
        if let index = resolved.tasks.firstIndex(where: { $0.id == taskID }) {
          resolved.tasks[index].updatedAt = incomingTime
        }
        state.phoneTaskVersions[taskID] = StoredTaskEditVersion(
          editedAt: incomingTime, deviceID: envelope.deviceID,
          clientSequence: envelope.clientSequence)
        let sequence = state.sequence
        try persist(resolved, syncState: state)
        Self.removeDeletedAttachmentFiles(from: current, keeping: resolved)
        cached = resolved
        syncState = state
        return .applied(
          sequence: sequence,
          snapshot: SyncSnapshot(
            libraryID: state.libraryID, sequence: sequence, library: resolved,
            taskReadMarkers: state.taskReadMarkers, projectReadMarkers: state.projectReadMarkers))
      }
      if let taskID = Self.lastWriteWinsTaskID(in: envelope.command),
        let index = updated.tasks.firstIndex(where: { $0.id == taskID }),
        envelope.editedAt > .distantPast
      {
        let incomingTime = min(envelope.editedAt, Date.now.addingTimeInterval(300))
        updated.tasks[index].updatedAt = incomingTime
        state.phoneTaskVersions[taskID] = StoredTaskEditVersion(
          editedAt: incomingTime, deviceID: envelope.deviceID,
          clientSequence: envelope.clientSequence)
      }
      state.sequence &+= 1
      state.deviceHighWater[envelope.deviceID] = envelope.clientSequence
      state.receipts[envelope.operationID] = StoredSyncReceipt(
        payloadDigest: digest, sequence: state.sequence, deviceID: envelope.deviceID,
        clientSequence: envelope.clientSequence)
      try Self.trimReceipts(in: &state)
      try persist(updated, syncState: state)
      Self.removeDeletedAttachmentFiles(from: current, keeping: updated)
      cached = updated
      syncState = state
      return .applied(
        sequence: state.sequence,
        snapshot: SyncSnapshot(
          libraryID: state.libraryID, sequence: state.sequence, library: updated,
          taskReadMarkers: state.taskReadMarkers, projectReadMarkers: state.projectReadMarkers))
    } catch BoardError.conflict {
      return .conflict(current: Self.snapshot(for: current, state: state))
    } catch BoardError.busy {
      return try persistSuperseded(envelope, digest: digest, current: current, state: &state)
    } catch BoardError.missing {
      return try persistSuperseded(envelope, digest: digest, current: current, state: &state)
    } catch {
      return .rejected(message: error.localizedDescription)
    }
  }

  private func applyReadAcknowledgment(
    _ envelope: SyncEnvelope, digest: String, current: Library,
    state: inout StoredSyncState, taskID: UUID?, projectID: UUID?, marker: TaskChangeReadMarker
  ) throws -> SyncCommandResult {
    let validScope: Bool
    if let taskID {
      validScope =
        current.tasks.contains(where: { $0.id == taskID })
        && current.activity.contains(where: {
          $0.taskID == taskID && $0.taskChange != nil && Self.marker($0, isValidFor: marker)
        })
    } else if let projectID {
      validScope =
        current.projects.contains(where: { $0.id == projectID })
        && current.activity.contains(where: {
          $0.projectID == projectID && $0.taskChange != nil && Self.marker($0, isValidFor: marker)
        })
    } else {
      validScope = false
    }
    guard validScope else {
      return .rejected(message: "The unread change is no longer available. Refresh and retry.")
    }
    if let taskID {
      state.taskReadMarkers[taskID] = .later(state.taskReadMarkers[taskID], marker)
    } else if let projectID {
      state.projectReadMarkers[projectID] = .later(state.projectReadMarkers[projectID], marker)
    }
    state.sequence &+= 1
    state.deviceHighWater[envelope.deviceID] = envelope.clientSequence
    state.receipts[envelope.operationID] = StoredSyncReceipt(
      payloadDigest: digest, sequence: state.sequence, deviceID: envelope.deviceID,
      clientSequence: envelope.clientSequence)
    try Self.trimReceipts(in: &state)
    try persist(current, syncState: state)
    cached = current
    syncState = state
    return .applied(
      sequence: state.sequence,
      snapshot: SyncSnapshot(
        libraryID: state.libraryID, sequence: state.sequence, library: current,
        taskReadMarkers: state.taskReadMarkers, projectReadMarkers: state.projectReadMarkers))
  }

  private static func marker(_ activity: Activity, isValidFor marker: TaskChangeReadMarker) -> Bool
  {
    if let activityID = marker.activityID {
      return activity.id == activityID && activity.date == marker.date
    }
    return activity.date <= marker.date
  }

  private static func snapshot(for library: Library, state: StoredSyncState) -> SyncSnapshot {
    SyncSnapshot(
      libraryID: state.libraryID, sequence: state.sequence, library: library,
      taskReadMarkers: state.taskReadMarkers, projectReadMarkers: state.projectReadMarkers)
  }

  private func persistSuperseded(
    _ envelope: SyncEnvelope, digest: String, current: Library,
    state: inout StoredSyncState
  ) throws -> SyncCommandResult {
    state.sequence &+= 1
    state.deviceHighWater[envelope.deviceID] = max(
      state.deviceHighWater[envelope.deviceID, default: 0], envelope.clientSequence)
    state.receipts[envelope.operationID] = StoredSyncReceipt(
      payloadDigest: digest, sequence: state.sequence, deviceID: envelope.deviceID,
      clientSequence: envelope.clientSequence, superseded: true)
    try Self.trimReceipts(in: &state)
    try persist(current, syncState: state)
    cached = current
    syncState = state
    return .superseded(
      sequence: state.sequence,
      current: SyncSnapshot(
        libraryID: state.libraryID, sequence: state.sequence, library: current,
        taskReadMarkers: state.taskReadMarkers, projectReadMarkers: state.projectReadMarkers))
  }

  private static func lastWriteWinsTaskID(in command: SyncCommand) -> UUID? {
    switch command {
    case .editTask(let id, _, _):
      id
    default: nil
    }
  }

  private static func clearPhoneVersions(
    forChangedTasksFrom old: Library, to new: Library, in state: inout StoredSyncState
  ) {
    let changed = Set(
      old.tasks.filter { task in
        new.tasks.first(where: { $0.id == task.id })?.revision != task.revision
      }.map(\.id))
    for id in changed { state.phoneTaskVersions.removeValue(forKey: id) }
  }

  private static func trimReceipts(in state: inout StoredSyncState) throws {
    if state.receipts.count > 2_000 {
      let stale = state.receipts.sorted { $0.value.sequence < $1.value.sequence }
        .prefix(state.receipts.count - 2_000).map(\.key)
      for id in stale { state.receipts.removeValue(forKey: id) }
    }
  }

  public func export() throws -> Data {
    try BackupArchive.encode(load())
  }

  public func importLibrary(_ data: Data, replaceEmptyOnly: Bool = true) throws -> Library {
    let existing = try load()
    guard !replaceEmptyOnly || existing.projects.isEmpty else {
      throw BoardError.invalid(
        "Restore requires an empty library. Your existing projects were not changed.")
    }
    let contents = try BackupArchive.decode(data)
    var imported = contents.library
    var writtenAssets: [UUID] = []
    do {
      for taskIndex in imported.tasks.indices {
        for attachmentIndex in imported.tasks[taskIndex].attachments.indices {
          let attachment = imported.tasks[taskIndex].attachments[attachmentIndex]
          guard let bytes = contents.assets[attachment.id] else {
            throw BoardError.invalid("The backup is missing an attached image.")
          }
          _ = try TaskAttachmentFiles.save(
            bytes, id: attachment.id, displayName: attachment.displayName,
            mediaType: attachment.mediaType)
          writtenAssets.append(attachment.id)
          imported.tasks[taskIndex].attachments[attachmentIndex].transferState = .available
        }
      }
    } catch {
      for id in writtenAssets { try? TaskAttachmentFiles.remove(id) }
      throw error
    }
    try imported.validate()
    for i in imported.runs.indices where imported.runs[i].status.isActive {
      imported.runs[i].status = .interrupted
    }
    for i in imported.projects.indices { imported.projects[i].automationEnabled = false }
    var nextSyncState = StoredSyncState()
    nextSyncState.sequence = (syncState?.sequence ?? 0) &+ 1
    do { try persist(imported, syncState: nextSyncState) } catch {
      for id in writtenAssets { try? TaskAttachmentFiles.remove(id) }
      throw error
    }
    cached = imported
    syncState = nextSyncState
    return imported
  }

  private static func digest(_ envelope: SyncEnvelope) throws -> String {
    let data = try JSONEncoder.syncEncoder.encode(envelope)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func removeDeletedAttachmentFiles(from old: Library, keeping new: Library) {
    let retained = Set(new.tasks.flatMap(\.attachments).map(\.id))
    let removed = Set(old.tasks.flatMap(\.attachments).map(\.id)).subtracting(retained)
    for id in removed { try? TaskAttachmentFiles.remove(id) }
  }

  private func persist(
    _ library: Library, syncState: StoredSyncState? = nil, mcpState: StoredMCPState? = nil
  ) throws {
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    func fetch(_ key: String) throws -> StageSchemaV1.Entry? {
      var descriptor = FetchDescriptor<StageSchemaV1.Entry>(predicate: #Predicate { $0.key == key })
      descriptor.fetchLimit = 1
      return try context.fetch(descriptor).first
    }
    func upsert<T: Encodable>(_ value: T, key: String, kind: String, project: UUID?) throws {
      let data = try encoder.encode(value)
      if let old = try fetch(key) {
        if old.payload != data {
          old.payload = data
          old.projectID = project
        }
      } else {
        context.insert(StageSchemaV1.Entry(key: key, kind: kind, projectID: project, payload: data))
      }
    }
    func sync<T: Encodable & Equatable & Identifiable>(
      _ values: [T], previous: [T], prefix: String, kind: String, project: (T) -> UUID?
    ) throws where T.ID == UUID {
      let before = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
      let retained = Set(values.map(\.id))
      for value in values where before[value.id] != value {
        try upsert(value, key: prefix + value.id.uuidString, kind: kind, project: project(value))
      }
      for value in previous where !retained.contains(value.id) {
        if let entry = try fetch(prefix + value.id.uuidString) { context.delete(entry) }
      }
    }
    if cached == nil { try upsert(1, key: "schema", kind: "metadata", project: nil) }
    if let state = syncState ?? self.syncState {
      try upsert(state, key: "sync-state", kind: "metadata", project: nil)
    }
    if let state = mcpState ?? self.mcpState {
      try upsert(state, key: "mcp-state", kind: "metadata", project: nil)
    }
    try sync(
      library.projects, previous: cached?.projects ?? [], prefix: "p:", kind: "project",
      project: { $0.id })
    try sync(
      library.tasks, previous: cached?.tasks ?? [], prefix: "t:", kind: "task",
      project: { $0.projectID })
    try sync(
      library.runs, previous: cached?.runs ?? [], prefix: "r:", kind: "run",
      project: { $0.projectID })
    try sync(
      library.activity, previous: cached?.activity ?? [], prefix: "a:", kind: "activity",
      project: { $0.projectID })
    try context.save()
  }
}
