import Foundation
import Testing

@testable import StageChaseCore

private let fixtureModelConfiguration = ResolvedCodexConfiguration(
  selection: .latestLuna, modelID: "gpt-6.10-luna", effort: "high", scope: .global)

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
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.move(task.id, .review, expectedRevision: 0), to: library)
  }
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.move(task.id, .review, expectedRevision: 1), to: library)
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

@Test func implementationRequiresPlanAndRollbackIsAtomic() throws {
  var project = Project(name: "A", directory: "/tmp/fixture")
  project.automationEnabled = true
  let task = WorkItem(projectID: project.id, title: "Build it")
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(
      .move(
        task.id, .implementation, expectedRevision: 0, configuration: fixtureModelConfiguration),
      to: library)
  }
  #expect(library.tasks[0].stage == .inbox)
  #expect(library.runs.isEmpty)
}

@Test func completionMovesStageButNeverCompletesTask() throws {
  let project = Project(name: "A")
  let task = WorkItem(projectID: project.id, title: "Task", stage: .next)
  var run = AgentRun(task: task, kind: .planning, modelConfiguration: fixtureModelConfiguration)
  run.status = .running
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.runs = [run]
  library = try BoardReducer.apply(.finishRun(run.id, planPath: "to-do/plan.md"), to: library)
  #expect(library.tasks[0].stage == .planned)
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
  #expect(throws: BoardError.self) { try BoardReducer.apply(.createTask(task), to: library) }
  #expect(library.tasks.isEmpty)
  #expect(library.runs.isEmpty)
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
