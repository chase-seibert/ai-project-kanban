import Foundation
import Testing

@testable import StageChaseCore

private let fixtureModelConfiguration = ResolvedCodexConfiguration(
  selection: .latestLuna, modelID: "gpt-6.10-luna", effort: "high", scope: .global)

@Test func explicitTaskRunPreservesPlacementAndSnapshotsProjectSettings() throws {
  var project = Project(name: "Manual runner", directory: "/tmp/manual-runner")
  project.automationEnabled = false
  project.usesWorktrees = true
  project.executionProfile = .fullAccessNoPrompts
  var task = WorkItem(projectID: project.id, title: "Run this now", stage: .next)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]

  library = try BoardReducer.apply(
    .runTaskNow(
      task.id, expectedRevision: task.revision, kind: .planning,
      configuration: fixtureModelConfiguration),
    to: library)

  task = library.tasks[0]
  #expect(task.stage == .next)
  #expect(task.section == .planning)
  #expect(!task.completed)
  #expect(task.planPath == WorkItem.canonicalPlanPath(for: task.id, title: task.title))
  #expect(task.revision == 1)
  #expect(library.runs.count == 1)
  #expect(library.runs[0].kind == .planning)
  #expect(library.runs[0].status == .queued)
  #expect(library.runs[0].usesWorktrees == true)
  #expect(library.runs[0].executionProfile == .fullAccessNoPrompts)
  #expect(library.runs[0].modelConfiguration == fixtureModelConfiguration)

  #expect(!library.projects[0].automationEnabled)
  #expect(library.runs[0].status == .queued)
}

@Test func explicitStageChasePlanningCanStartFromInboxWithoutMovingTask() throws {
  let project = Project(name: "Inbox planning", directory: "/tmp/inbox-planning")
  let task = WorkItem(projectID: project.id, title: "Plan before implementation")
  var library = Library()
  library.projects = [project]
  library.tasks = [task]

  library = try BoardReducer.apply(
    .runTaskNow(
      task.id, expectedRevision: task.revision, kind: .planning,
      configuration: fixtureModelConfiguration),
    to: library)

  #expect(library.tasks[0].section == .inbox)
  #expect(library.tasks[0].stage == .inbox)
  #expect(library.tasks[0].planPath == WorkItem.canonicalPlanPath(for: task.id, title: task.title))
  #expect(library.runs.first?.kind == .planning)
}

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
  #expect(prompt.contains("Preserve the current completion flag"))
  #expect(prompt.contains("MCP has no completion action"))
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
  #expect(revisionPrompt.contains("Review the existing plan"))
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
  #expect(decoded.favoriteMakeTargets.isEmpty)
  #expect(!decoded.usesWorktrees)
  #expect(decoded.executionProfile == .workspaceAccessNoPrompts)
  #expect(!Project(name: "New").usesWorktrees)

  var enabled = decoded
  enabled.usesWorktrees = true
  enabled.favoriteMakeTargets = ["test", "lint"]
  let roundTrip = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(enabled))
  #expect(roundTrip == enabled)
}

@Test func projectExecutionProfilesAreIndependentAndRunRetriesKeepTheirSnapshot() throws {
  var restricted = Project(name: "Restricted", directory: "/tmp/restricted")
  restricted.automationEnabled = true
  var full = Project(name: "Full", directory: "/tmp/full")
  full.automationEnabled = true
  full.executionProfile = .fullAccessNoPrompts
  var library = Library()
  library.projects = [restricted, full]
  let restrictedTask = WorkItem(projectID: restricted.id, title: "Restricted task", stage: .next)
  let fullTask = WorkItem(projectID: full.id, title: "Full task", stage: .next)
  library = try BoardReducer.apply(
    .createTask(restrictedTask, configuration: fixtureModelConfiguration), to: library)
  library = try BoardReducer.apply(
    .createTask(fullTask, configuration: fixtureModelConfiguration), to: library)
  #expect(library.runs[0].executionProfile == .workspaceAccessNoPrompts)
  #expect(library.runs[1].executionProfile == .fullAccessNoPrompts)

  var failedRun = library.runs[1]
  failedRun.status = .failed
  library = try BoardReducer.apply(.updateRun(failedRun), to: library)
  var changedProject = full
  changedProject.executionProfile = .workspaceAccessNoPrompts
  library = try BoardReducer.apply(.editProject(changedProject), to: library)
  library = try BoardReducer.apply(.retry(failedRun.id), to: library)
  #expect(library.runs[1].executionProfile == .fullAccessNoPrompts)
}

