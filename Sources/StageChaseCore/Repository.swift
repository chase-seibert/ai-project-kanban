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

/// One durable row per entity; mutations update only changed rows in a single SQLite transaction.
/// All decoding and persistence runs on this actor, not the main UI executor.
public actor LibraryRepository {
  private let container: ModelContainer
  private var cached: Library?
  private let legacyURL: URL?
  public init(url: URL? = nil, legacyURL: URL? = nil, inMemory: Bool = false) throws {
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
      case "metadata": break
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
    for index in library.runs.indices
    where [.running, .needsInput, .queued].contains(library.runs[index].status) {
      library.runs[index].status = .interrupted
      library.runs[index].summary = "Runner stopped. Review the session, then retry explicitly."
      recovered = true
    }
    try library.validate()
    if recovered { try persist(library) }
    cached = library
    return library
  }

  public func apply(_ command: Mutation) throws -> Library {
    let library = try BoardReducer.apply(command, to: load())
    try persist(library)
    cached = library
    return library
  }

  public func export() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(load())
  }

  public func importLibrary(_ data: Data, replaceEmptyOnly: Bool = true) throws -> Library {
    let existing = try load()
    guard !replaceEmptyOnly || existing.projects.isEmpty else {
      throw BoardError.invalid(
        "Restore requires an empty library. Your existing projects were not changed.")
    }
    var imported = try JSONDecoder().decode(Library.self, from: data)
    try imported.validate()
    for i in imported.runs.indices where imported.runs[i].status.isActive {
      imported.runs[i].status = .interrupted
    }
    for i in imported.projects.indices { imported.projects[i].automationEnabled = false }
    try persist(imported)
    cached = imported
    return imported
  }

  private func persist(_ library: Library) throws {
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
