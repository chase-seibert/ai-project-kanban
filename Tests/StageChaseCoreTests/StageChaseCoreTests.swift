import Foundation
import Testing

@testable import StageChaseCore

private let fixtureModelConfiguration = ResolvedCodexConfiguration(
  selection: .latestLuna, modelID: "gpt-6.10-luna", effort: "high", scope: .global)

@Test func planHandoffPromptUsesCanonicalPathAndPlanOnlyMCPWorkflow() throws {
  let project = Project(name: "Prompt project", directory: "/tmp/missing-plan-project")
  let task = WorkItem(projectID: project.id, title: "Add a plan action")
  var notedTask = task
  notedTask.notes = "Keep the Mac-only boundary."
  let format = "Start with user stories, then risks."

  let prompt = PlanHandoffPrompt.make(for: notedTask, project: project, formatPrompt: format)

  let expectedPlanPath = WorkItem.canonicalPlanPath(for: task.id, title: task.title)
  #expect(PlanHandoffPrompt.planPath(for: notedTask) == expectedPlanPath)
  #expect(prompt.hasPrefix("Task: \(task.title)\n\n"))
  #expect(prompt.contains(expectedPlanPath))
  #expect(prompt.contains("Project ID (`project_id`): \(project.id.uuidString.lowercased())"))
  #expect(prompt.contains("Task ID (`task_id`): \(task.id.uuidString.lowercased())"))
  #expect(prompt.contains("Start with user stories, then risks."))
  #expect(prompt.contains("attach_task_plan"))
  #expect(prompt.contains("move_task` to `planned`"))
  #expect(prompt.contains("Keep the task incomplete"))
  #expect(!prompt.contains("set_task_completed"))
  #expect(!prompt.contains("Execute this existing task"))
  #expect(!prompt.contains("implementation work"))
}

@Test func canonicalPlanPathUsesReadableSafeUniqueTaskSlugs() {
  let id = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
  let path = WorkItem.canonicalPlanPath(for: id, title: "Add Export: CSV & JSON")
  #expect(path == "to-do/add-export-csv-json-12345678-1234-1234-1234-123456789abc.md")
  #expect(WorkItem.canonicalPlanPath(for: id, title: "Résumé / 東京 🚀").hasPrefix("to-do/resume-東京-"))
  #expect(
    WorkItem.canonicalPlanPath(for: id, title: "!!!")
      == "to-do/task-12345678-1234-1234-1234-123456789abc.md")
  let longTitle = String(repeating: "A", count: 200)
  #expect(WorkItem.canonicalPlanPath(for: id, title: longTitle).count < 120)

  let otherID = UUID(uuidString: "87654321-4321-4321-4321-cba987654321")!
  #expect(
    WorkItem.canonicalPlanPath(for: id, title: "Same title")
      != WorkItem.canonicalPlanPath(for: otherID, title: "Same title"))
}

@Test func planHandoffPromptPreservesReadableAndUnreadableAttachedPaths() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChasePlanPrompt-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let project = Project(name: "Prompt project", directory: root.path)
  var task = WorkItem(projectID: project.id, title: "Revise my plan")
  task.planPath = "custom/plans/my-plan.md"
  let planURL = root.appendingPathComponent(task.planPath!)
  try FileManager.default.createDirectory(
    at: planURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  try "## Existing plan\n\nKeep the user context.".write(
    to: planURL, atomically: true, encoding: .utf8)

  #expect(PlanHandoffPrompt.hasReadablePlan(for: task, project: project))
  let revisionPrompt = PlanHandoffPrompt.make(
    for: task, project: project, formatPrompt: "Use concise sections.")
  #expect(PlanHandoffPrompt.planPath(for: task) == "custom/plans/my-plan.md")
  #expect(revisionPrompt.contains("Revise the existing plan"))
  #expect(revisionPrompt.contains("custom/plans/my-plan.md"))
  #expect(revisionPrompt.contains("Use concise sections."))

  try FileManager.default.removeItem(at: planURL)
  #expect(!PlanHandoffPrompt.hasReadablePlan(for: task, project: project))
  let unavailablePrompt = PlanHandoffPrompt.make(for: task, project: project, formatPrompt: "")
  #expect(unavailablePrompt.contains("Create a plan at the target path"))
  #expect(unavailablePrompt.contains("custom/plans/my-plan.md"))
  #expect(unavailablePrompt.contains("No custom plan-format preference is set."))
}

@Test func creatingProjectsNeverEditsExistingProject() throws {
  let a = Project(name: "First")
  let b = Project(name: "Second")
  var library = try BoardReducer.apply(.createProject(a), to: Library())
  library = try BoardReducer.apply(.createProject(b), to: library)
  #expect(library.projects == [a, b])
  var edited = b
  edited.name = "Renamed"
  library = try BoardReducer.apply(.editProject(edited), to: library)
  #expect(library.projects[0] == a)
  #expect(library.projects[1].name == "Renamed")
}