@Test func legacyProjectAndRunRecordsDecodeToSafeExecutionProfile() throws {
  let legacyProject = Data(
    #"{"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","directory":"/tmp/legacy","createdAt":0}"#
      .utf8)
  let project = try JSONDecoder().decode(Project.self, from: legacyProject)
  #expect(project.executionProfile == .workspaceAccessNoPrompts)

  let task = WorkItem(projectID: project.id, title: "Old run")
  let run = AgentRun(task: task, kind: .implementation)
  let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as! [String: Any]
  var legacyRunObject = object
  legacyRunObject.removeValue(forKey: "executionProfile")
  let decoded = try JSONDecoder().decode(
    AgentRun.self, from: JSONSerialization.data(withJSONObject: legacyRunObject))
  #expect(decoded.executionProfile == nil)
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
  project.executionProfile = .fullAccessNoPrompts
  project.favoriteMakeTargets = ["test", "build"]
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
  #expect(replica.projects[0].executionProfile == .fullAccessNoPrompts)
  #expect(replica.projects[0].favoriteMakeTargets == project.favoriteMakeTargets)
  #expect(replica.tasks[0].notes == task.notes)
  #expect(replica.tasks[0].planPath == nil)
  #expect(replica.runs[0].status == run.status)

  var legacyObject = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
  var legacyProjects = try #require(legacyObject["projects"] as? [[String: Any]])
  legacyProjects[0].removeValue(forKey: "favoriteMakeTargets")
  legacyObject["projects"] = legacyProjects
  let legacySnapshotData = try JSONSerialization.data(withJSONObject: legacyObject)
  let legacySnapshot = try JSONDecoder().decode(SyncSnapshot.self, from: legacySnapshotData)
  #expect(try legacySnapshot.replica().projects[0].favoriteMakeTargets.isEmpty)
}

@Test func syncSnapshotRoundTripsOptionalCodexThreadIDs() throws {
  let project = Project(name: "Session handoff")
  let task = WorkItem(projectID: project.id, title: "Open from iPhone")
  var linkedRun = AgentRun(task: task, kind: .implementation)
  linkedRun.threadID = "desktop-thread-123"
  let unlinkedRun = AgentRun(task: task, kind: .planning)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.runs = [linkedRun, unlinkedRun]

  let snapshot = SyncSnapshot(libraryID: UUID(), sequence: 1, library: library)
  let encoded = try JSONEncoder().encode(snapshot)
  let decoded = try JSONDecoder().decode(SyncSnapshot.self, from: encoded)
  let replica = try decoded.replica()

  #expect(decoded.version == 5)
  #expect(decoded.runs.first(where: { $0.id == linkedRun.id })?.threadID == "desktop-thread-123")
  #expect(decoded.runs.first(where: { $0.id == unlinkedRun.id })?.threadID == nil)
  #expect(replica.runs.first(where: { $0.id == linkedRun.id })?.threadID == "desktop-thread-123")
  #expect(replica.runs.first(where: { $0.id == unlinkedRun.id })?.threadID == nil)
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
    expectedRevision: 0, editedAt: .distantPast,
    command: .editTask(id: taskID, title: "Stale", notes: ""))
  guard case .superseded(let staleSequence, _) = try await repository.applyRemote(stale)
  else {
    Issue.record("Expected an older queued edit to be acknowledged as superseded")
    return
  }
  guard case .superseded(let replaySequence, _) = try await repository.applyRemote(stale)
  else {
    Issue.record("Expected a superseded retry to replay its terminal receipt")
    return
  }
  #expect(replaySequence == staleSequence)
  let later = SyncEnvelope(
    libraryID: initial.libraryID, deviceID: deviceID, clientSequence: 4,
    expectedRevision: 1, command: .editTask(id: taskID, title: "Later", notes: ""))
  guard case .applied = try await repository.applyRemote(later)
  else {
    Issue.record("A later operation must proceed after a superseded queue entry")
    return
  }
  let persisted = try await repository.syncStateSnapshot()
  #expect(persisted.library.tasks[0].title == "Later")
}