@Test func projectWorktreePreferenceDefaultsOffAndSurvivesCoding() throws {
  let legacy = Data(
    #"{"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","directory":"/tmp/legacy","automationEnabled":true,"createdAt":0}"#
      .utf8)
  let decoded = try JSONDecoder().decode(Project.self, from: legacy)
  #expect(!decoded.usesWorktrees)
  #expect(!Project(name: "New").usesWorktrees)

  var enabled = decoded
  enabled.usesWorktrees = true
  let roundTrip = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(enabled))
  #expect(roundTrip == enabled)
}

@Test func deployedRevisionIsOptionalBackwardCompatibleProjectData() throws {
  let legacy = Data(
    #"{"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","directory":"/tmp/legacy","createdAt":0}"#
      .utf8)
  let decoded = try JSONDecoder().decode(Project.self, from: legacy)
  #expect(decoded.deployedCommitHash == nil)
  #expect(decoded.deployedAt == nil)

  var deployed = decoded
  deployed.deployedCommitHash = String(repeating: "a", count: 40)
  deployed.deployedAt = Date(timeIntervalSince1970: 1_790_000_000)
  let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(deployed))
  #expect(restored == deployed)
}

@Test func syncMessagesAreAuthenticatedEncryptedAndBounded() throws {
  let key = SyncCrypto.randomSecret()
  let task = WorkItem(projectID: UUID(), title: "Keep this private")
  let encoded = try SyncCrypto.seal(task, key: key)
  #expect(!String(decoding: encoded, as: UTF8.self).contains(task.title))
  let decoded = try SyncCrypto.open(encoded, key: key, as: WorkItem.self)
  #expect(decoded.id == task.id)
  #expect(decoded.projectID == task.projectID)
  #expect(decoded.title == task.title)

  var tampered = encoded
  tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
  #expect(throws: (any Error).self) {
    try SyncCrypto.open(tampered, key: key, as: WorkItem.self)
  }
  #expect(throws: (any Error).self) {
    try SyncCrypto.open(encoded, key: SyncCrypto.randomSecret(), as: WorkItem.self)
  }
}

@Test func syncSnapshotPreservesSharedStateButOmitsMacOnlyConfiguration() throws {
  var project = Project(name: "Shared", directory: "/Users/test/private-repo")
  project.automationEnabled = true
  project.usesWorktrees = true
  project.modelOverride = CodexModelConfiguration(selection: .model("private-model"))
  var task = WorkItem(projectID: project.id, title: "Task", stage: .planned)
  task.planPath = "/Users/test/private-repo/plan.md"
  task.notes = "Keep the details"
  let run = AgentRun(task: task, kind: .planning)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.runs = [run]
  library.activity = [Activity("Wrote /Users/test/private-repo/plan.md")]

  let snapshot = SyncSnapshot(libraryID: UUID(), sequence: 7, library: library)
  let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
  #expect(!json.contains("private-repo"))
  #expect(!json.contains("planPath"))
  let replica = try snapshot.replica()
  #expect(replica.projects[0].id == project.id)
  #expect(replica.projects[0].automationEnabled)
  #expect(replica.projects[0].usesWorktrees)
  #expect(replica.projects[0].modelOverride == project.modelOverride)
  #expect(replica.tasks[0].notes == task.notes)
  #expect(replica.tasks[0].planPath == nil)
  #expect(replica.runs[0].status == run.status)
}

@Test func remoteCommandsAreTransactionalRevisionCheckedAndIdempotent() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Shared")
  _ = try await repository.apply(.createProject(project))
  let initial = try await repository.syncStateSnapshot()
  let deviceID = UUID()
  let taskID = UUID()
  let create = SyncEnvelope(
    libraryID: initial.libraryID, deviceID: deviceID, clientSequence: 1,
    command: .createTask(
      id: taskID, projectID: project.id, title: "Phone task", notes: "", stage: .inbox))

  guard
    case .applied(let firstSequence, let firstSnapshot) = try await repository.applyRemote(create)
  else {
    Issue.record("Expected phone task command to be applied")
    return
  }
  #expect(firstSequence == initial.sequence + 1)
  #expect(firstSnapshot.tasks.map(\.id) == [taskID])

  guard case .applied(let replaySequence, _) = try await repository.applyRemote(create)
  else {
    Issue.record("Expected an identical retry to return its original receipt")
    return
  }
  #expect(replaySequence == firstSequence)

  let conflictingReplay = SyncEnvelope(
    libraryID: initial.libraryID, deviceID: deviceID, clientSequence: 1,
    operationID: create.operationID,
    command: .createTask(
      id: taskID, projectID: project.id, title: "Different content", notes: "", stage: .inbox))
  guard case .rejected = try await repository.applyRemote(conflictingReplay)
  else {
    Issue.record("An operation ID must not be reused with different content")
    return
  }

  let edit = SyncEnvelope(
    libraryID: initial.libraryID, deviceID: deviceID, clientSequence: 2,
    expectedRevision: 0, command: .editTask(id: taskID, title: "Edited", notes: "saved"))
  guard case .applied(_, let edited) = try await repository.applyRemote(edit)
  else {
    Issue.record("Expected revision-matched edit to be applied")
    return
  }
  #expect(edited.tasks[0].title == "Edited")

  let stale = SyncEnvelope(
    libraryID: initial.libraryID, deviceID: deviceID, clientSequence: 3,
    expectedRevision: 0, command: .editTask(id: taskID, title: "Stale", notes: ""))
  guard case .conflict = try await repository.applyRemote(stale)
  else {
    Issue.record("Expected stale revision to report a conflict")
    return
  }
  let persisted = try await repository.syncStateSnapshot()
  #expect(persisted.library.tasks[0].title == "Edited")
}