@Test func phoneCompletionAndDeletionCommandsAreRevisionChecked() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Phone actions")
  _ = try await repository.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Complete then delete")
  _ = try await repository.apply(.createTask(task))
  let state = try await repository.syncStateSnapshot()
  let deviceID = UUID()
  let complete = SyncEnvelope(
    libraryID: state.libraryID, deviceID: deviceID, clientSequence: 1,
    expectedRevision: task.revision,
    command: .completeTask(id: task.id, completed: true))
  guard case .applied(_, let completed) = try await repository.applyRemote(complete) else {
    Issue.record("Expected the explicit completion command to apply")
    return
  }
  #expect(completed.tasks.first?.completed == true)
  let staleDelete = SyncEnvelope(
    libraryID: state.libraryID, deviceID: deviceID, clientSequence: 2,
    expectedRevision: task.revision, command: .deleteTask(id: task.id))
  guard case .conflict = try await repository.applyRemote(staleDelete) else {
    Issue.record("A stale delete must preserve the changed task")
    return
  }
  let currentRevision = try #require(completed.tasks.first?.revision)
  let delete = SyncEnvelope(
    libraryID: state.libraryID, deviceID: deviceID, clientSequence: 3,
    expectedRevision: currentRevision, command: .deleteTask(id: task.id))
  guard case .applied(_, let deleted) = try await repository.applyRemote(delete) else {
    Issue.record("Expected a revision-matched confirmed delete command to apply")
    return
  }
  #expect(deleted.tasks.isEmpty)
}

@Test func phoneDeleteRejectsAnActiveRunAndPreviousProtocolCommandsFailClearly() throws {
  let project = Project(name: "Compatibility")
  let task = WorkItem(projectID: project.id, title: "Busy task")
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.runs = [AgentRun(task: task, kind: .implementation)]
  let deletion = SyncEnvelope(
    libraryID: UUID(), deviceID: UUID(), expectedRevision: task.revision,
    command: .deleteTask(id: task.id))
  let mutation = try SyncCommandValidator.mutation(for: deletion, in: library)
  #expect(throws: BoardError.self) { try BoardReducer.apply(mutation, to: library) }

  var oldEnvelope = deletion
  oldEnvelope.version = SyncProtocol.version - 1
  #expect(throws: BoardError.self) {
    try SyncCommandValidator.mutation(for: oldEnvelope, in: library)
  }
  let snapshot = SyncSnapshot(libraryID: UUID(), sequence: 0, library: library)
  #expect(snapshot.version == 5)
  var oldSnapshot = snapshot
  oldSnapshot.version = SyncProtocol.version - 1
  #expect(throws: BoardError.self) { try oldSnapshot.replica() }
}

@Test func unreadAcknowledgmentsSyncBidirectionallyAndNeverMoveBackward() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Unread")
  _ = try await repository.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Moved")
  _ = try await repository.apply(.createTask(task))
  _ = try await repository.apply(.move(task.id, .planned, expectedRevision: task.revision))
  var state = try await repository.syncStateSnapshot()
  let firstChange = try #require(state.library.activity.last(where: { $0.taskChange != nil }))
  let phoneID = UUID()
  let firstRead = SyncEnvelope(
    libraryID: state.libraryID, deviceID: phoneID, clientSequence: 1,
    command: .acknowledgeTaskChanges(
      taskID: task.id,
      marker: TaskChangeReadMarker(date: firstChange.date, activityID: firstChange.id)))
  guard case .applied(_, let readSnapshot) = try await repository.applyRemote(firstRead) else {
    Issue.record("Expected the phone task acknowledgment to reach the Mac")
    return
  }
  #expect(readSnapshot.taskReadMarkers[task.id]?.activityID == firstChange.id)
  #expect(readSnapshot.projectReadMarkers[project.id] == nil)

  _ = try await repository.apply(.move(task.id, .implementation, expectedRevision: 1))
  state = try await repository.syncStateSnapshot()
  let newerChange = try #require(state.library.activity.last(where: { $0.taskChange != nil }))
  #expect(!readSnapshot.taskReadMarkers[task.id]!.acknowledges(newerChange))
  let newerRead = SyncEnvelope(
    libraryID: state.libraryID, deviceID: phoneID, clientSequence: 2,
    command: .acknowledgeTaskChanges(
      taskID: task.id,
      marker: TaskChangeReadMarker(date: newerChange.date, activityID: newerChange.id)))
  guard case .applied = try await repository.applyRemote(newerRead) else {
    Issue.record("Expected the newer task acknowledgment to apply")
    return
  }

  // A delayed acknowledgment from another device cannot roll the shared marker back.
  let delayed = SyncEnvelope(
    libraryID: state.libraryID, deviceID: UUID(), clientSequence: 1,
    command: .acknowledgeTaskChanges(
      taskID: task.id,
      marker: TaskChangeReadMarker(date: firstChange.date, activityID: firstChange.id)))
  guard case .applied = try await repository.applyRemote(delayed) else {
    Issue.record("Expected the idempotent stale marker to be accepted")
    return
  }
  state = try await repository.syncStateSnapshot()
  #expect(state.taskReadMarkers[task.id]?.activityID == newerChange.id)

  let projectRead = SyncEnvelope(
    libraryID: state.libraryID, deviceID: phoneID, clientSequence: 3,
    command: .acknowledgeProjectChanges(
      projectID: project.id,
      marker: TaskChangeReadMarker(date: newerChange.date, activityID: newerChange.id)))
  guard case .applied(_, let cleared) = try await repository.applyRemote(projectRead) else {
    Issue.record("Expected project-level acknowledgment to apply independently")
    return
  }
  #expect(cleared.projectReadMarkers[project.id]?.activityID == newerChange.id)
  #expect(cleared.taskReadMarkers[task.id]?.activityID == newerChange.id)
  let roundTrip = try JSONDecoder().decode(
    SyncSnapshot.self, from: JSONEncoder().encode(cleared))
  #expect(roundTrip.taskReadMarkers == cleared.taskReadMarkers)
  #expect(roundTrip.projectReadMarkers == cleared.projectReadMarkers)
}

@Test func sharedReadMarkersSurviveRepositoryRestart() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChaseReadMarkers-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = root.appendingPathComponent("Library.sqlite")
  var repository: LibraryRepository? = try LibraryRepository(url: store)
  let project = Project(name: "Persistent read state")
  _ = try await repository!.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Read once")
  _ = try await repository!.apply(.createTask(task))
  _ = try await repository!.apply(.move(task.id, .planned, expectedRevision: task.revision))
  let before = try await repository!.syncStateSnapshot()
  let change = try #require(before.library.activity.last(where: { $0.taskChange != nil }))
  let acknowledgment = SyncEnvelope(
    libraryID: before.libraryID, deviceID: UUID(),
    command: .acknowledgeProjectChanges(
      projectID: project.id,
      marker: TaskChangeReadMarker(date: change.date, activityID: change.id)))
  guard case .applied = try await repository!.applyRemote(acknowledgment) else {
    Issue.record("Expected the project read marker to persist")
    return
  }
  repository = nil
  repository = try LibraryRepository(url: store)
  let reopened = try await repository!.syncStateSnapshot()
  #expect(reopened.projectReadMarkers[project.id]?.activityID == change.id)
  #expect(reopened.taskReadMarkers[task.id] == nil)
  repository = nil
}

@Test func directGitRequestsStayOutOfTheEditCommandProtocol() throws {
  let taskID = UUID()
  let projectID = UUID()
  let request = SyncClientRequest.direct(
    .commitTask(
      requestID: UUID(), projectID: projectID, taskID: taskID, expectedRevision: 4))
  let encoded = try JSONEncoder.syncEncoder.encode(request)
  let text = String(decoding: encoded, as: UTF8.self)
  #expect(text.contains("commitTask"))
  #expect(!text.contains("/Users/"))
  let decoded = try JSONDecoder.syncDecoder.decode(SyncClientRequest.self, from: encoded)
  guard
    case .direct(
      .commitTask(
        _, let decodedProjectID, let decodedTaskID, let revision)) = decoded
  else {
    Issue.record("Expected the direct Git request to round trip without becoming a queued command")
    return
  }
  #expect(decodedProjectID == projectID)
  #expect(decodedTaskID == taskID)
  #expect(revision == 4)
}