@Test func syncFramesAreLengthBoundedAndRejectMalformedMessages() throws {
  let request = SyncWireRequest.pairStart(Data([1, 2, 3]))
  let frame = try SyncFrame.encode(request)
  #expect(try SyncFrame.decode(frame, as: SyncWireRequest.self) == request)
  #expect(throws: BoardError.self) {
    try SyncFrame.decode(Data([0, 0, 0, 8, 1]), as: SyncWireRequest.self)
  }
  #expect(throws: BoardError.self) {
    try SyncFrame.encode(Data(repeating: 0, count: SyncProtocol.maximumMessageBytes + 1))
  }
}

@Test func syncNetworkJournalPersistsOnlyBoundedExchangeMetadata() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChaseSyncLog-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appendingPathComponent("events.json")
  var events: [SyncNetworkEvent] = []
  for index in 0..<(SyncNetworkEventJournal.maximumEvents + 5) {
    events = try SyncNetworkEventJournal.append(
      SyncNetworkEvent(
        direction: "Phone → Mac", remoteAddress: "192.168.1.2:47928",
        operation: "Refresh \(index)", requestBytes: 120, responseBytes: 340,
        outcome: "Response received", detail: "Metadata only", elapsedMilliseconds: 14),
      to: events, at: url)
  }
  let restored = try SyncNetworkEventJournal.load(from: url)
  #expect(restored.count == SyncNetworkEventJournal.maximumEvents)
  #expect(restored.first?.operation == "Refresh 204")
  #expect(restored.first?.detail == "Metadata only")
}

@Test func remoteCommandReceiptSurvivesRepositoryRestart() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChaseSync-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let storeURL = root.appendingPathComponent("Library.sqlite")
  var repository: LibraryRepository? = try LibraryRepository(url: storeURL)
  let project = Project(name: "Durable")
  _ = try await repository!.apply(.createProject(project))
  let state = try await repository!.syncStateSnapshot()
  let request = SyncEnvelope(
    libraryID: state.libraryID, deviceID: UUID(), clientSequence: 1,
    command: .createTask(
      id: UUID(), projectID: project.id, title: "Once", notes: "", stage: .inbox))
  guard case .applied(let originalSequence, _) = try await repository!.applyRemote(request)
  else {
    Issue.record("Expected first request to commit")
    return
  }
  repository = nil

  repository = try LibraryRepository(url: storeURL)
  guard case .applied(let replaySequence, let snapshot) = try await repository!.applyRemote(request)
  else {
    Issue.record("Expected durable retry receipt after restart")
    return
  }
  #expect(replaySequence == originalSequence)
  #expect(snapshot.tasks.count == 1)
  repository = nil
}

@Test func repositoryRefreshReadsCurrentStateFromAnotherRepositoryClient() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChaseRefresh-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let storeURL = root.appendingPathComponent("Library.sqlite")
  let boardRepository = try LibraryRepository(url: storeURL)
  let externalRepository = try LibraryRepository(url: storeURL)
  let project = Project(name: "Refresh fixture")
  _ = try await boardRepository.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Before refresh")
  _ = try await boardRepository.apply(.createTask(task))
  #expect(try await externalRepository.load().tasks.first?.title == "Before refresh")

  var updated = task
  updated.title = "After refresh"
  _ = try await boardRepository.apply(.editTask(updated, expectedRevision: task.revision))
  #expect(try await externalRepository.load().tasks.first?.title == "Before refresh")

  let refreshed = try await externalRepository.refresh()
  #expect(refreshed.tasks.first?.title == "After refresh")
  #expect(refreshed.tasks.first?.revision == task.revision + 1)
  #expect(refreshed.tasks.first?.stage == task.stage)
  #expect(refreshed.tasks.first?.completed == task.completed)
  #expect(refreshed.runs.isEmpty)
}

@Test func mcpMutationReceiptIsAtomicDurableAndRejectsOperationReuse() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChaseMCP-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let storeURL = root.appendingPathComponent("Library.sqlite")
  var repository: LibraryRepository? = try LibraryRepository(url: storeURL)
  let project = Project(name: "MCP test")
  _ = try await repository!.apply(.createProject(project))
  let operationID = UUID()
  var task = WorkItem(projectID: project.id, title: "One MCP task")
  task.id = operationID
  let first = try await repository!.applyMCP(
    .createTask(task), operationID: operationID, fingerprint: "same-request")
  #expect(!first.replayed)
  #expect(first.library.tasks.count == 1)
  repository = nil

  repository = try LibraryRepository(url: storeURL)
  let replay = try await repository!.applyMCP(
    .createTask(task), operationID: operationID, fingerprint: "same-request")
  #expect(replay.replayed)
  #expect(replay.library.tasks.count == 1)
  await #expect(throws: (any Error).self) {
    try await repository!.applyMCP(
      .createTask(task), operationID: operationID, fingerprint: "changed-request")
  }
  repository = nil
}