@Test func newerPhoneTaskEditWinsAndEqualTimestampMacEditWinsDeterministically() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Ordering")
  _ = try await repository.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Original", stage: .inbox)
  _ = try await repository.apply(.createTask(task))
  var macEdited = task
  macEdited.title = "Mac version"
  _ = try await repository.apply(.editTask(macEdited, expectedRevision: 0))
  let state = try await repository.syncStateSnapshot()
  let current = try #require(state.library.tasks.first)
  let deviceID = UUID()

  let equalTime = SyncEnvelope(
    libraryID: state.libraryID, deviceID: deviceID, clientSequence: 1,
    expectedRevision: 0, editedAt: current.updatedAt,
    command: .editTask(id: task.id, title: "Equal timestamp phone", notes: ""))
  guard case .superseded = try await repository.applyRemote(equalTime) else {
    Issue.record("Exact timestamp ties must deterministically preserve the Mac version")
    return
  }

  let newer = SyncEnvelope(
    libraryID: state.libraryID, deviceID: deviceID, clientSequence: 2,
    expectedRevision: 0, editedAt: current.updatedAt.addingTimeInterval(1),
    command: .editTask(id: task.id, title: "Newer phone version", notes: ""))
  guard case .applied = try await repository.applyRemote(newer) else {
    Issue.record("A newer phone edit should rebase over the stale Mac revision")
    return
  }
  let finalState = try await repository.syncStateSnapshot()
  #expect(finalState.library.tasks.first?.title == "Newer phone version")
}

@Test func forcedSnapshotRequestSurvivesWireEncoding() throws {
  let request = SyncClientRequest.fullSnapshot
  let decoded = try JSONDecoder.syncDecoder.decode(
    SyncClientRequest.self, from: JSONEncoder.syncEncoder.encode(request))
  guard case .fullSnapshot = decoded else {
    Issue.record("Expected the explicit unconditional full-snapshot request")
    return
  }
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

@Test func externalPlanningRunRetainsItsKindAndLiveState() throws {
  let project = Project(name: "Desktop planning")
  let task = WorkItem(projectID: project.id, title: "Plan this")
  var run = AgentRun(task: task, kind: .planning)
  run.source = .codexDesktop
  run.status = .running
  run.threadID = "desktop-thread"
  run.turnID = "desktop-turn"
  run.liveState = .busy
  var initial = Library()
  initial.projects = [project]
  initial.tasks = [task]
  let library = try BoardReducer.apply(.beginExternalRun(run), to: initial)
  let saved = try #require(library.runs.first)
  #expect(saved.kind == .planning)
  #expect(saved.threadID == "desktop-thread")
  #expect(saved.liveState == .busy)

  let legacyData = try JSONEncoder().encode(AgentRun(task: task, kind: .task))
  let legacy = try JSONDecoder().decode(AgentRun.self, from: legacyData)
  #expect(legacy.liveState == nil)
}

@Test func externalCodexStartSupersedesOnlySameTaskStageChaseRunAndIgnoresLateUpdates() async throws
{
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Retry tracking", directory: "/tmp/retry-tracking")
  _ = try await repository.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Tracked task", stage: .implementation)
  _ = try await repository.apply(.createTask(task))
  let unrelatedTask = WorkItem(projectID: project.id, title: "Other task", stage: .implementation)
  _ = try await repository.apply(.createTask(unrelatedTask))

  _ = try await repository.apply(
    .runTaskNow(
      task.id, expectedRevision: 0, kind: .implementation,
      configuration: fixtureModelConfiguration))
  var snapshot = try await repository.load()
  var stageChaseRun = try #require(snapshot.runs.first(where: { $0.taskID == task.id }))
  stageChaseRun.source = .stageChase
  stageChaseRun.status = .running
  _ = try await repository.apply(.updateRun(stageChaseRun))

  _ = try await repository.apply(
    .runTaskNow(
      unrelatedTask.id, expectedRevision: 0, kind: .implementation,
      configuration: fixtureModelConfiguration))
  snapshot = try await repository.load()
  let unrelatedRun = try #require(snapshot.runs.first(where: { $0.taskID == unrelatedTask.id }))

  let externalRunID = UUID()
  var externalRun = AgentRun(task: task, kind: .task)
  externalRun.id = externalRunID
  externalRun.source = .codexDesktop
  externalRun.status = .running
  externalRun.createdAt = stageChaseRun.createdAt.addingTimeInterval(1)
  let first = try await repository.applyMCP(
    .beginExternalRun(externalRun), operationID: externalRunID, fingerprint: "begin-retry")
  #expect(!first.replayed)
  #expect(first.library.runs.count == 3)
  #expect(first.library.runs.first(where: { $0.id == stageChaseRun.id })?.status == .superseded)
  #expect(first.library.latestRun(for: task.id)?.id == externalRunID)
  #expect(first.library.runs.first(where: { $0.id == unrelatedRun.id })?.status.isActive == true)
  #expect(
    first.library.activity.contains(where: {
      $0.runID == stageChaseRun.id && $0.message.contains("superseded")
    }))

  let replay = try await repository.applyMCP(
    .beginExternalRun(externalRun), operationID: externalRunID, fingerprint: "begin-retry")
  #expect(replay.replayed)
  #expect(replay.library.runs.count == 3)
  let currentTaskStatus = try #require(replay.library.tasks.first(where: { $0.id == task.id }))
    .status

  var lateStageChaseUpdate = stageChaseRun
  lateStageChaseUpdate.status = .failed
  lateStageChaseUpdate.summary = "Late runner failure"
  let afterLateUpdate = try BoardReducer.apply(.updateRun(lateStageChaseUpdate), to: replay.library)
  #expect(afterLateUpdate.runs.first(where: { $0.id == stageChaseRun.id })?.status == .superseded)
  #expect(
    afterLateUpdate.runs.first(where: { $0.id == stageChaseRun.id })?.summary.contains(
      "Late runner") == false)
  #expect(afterLateUpdate.latestRun(for: task.id)?.id == externalRunID)
  #expect(afterLateUpdate.tasks.first(where: { $0.id == task.id })?.status == currentTaskStatus)

  var concurrentExternalRun = AgentRun(task: task, kind: .task)
  concurrentExternalRun.id = UUID()
  concurrentExternalRun.source = .codexDesktop
  concurrentExternalRun.status = .running
  #expect(throws: (any Error).self) {
    try BoardReducer.apply(.beginExternalRun(concurrentExternalRun), to: replay.library)
  }
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
  library = try BoardReducer.apply(.complete(task.id, true, expectedRevision: 2), to: library)
  #expect(library.tasks[0].completed)
  #expect(library.tasks[0].status == .done)
  var activeRun = library.runs[0]
  activeRun.status = .running
  library = try BoardReducer.apply(.updateRun(activeRun), to: library)
  library = try BoardReducer.apply(.finishRun(library.runs[0].id, planPath: nil), to: library)
  #expect(library.tasks[0].stage == .review)
  #expect(library.tasks[0].section == .implementing)
  #expect(library.tasks[0].completed)
  #expect(library.tasks[0].status == .done)
}