@Test func mcpMoveDoesNotQueueCodexAndLatestUpdatePreservesBoardState() async throws {
  let repository = try LibraryRepository(inMemory: true)
  var project = Project(name: "MCP")
  project.directory = "/tmp/mcp-fixture"
  project.automationEnabled = true
  _ = try await repository.apply(.createProject(project))
  let createID = UUID()
  var task = WorkItem(projectID: project.id, title: "MCP acceptance")
  task.id = createID
  _ = try await repository.applyMCP(
    .createTask(task), operationID: createID, fingerprint: "create")

  let moveID = UUID()
  let moved = try await repository.applyMCP(
    .move(task.id, .implementation, expectedRevision: 0),
    operationID: moveID, fingerprint: "move")
  #expect(moved.library.tasks[0].stage == .implementation)
  #expect(moved.library.runs.isEmpty)

  let updateID = UUID()
  let updated = try await repository.applyMCP(
    .reportTaskUpdate(task.id, "Build is ready for review", expectedRevision: 1),
    operationID: updateID, fingerprint: "report")
  #expect(updated.library.tasks[0].stage == .implementation)
  #expect(!updated.library.tasks[0].completed)
  #expect(updated.library.tasks[0].latestCodexUpdate == "Build is ready for review")
  #expect(updated.library.tasks[0].revision == 2)
  #expect(updated.library.runs.isEmpty)
}

@Test func externalCodexRunBecomesStaleInsteadOfInterruptedAfterRestart() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChaseExternal-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let storeURL = root.appendingPathComponent("Library.sqlite")
  var repository: LibraryRepository? = try LibraryRepository(url: storeURL)
  let project = Project(name: "External")
  _ = try await repository!.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Desktop session")
  _ = try await repository!.apply(.createTask(task))
  var run = AgentRun(task: task, kind: .task)
  run.source = .codexDesktop
  run.status = .running
  _ = try await repository!.apply(.beginExternalRun(run))
  repository = nil

  repository = try LibraryRepository(url: storeURL)
  let restored = try await repository!.load()
  #expect(restored.runs.first?.status == .stale)
  #expect(restored.runs.first?.source == .codexDesktop)
  #expect(restored.runs.first?.summary.contains("unverified") == true)
  repository = nil
}

@Test func taskIsolationAndQuickCaptureInEveryStage() throws {
  let a = Project(name: "A")
  let b = Project(name: "B")
  var library = Library()
  library.projects = [a, b]
  for stage in WorkflowStage.allCases {
    library = try BoardReducer.apply(
      .createTask(WorkItem(projectID: a.id, title: stage.title, stage: stage)), to: library)
  }
  #expect(library.items(in: a.id).count == 5)
  #expect(library.items(in: b.id).isEmpty)
  #expect(library.runs.isEmpty)
}

@Test func movesAreRevisionCheckedAndIdempotent() throws {
  var project = Project(name: "A", directory: "/tmp/fixture")
  project.automationEnabled = true
  let task = WorkItem(projectID: project.id, title: "Plan it")
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library = try BoardReducer.apply(
    .move(task.id, .next, expectedRevision: 0, configuration: fixtureModelConfiguration),
    to: library)
  #expect(library.runs.count == 1)
  #expect(library.runs[0].status == .queued)
  let same = try BoardReducer.apply(.move(task.id, .next, expectedRevision: 1), to: library)
  #expect(same == library)
  library = try BoardReducer.apply(.move(task.id, .review, expectedRevision: 1), to: library)
  #expect(library.tasks[0].stage == .review)
  #expect(library.runs.count == 1)
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.move(task.id, .inbox, expectedRevision: 1), to: library)
  }
}

@Test func enablingAutomationDoesNotStartExistingTasks() throws {
  var project = Project(name: "A", directory: "/tmp/fixture")
  var library = Library()
  library.projects = [project]
  library.tasks = [WorkItem(projectID: project.id, title: "Existing", stage: .next)]
  project.automationEnabled = true
  library = try BoardReducer.apply(.editProject(project), to: library)
  #expect(library.runs.isEmpty)
}

@Test func implementationCanBeQueuedWithoutAPlanAndMoveDoesNotRequireIdleCodex() throws {
  var project = Project(name: "A", directory: "/tmp/fixture")
  project.automationEnabled = true
  let task = WorkItem(projectID: project.id, title: "Build it")
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library = try BoardReducer.apply(
    .move(
      task.id, .implementation, expectedRevision: 0, configuration: fixtureModelConfiguration),
    to: library)
  #expect(library.tasks[0].stage == .implementation)
  #expect(library.runs.count == 1)
  #expect(library.tasks[0].planPath == nil)
  library = try BoardReducer.apply(.move(task.id, .review, expectedRevision: 1), to: library)
  #expect(library.tasks[0].stage == .review)
  #expect(library.runs.count == 1)
}