@Test func sameStageConfirmationCanQueueOnlyAfterUserConfirms() throws {
  var project = Project(name: "A", directory: "/tmp/fixture")
  project.automationEnabled = true
  let task = WorkItem(projectID: project.id, title: "Plan it", stage: .next)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]

  library = try BoardReducer.apply(
    .move(task.id, .next, expectedRevision: 0, configuration: fixtureModelConfiguration),
    to: library)

  #expect(library.tasks[0].stage == .next)
  #expect(library.runs.count == 1)
  #expect(library.tasks[0].planPath == WorkItem.canonicalPlanPath(for: task.id, title: task.title))
  #expect(library.tasks[0].revision == 1)
}

@Test func reorderCanMoveTaskAcrossPriorityGroups() throws {
  let project = Project(name: "A")
  var source = WorkItem(projectID: project.id, title: "Source", stage: .implementation)
  source.priority = .low
  source.rank = 0
  var target = WorkItem(projectID: project.id, title: "Target", stage: .implementation)
  target.priority = .high
  target.rank = 0
  var library = Library()
  library.projects = [project]
  library.tasks = [source, target]

  library = try BoardReducer.apply(
    .reorder(source.id, before: target.id, expectedRevision: source.revision), to: library)

  let moved = try #require(library.tasks.first { $0.id == source.id })
  #expect(moved.priority == .high)
  #expect(moved.rank == 0)
  #expect(moved.revision == 1)
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
  #expect(library.tasks[0].status == .ready)
  #expect(!library.tasks[0].completed)
  #expect(library.runs[0].status == .succeeded)
}

@Test func everyTaskStatusHasAnIconAndSemanticBadgeColor() {
  let styles = TaskStatus.allCases.map(\.badgeStyle)
  #expect(styles.count == 9)
  #expect(styles.allSatisfy { !$0.symbol.isEmpty })
  #expect(Set(styles.map(\.symbol)).count == TaskStatus.allCases.count)
  #expect(TaskStatus.ready.badgeStyle.color == .green)
  #expect(TaskStatus.review.badgeStyle.color == .green)
  #expect(TaskStatus.done.badgeStyle.symbol == "checkmark.seal.fill")
  #expect(TaskStatus.done.badgeStyle.color == .blue)
  #expect(TaskStatus.quota.badgeStyle.color == .orange)
}

@Test func successfulImplementationNeedsExplicitSignoffForDone() throws {
  let project = Project(name: "A")
  let task = WorkItem(projectID: project.id, title: "Implement", stage: .implementation)
  var run = AgentRun(
    task: task, kind: .implementation, modelConfiguration: fixtureModelConfiguration)
  run.status = .running
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.runs = [run]

  library = try BoardReducer.apply(.finishRun(run.id, planPath: nil), to: library)
  #expect(library.tasks[0].status == .review)
  #expect(!library.tasks[0].completed)
  #expect(library.runs[0].status == .succeeded)

  library = try BoardReducer.apply(.complete(task.id, true, expectedRevision: 1), to: library)
  #expect(library.tasks[0].status == .done)
  #expect(library.tasks[0].completed)
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
  #expect(task.completedAt == nil)
}

@Test func completedTaskTimestampTracksTransitionsAndProjectCommitRecency() throws {
  let project = Project(name: "Commit timestamps")
  let otherProject = Project(name: "Other project")
  var older = WorkItem(projectID: project.id, title: "Older task")
  older.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  older.completed = true
  older.updatedAt = Date(timeIntervalSinceReferenceDate: 300)
  older.completedAt = Date(timeIntervalSinceReferenceDate: 100)
  var newer = WorkItem(projectID: project.id, title: "Newest completed task")
  newer.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  newer.completed = true
  newer.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
  newer.completedAt = Date(timeIntervalSinceReferenceDate: 200)
  var unrelated = WorkItem(projectID: otherProject.id, title: "Other project task")
  unrelated.completed = true
  unrelated.completedAt = Date(timeIntervalSince1970: 500)
  let legacy = try JSONDecoder().decode(
    WorkItem.self,
    from: Data(
      """
      {"id":"00000000-0000-0000-0000-000000000003","projectID":"\(project.id.uuidString)","title":"Legacy completed task","completed":true,"createdAt":0,"updatedAt":150}
      """.utf8))
  #expect(legacy.completedAt == nil)

  var library = Library()
  library.projects = [project, otherProject]
  library.tasks = [older, newer, unrelated, legacy]
  #expect(library.latestCompletedTask(in: project.id)?.id == newer.id)
  var tied = WorkItem(projectID: project.id, title: "Tie breaker")
  tied.id = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
  tied.completed = true
  tied.completedAt = newer.completedAt
  library.tasks.append(tied)
  #expect(library.latestCompletedTask(in: project.id)?.id == tied.id)

  let active = WorkItem(projectID: project.id, title: "New transition")
  library.tasks.append(active)
  library = try BoardReducer.apply(.complete(active.id, true, expectedRevision: 0), to: library)
  let completedAt = try #require(library.tasks.first(where: { $0.id == active.id })?.completedAt)
  var edited = try #require(library.tasks.first(where: { $0.id == active.id }))
  edited.title = "Edited after completion"
  library = try BoardReducer.apply(
    .editTask(edited, expectedRevision: edited.revision), to: library)
  #expect(library.tasks.first(where: { $0.id == active.id })?.completedAt == completedAt)

  library = try BoardReducer.apply(
    .complete(active.id, false, expectedRevision: edited.revision + 1), to: library)
  #expect(library.tasks.first(where: { $0.id == active.id })?.completedAt == nil)
  #expect(library.latestCompletedTask(in: project.id)?.id == tied.id)
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
  normal.updatedAt = Date(timeIntervalSince1970: 10)
  normal.rank = 0
  var review = WorkItem(projectID: project.id, title: "Review", stage: .review)
  review.updatedAt = Date(timeIntervalSince1970: 40)
  review.rank = 8
  var waiting = WorkItem(projectID: project.id, title: "Waiting", stage: .implementation)
  waiting.updatedAt = Date(timeIntervalSince1970: 30)
  waiting.status = .waiting
  waiting.rank = 9
  var failed = WorkItem(projectID: project.id, title: "Failed", stage: .implementation)
  failed.updatedAt = Date(timeIntervalSince1970: 20)
  failed.status = .error
  failed.rank = 10
  var library = Library()
  library.projects = [project]
  library.tasks = [normal, review, waiting, failed]

  #expect(
    library.items(in: project.id, section: .implementing).map(\.title)
      == ["Review", "Waiting", "Failed", "Normal"])
  library = try BoardReducer.apply(.complete(review.id, true, expectedRevision: 0), to: library)
  let done = try #require(library.tasks.first(where: { $0.id == review.id }))
  #expect(done.completed)
  #expect(done.status == .done)
  #expect(done.section == .implementing)
}