@Test func codexCompletionLeavesTaskColumnAndCompletionStateAlone() throws {
  let project = Project(name: "A")
  let task = WorkItem(projectID: project.id, title: "Task", stage: .next)
  var run = AgentRun(task: task, kind: .planning, modelConfiguration: fixtureModelConfiguration)
  run.status = .running
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.runs = [run]
  library = try BoardReducer.apply(.finishRun(run.id, planPath: "to-do/plan.md"), to: library)
  #expect(library.tasks[0].stage == .next)
  #expect(!library.tasks[0].completed)
  #expect(library.runs[0].status == .succeeded)
}

@Test func retryPreservesSessionAndDoesNotDuplicateRun() throws {
  var project = Project(name: "A", directory: "/tmp/fixture")
  project.automationEnabled = true
  let task = WorkItem(projectID: project.id, title: "Task", stage: .next)
  var run = AgentRun(task: task, kind: .planning, modelConfiguration: fixtureModelConfiguration)
  run.status = .failed
  run.threadID = "existing-thread"
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.runs = [run]
  library = try BoardReducer.apply(.retry(run.id), to: library)
  #expect(library.runs.count == 1)
  #expect(library.runs[0].threadID == "existing-thread")
  #expect(library.runs[0].modelConfiguration == fixtureModelConfiguration)
  #expect(library.runs[0].status == .queued)
  #expect(throws: BoardError.self) { try BoardReducer.apply(.retry(run.id), to: library) }
}

@Test func legacyRetryRequiresAndThenStoresAnExplicitModelChoice() throws {
  var project = Project(name: "A", directory: "/tmp/fixture")
  project.automationEnabled = true
  let task = WorkItem(projectID: project.id, title: "Old run", stage: .next)
  var run = AgentRun(task: task, kind: .planning)
  run.status = .interrupted
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.runs = [run]
  #expect(throws: BoardError.self) { try BoardReducer.apply(.retry(run.id), to: library) }
  library = try BoardReducer.apply(
    .retry(run.id, configuration: fixtureModelConfiguration), to: library)
  #expect(library.runs[0].status == .queued)
  #expect(library.runs[0].modelConfiguration == fixtureModelConfiguration)
}

@Test func automationCannotQueueWithoutAResolvedConfiguration() throws {
  var project = Project(name: "A", directory: "/tmp/fixture")
  project.automationEnabled = true
  let task = WorkItem(projectID: project.id, title: "Task", stage: .next)
  var library = Library()
  library.projects = [project]
  library = try BoardReducer.apply(.createTask(task), to: library)
  #expect(library.tasks.count == 1)
  #expect(library.runs.isEmpty)
}

@Test func confirmedPlanningReservesDeterministicPathBeforeRunAndPreservesManualPaths() throws {
  var project = Project(name: "Automated", directory: "/tmp/fixture")
  project.automationEnabled = true
  var library = Library()
  library.projects = [project]

  let created = WorkItem(projectID: project.id, title: "Created in Next", stage: .next)
  library = try BoardReducer.apply(
    .createTask(created, configuration: fixtureModelConfiguration), to: library)
  #expect(
    library.tasks[0].planPath == WorkItem.canonicalPlanPath(for: created.id, title: created.title))
  #expect(library.runs.count == 1)
  #expect(library.runs[0].taskID == created.id)
  #expect(library.runs[0].kind == .planning)

  var moved = WorkItem(projectID: project.id, title: "Moved task")
  library = try BoardReducer.apply(.createTask(moved), to: library)
  moved = library.tasks.first { $0.id == moved.id }!
  library = try BoardReducer.apply(
    .move(
      moved.id, .next, expectedRevision: moved.revision,
      configuration: fixtureModelConfiguration), to: library)
  #expect(
    library.tasks.first { $0.id == moved.id }?.planPath
      == WorkItem.canonicalPlanPath(for: moved.id, title: moved.title)
  )
  #expect(library.runs.last?.taskID == moved.id)

  var manual = WorkItem(projectID: project.id, title: "Manual path", stage: .next)
  manual.planPath = "to-do/chosen-by-user.md"
  library = try BoardReducer.apply(
    .createTask(manual, configuration: fixtureModelConfiguration), to: library)
  #expect(library.tasks.first { $0.id == manual.id }?.planPath == manual.planPath)
}

@Test func planningCompletionMustMatchReservedPathAndLegacyRetryReservesOne() throws {
  var project = Project(name: "Automated", directory: "/tmp/fixture")
  project.automationEnabled = true
  let task = WorkItem(projectID: project.id, title: "Task", stage: .next)
  let reserved = WorkItem.canonicalPlanPath(for: task.id, title: task.title)
  var run = AgentRun(task: task, kind: .planning, modelConfiguration: fixtureModelConfiguration)
  run.status = .running
  var library = Library()
  library.projects = [project]
  var reservedTask = task
  reservedTask.planPath = reserved
  library.tasks = [reservedTask]
  library.runs = [run]
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.finishRun(run.id, planPath: "to-do/wrong.md"), to: library)
  }
  library = try BoardReducer.apply(.finishRun(run.id, planPath: reserved), to: library)
  #expect(library.tasks[0].planPath == reserved)
  #expect(library.tasks[0].stage == .next)

  var legacyRun = AgentRun(
    task: task, kind: .planning, modelConfiguration: fixtureModelConfiguration)
  legacyRun.status = .failed
  var legacy = Library()
  legacy.projects = [project]
  legacy.tasks = [task]
  legacy.runs = [legacyRun]
  legacy = try BoardReducer.apply(.retry(legacyRun.id), to: legacy)
  #expect(legacy.tasks[0].planPath == reserved)
  #expect(legacy.runs[0].status == .queued)
}

@Test func modelConfigurationResolvesTaskThenProjectThenGlobal() {
  let global = CodexModelConfiguration(selection: .latestLuna, effort: "high")
  let project = CodexModelConfiguration(selection: .model("gpt-6-sol"), effort: "medium")
  let task = CodexModelConfiguration(selection: .model("gpt-6-astra"), effort: "low")
  #expect(CodexModelResolver.effective(task: nil, project: nil, global: global).scope == .global)
  #expect(
    CodexModelResolver.effective(task: nil, project: project, global: global).scope == .project)
  #expect(
    CodexModelResolver.effective(task: task, project: project, global: global).configuration == task
  )
  #expect(
    CodexModelResolver.effective(task: nil, project: nil, global: global).configuration == global)
}

@Test func latestLunaUsesHighestStableNumericVersionAndValidatesEffort() throws {
  let catalog = [
    CodexModelOption(id: "gpt-6.9-luna", displayName: "6.9 Luna", reasoningEfforts: ["high"]),
    CodexModelOption(id: "gpt-6.10-luna", displayName: "6.10 Luna", reasoningEfforts: ["high"]),
    CodexModelOption(
      id: "gpt-7-luna-preview", displayName: "Preview Luna", reasoningEfforts: ["high"]),
    CodexModelOption(
      id: "gpt-8-luna", displayName: "Hidden Luna", hidden: true, reasoningEfforts: ["high"]),
    CodexModelOption(id: "gpt-6-astra", displayName: "Astra", reasoningEfforts: ["low"]),
  ]
  let resolved = try CodexModelResolver.resolve(
    CodexModelConfiguration(), scope: .global, catalog: catalog)
  #expect(resolved.modelID == "gpt-6.10-luna")
  #expect(resolved.effort == "high")
  #expect(throws: BoardError.self) {
    try CodexModelResolver.resolve(
      CodexModelConfiguration(selection: .model("gpt-6-astra"), effort: "high"),
      scope: .task, catalog: catalog)
  }
  #expect(throws: BoardError.self) {
    try CodexModelResolver.resolve(
      CodexModelConfiguration(), scope: .global,
      catalog: [
        CodexModelOption(id: "gpt-6-luna", displayName: "Luna", reasoningEfforts: ["medium"])
      ])
  }
  #expect(throws: BoardError.self) {
    try CodexModelResolver.resolve(
      CodexModelConfiguration(), scope: .global,
      catalog: [
        CodexModelOption(id: "gpt-6-luna", displayName: "Luna", reasoningEfforts: ["high"]),
        CodexModelOption(id: "gpt-6.0-luna", displayName: "Luna 6.0", reasoningEfforts: ["high"]),
      ])
  }
}

@Test func oldEntityPayloadsDecodeWithUnsetModelOverrides() throws {
  let project = try JSONDecoder().decode(
    Project.self,
    from: Data(
      #"{"id":"00000000-0000-0000-0000-000000000001","name":"Old","directory":"","automationEnabled":false,"createdAt":0}"#
        .utf8))
  #expect(project.modelOverride == nil)
  let task = try JSONDecoder().decode(
    WorkItem.self,
    from: Data(
      #"{"id":"00000000-0000-0000-0000-000000000002","projectID":"00000000-0000-0000-0000-000000000001","title":"Old task","notes":"","stage":"inbox","rank":0,"completed":false,"revision":0,"createdAt":0,"updatedAt":0}"#
        .utf8))
  #expect(task.modelOverride == nil)
}

@Test func legacyMigrationPreservesIdentitiesAndTaskContent() throws {
  let projectID = UUID()
  let taskID = UUID()
  let data = Data(
    """
    {"boards":[{"id":"\(projectID)","name":"My existing project","projectDirectory":"/tmp/project"}],
    "tasks":[{"id":"\(taskID)","boardID":"\(projectID)","title":"My idea","description":"Keep this","stage":"next","position":2,"completed":false,"revision":4}],"activity":[]}
    """.utf8)
  let library = try LegacyImport.decode(data)
  #expect(library.projects[0].id == projectID)
  #expect(library.tasks[0].id == taskID)
  #expect(library.tasks[0].notes == "Keep this")
  #expect(!library.projects[0].automationEnabled)
  #expect(library.runs.isEmpty)
  #expect(throws: (any Error).self) { try LegacyImport.decode(Data("broken".utf8)) }
}