@Test func planningAndImplementingSectionsSortByMostRecentlyUpdated() {
  let project = Project(name: "Recent updates")
  var oldPlanning = WorkItem(projectID: project.id, title: "Old planning", stage: .next)
  oldPlanning.updatedAt = Date(timeIntervalSince1970: 10)
  oldPlanning.priority = .high
  var newPlanning = WorkItem(projectID: project.id, title: "New planning", stage: .planned)
  newPlanning.updatedAt = Date(timeIntervalSince1970: 30)
  newPlanning.priority = .low
  var oldImplementation = WorkItem(
    projectID: project.id, title: "Old implementation", stage: .implementation)
  oldImplementation.updatedAt = Date(timeIntervalSince1970: 20)
  oldImplementation.priority = .high
  var newImplementation = WorkItem(
    projectID: project.id, title: "New implementation", stage: .review)
  newImplementation.updatedAt = Date(timeIntervalSince1970: 40)
  newImplementation.priority = .low
  var library = Library()
  library.projects = [project]
  library.tasks = [oldPlanning, oldImplementation, newPlanning, newImplementation]

  #expect(
    library.items(in: project.id, section: .planning).map(\.title) == [
      "New planning", "Old planning",
    ])
  #expect(
    library.items(in: project.id, section: .implementing).map(\.title) == [
      "New implementation", "Old implementation",
    ])
}

@Test func taskRunDisclosuresKeepLatestOpenAndUserChoicesAcrossUpdates() {
  let project = Project(name: "Inspector")
  let task = WorkItem(projectID: project.id, title: "Mixed runs")
  var older = AgentRun(task: task, kind: .planning)
  older.createdAt = Date(timeIntervalSince1970: 10)
  var latest = AgentRun(task: task, kind: .implementation)
  latest.createdAt = Date(timeIntervalSince1970: 20)
  latest.source = .codexDesktop
  var state = TaskRunDisclosureState()
  state.select(taskID: task.id, runs: [older, latest])
  #expect(state.expandedIDs == [latest.id])
  #expect(TaskRunDisclosureState.ordered([older, latest]).map(\.id) == [latest.id, older.id])

  state.setExpanded(true, for: older.id)
  state.setExpanded(false, for: latest.id)
  latest.status = .succeeded
  latest.updatedAt = Date(timeIntervalSince1970: 100)
  state.select(taskID: task.id, runs: [latest, older])
  #expect(state.expandedIDs == [older.id])

  var newest = AgentRun(task: task, kind: .task)
  newest.createdAt = Date(timeIntervalSince1970: 30)
  state.setExpanded(true, for: latest.id)
  state.select(taskID: task.id, runs: [older, newest, latest])
  #expect(state.expandedIDs == [older.id, newest.id])
  state.select(taskID: task.id, runs: [newest, latest])
  #expect(state.expandedIDs == [newest.id])

  let other = WorkItem(projectID: project.id, title: "Other")
  let otherRun = AgentRun(task: other, kind: .planning)
  state.select(taskID: other.id, runs: [newest, otherRun])
  #expect(state.expandedIDs == [otherRun.id])
  state.select(taskID: task.id, runs: [latest, newest])
  #expect(state.expandedIDs == [newest.id])
  state.select(taskID: task.id, runs: [])
  #expect(state.expandedIDs.isEmpty)
  #expect(state.latestID == nil)
}

@Test func taskRunOrderingBreaksTimestampTiesDeterministically() {
  let task = WorkItem(projectID: UUID(), title: "Same timestamp")
  var a = AgentRun(task: task, kind: .planning)
  var b = AgentRun(task: task, kind: .task)
  a.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  a.createdAt = Date(timeIntervalSince1970: 10)
  b.createdAt = a.createdAt
  #expect(TaskRunDisclosureState.ordered([b, a]).map(\.id) == [a.id, b.id])
}