@Test func databaseExportRestoreAndNoOverwrite() async throws {
  let repo = try LibraryRepository(inMemory: true)
  let a = Project(name: "A")
  var b = Project(name: "B")
  b.usesWorktrees = true
  b.modelOverride = CodexModelConfiguration(selection: .model("gpt-6-sol"), effort: "medium")
  _ = try await repo.apply(.createProject(a))
  _ = try await repo.apply(.createProject(b))
  var savedTask = WorkItem(projectID: b.id, title: "Survives export")
  savedTask.modelOverride = CodexModelConfiguration(selection: .model("gpt-6-astra"), effort: "low")
  _ = try await repo.apply(.createTask(savedTask))
  let data = try await repo.export()
  let restored = try LibraryRepository(inMemory: true)
  let imported = try await restored.importLibrary(data)
  #expect(imported.projects.count == 2)
  #expect(imported.tasks[0].projectID == b.id)
  #expect(imported.projects.first(where: { $0.id == b.id })?.modelOverride == b.modelOverride)
  #expect(imported.projects.first(where: { $0.id == b.id })?.usesWorktrees == true)
  #expect(imported.tasks[0].modelOverride == savedTask.modelOverride)
  await #expect(throws: BoardError.self) { try await restored.importLibrary(data) }
}

@Test func restartDoesNotResumeSideEffects() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let url = folder.appendingPathComponent("test.sqlite")
  let repo = try LibraryRepository(url: url)
  var project = Project(name: "A", directory: "/tmp/fixture")
  project.automationEnabled = true
  _ = try await repo.apply(.createProject(project))
  _ = try await repo.apply(
    .createTask(
      WorkItem(projectID: project.id, title: "Task", stage: .next),
      configuration: fixtureModelConfiguration))
  let reopened = try LibraryRepository(url: url)
  let library = try await reopened.load()
  #expect(library.runs[0].status == .interrupted)
}

@Test func undoRestoresManualMovesWithoutStartingAutomation() throws {
  var project = Project(name: "Project", directory: "/tmp/fixture")
  var task = WorkItem(projectID: project.id, title: "Move me", stage: .next)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library = try BoardReducer.apply(.move(task.id, .inbox, expectedRevision: 0), to: library)
  project.automationEnabled = true
  library.projects = [project]
  library = try BoardReducer.apply(.restoreTask(task.id, task, expectedRevision: 1), to: library)
  #expect(library.tasks[0].stage == .next)
  #expect(library.tasks[0].revision == 2)
  #expect(library.runs.isEmpty)
  task.revision = 0
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.restoreTask(task.id, task, expectedRevision: 0), to: library)
  }
}

@Test func reorderIsProjectAndStageScoped() throws {
  let project = Project(name: "Project")
  var a = WorkItem(projectID: project.id, title: "A")
  var b = WorkItem(projectID: project.id, title: "B")
  a.rank = 0
  b.rank = 1
  var library = Library()
  library.projects = [project]
  library.tasks = [a, b]
  library = try BoardReducer.apply(.reorder(b.id, before: a.id, expectedRevision: 0), to: library)
  #expect(library.items(in: project.id).map(\.title) == ["B", "A"])
  #expect(library.runs.isEmpty)
}

@Test func activeProjectFolderCannotBeChanged() throws {
  var project = Project(name: "Project", directory: "/tmp/fixture")
  project.automationEnabled = true
  let task = WorkItem(projectID: project.id, title: "Task", stage: .next)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.runs = [AgentRun(task: task, kind: .planning)]
  project.directory = "/tmp/other"
  #expect(throws: BoardError.self) { try BoardReducer.apply(.editProject(project), to: library) }
}

@Test func prioritiesSortBeforeUnsetAndPreserveRankWithinGroups() throws {
  let project = Project(name: "Priority")
  var highLater = WorkItem(projectID: project.id, title: "High later")
  highLater.priority = .high
  highLater.rank = 3
  var highFirst = WorkItem(projectID: project.id, title: "High first")
  highFirst.priority = .high
  highFirst.rank = 1
  var medium = WorkItem(projectID: project.id, title: "Medium")
  medium.priority = .medium
  var low = WorkItem(projectID: project.id, title: "Low")
  low.priority = .low
  let unset = WorkItem(projectID: project.id, title: "Unset")
  var library = Library()
  library.projects = [project]
  library.tasks = [unset, low, highLater, medium, highFirst]

  #expect(
    library.items(in: project.id).map(\.title) == [
      "High first", "High later", "Medium", "Low", "Unset",
    ])
  let snapshot = SyncSnapshot(libraryID: UUID(), sequence: 1, library: library)
  let roundTrip = try JSONDecoder().decode(SyncSnapshot.self, from: JSONEncoder().encode(snapshot))
  #expect(roundTrip.tasks.first(where: { $0.id == highFirst.id })?.priority == .high)
  let replica = try roundTrip.replica()
  #expect(replica.tasks.first(where: { $0.id == highFirst.id })?.priority == .high)
  #expect(replica.tasks.first(where: { $0.id == highFirst.id })?.section == highFirst.section)
  #expect(replica.tasks.first(where: { $0.id == highFirst.id })?.status == highFirst.status)

  var changed = highFirst
  changed.priority = .low
  let updated = try BoardReducer.apply(.editTask(changed, expectedRevision: 0), to: library)
  #expect(updated.tasks.first(where: { $0.id == highFirst.id })?.priority == .low)
  #expect(updated.tasks.first(where: { $0.id == highFirst.id })?.revision == 1)
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.editTask(changed, expectedRevision: 0), to: updated)
  }

  let phoneEdit = SyncEnvelope(
    libraryID: UUID(), deviceID: UUID(), expectedRevision: 0,
    command: .editTask(id: highFirst.id, title: "Renamed", notes: "Phone edit"))
  let phoneMutation = try SyncCommandValidator.mutation(for: phoneEdit, in: library)
  let phoneUpdated = try BoardReducer.apply(phoneMutation, to: library)
  #expect(phoneUpdated.tasks.first(where: { $0.id == highFirst.id })?.priority == .high)

  let encoded = try JSONEncoder().encode(unset)
  var oldRecord = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  oldRecord.removeValue(forKey: "priority")
  let legacyData = try JSONSerialization.data(withJSONObject: oldRecord)
  let decoded = try JSONDecoder().decode(WorkItem.self, from: legacyData)
  #expect(decoded.priority == nil)
}

@Test func repeatedPlanFeedbackAppendDoesNotDuplicateSuccessfulRetry() async throws {
  let folder = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChasePlanFeedback-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let todo = folder.appendingPathComponent("to-do", isDirectory: true)
  try FileManager.default.createDirectory(at: todo, withIntermediateDirectories: true)
  let plan = todo.appendingPathComponent("plan.md")
  try Data("# Plan\n".utf8).write(to: plan)
  let store = PlanFileStore()
  try await store.appendFeedback(
    "Keep the migration small.", projectDirectory: folder.path, relativePath: "to-do/plan.md")
  try await store.appendFeedback(
    "Keep the migration small.", projectDirectory: folder.path, relativePath: "to-do/plan.md")
  let text = try String(contentsOf: plan, encoding: .utf8)
  #expect(text.components(separatedBy: "## User feedback on the plan").count == 2)
  #expect(text.hasSuffix("Keep the migration small."))
}

@Test func reorderCannotCrossPriorityGroups() throws {
  let project = Project(name: "Priority")
  var high = WorkItem(projectID: project.id, title: "High")
  high.priority = .high
  let medium = WorkItem(projectID: project.id, title: "Medium")
  var library = Library()
  library.projects = [project]
  library.tasks = [high, medium]
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.reorder(high.id, before: medium.id, expectedRevision: 0), to: library)
  }
}

@Test func legacyWorkItemsDecodeIntoConsolidatedSectionsAndStatuses() throws {
  let projectID = UUID()
  for stage in WorkflowStage.allCases {
    var item = WorkItem(projectID: projectID, title: stage.title, stage: stage)
    item.revision = 7
    item.rank = 3
    let encoded = try JSONEncoder().encode(item)
    var payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    payload.removeValue(forKey: "section")
    payload.removeValue(forKey: "status")
    let legacyData = try JSONSerialization.data(withJSONObject: payload)
    let decoded = try JSONDecoder().decode(WorkItem.self, from: legacyData)
    #expect(decoded.id == item.id)
    #expect(decoded.revision == 7)
    #expect(decoded.rank == 3)
    #expect(decoded.section == WorkItem.legacySection(for: stage))
    #expect(decoded.status == TaskStatus.legacyStatus(for: stage))
  }
}

@Test func specialStatusesSortFirstAndUserSignoffMarksDone() throws {
  let project = Project(name: "Statuses")
  var normal = WorkItem(projectID: project.id, title: "Normal", stage: .implementation)
  normal.rank = 0
  var review = WorkItem(projectID: project.id, title: "Review", stage: .review)
  review.rank = 8
  var waiting = WorkItem(projectID: project.id, title: "Waiting", stage: .implementation)
  waiting.status = .waiting
  waiting.rank = 9
  var failed = WorkItem(projectID: project.id, title: "Failed", stage: .implementation)
  failed.status = .error
  failed.rank = 10
  var library = Library()
  library.projects = [project]
  library.tasks = [normal, review, waiting, failed]

  #expect(
    library.items(in: project.id, section: .implementing).map(\.title)
      == ["Waiting", "Failed", "Review", "Normal"])
  library = try BoardReducer.apply(.complete(review.id, true, expectedRevision: 0), to: library)
  let done = try #require(library.tasks.first(where: { $0.id == review.id }))
  #expect(done.completed)
  #expect(done.status == .done)
  #expect(done.section == .implementing)
}
