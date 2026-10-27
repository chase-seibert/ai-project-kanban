import Foundation
import Testing

@testable import StageChaseCore

private let fixtureModelConfiguration = ResolvedCodexConfiguration(
  selection: .latestLuna, modelID: "gpt-6.10-luna", effort: "high", scope: .global)

@Test func loopbackVerificationStatesUseNeutralSuccessAndFailureColors() {
  #expect(LoopbackVerificationState.inactive.presentationColor == .neutral)
  #expect(LoopbackVerificationState.checking.presentationColor == .neutral)
  #expect(LoopbackVerificationState.verified.presentationColor == .green)
  #expect(LoopbackVerificationState.failed.presentationColor == .red)
  #expect(LocalSyncVerification.intervalSeconds == 300)
}

@Test func recentTasksAreCombinedNewestFirstAndStableForTies() {
  let firstProject = Project(name: "First")
  let secondProject = Project(name: "Second")
  var older = WorkItem(projectID: firstProject.id, title: "Older")
  older.updatedAt = Date(timeIntervalSince1970: 10)
  var tiedLaterID = WorkItem(projectID: secondProject.id, title: "Tied later ID")
  tiedLaterID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  tiedLaterID.updatedAt = Date(timeIntervalSince1970: 20)
  var tiedEarlierID = WorkItem(projectID: firstProject.id, title: "Tied earlier ID")
  tiedEarlierID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  tiedEarlierID.updatedAt = tiedLaterID.updatedAt
  var orphaned = WorkItem(projectID: UUID(), title: "Missing project")
  orphaned.updatedAt = Date(timeIntervalSince1970: 30)
  var completed = WorkItem(projectID: secondProject.id, title: "Completed")
  completed.completed = true
  completed.updatedAt = Date(timeIntervalSince1970: 15)

  var library = Library()
  library.projects = [firstProject, secondProject]
  library.tasks = [older, tiedLaterID, tiedEarlierID, orphaned, completed]

  #expect(
    library.recentTasks.map(\.id) == [tiedEarlierID.id, tiedLaterID.id, completed.id, older.id])
}

@Test func shortTaskIDsAllocateAcrossProjectsAndAreNeverReused() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let firstProject = Project(name: "First")
  let secondProject = Project(name: "Second")
  _ = try await repository.apply(.createProject(firstProject))
  _ = try await repository.apply(.createProject(secondProject))

  var first = WorkItem(projectID: firstProject.id, title: "First task")
  first.shortID = 900  // A client candidate is never authoritative.
  let firstLibrary = try await repository.apply(.createTask(first))
  #expect(firstLibrary.tasks.first?.shortID == 1)
  var second = WorkItem(projectID: secondProject.id, title: "Second task")
  let secondLibrary = try await repository.apply(.createTask(second))
  second = try #require(secondLibrary.tasks.first(where: { $0.id == second.id }))
  #expect(second.shortID == 2)
  #expect(Set(secondLibrary.tasks.compactMap(\.shortID)).count == 2)

  _ = try await repository.apply(.deleteTask(first.id, expectedRevision: first.revision))
  let third = WorkItem(projectID: firstProject.id, title: "Third task")
  let finalLibrary = try await repository.apply(.createTask(third))
  #expect(finalLibrary.tasks.first(where: { $0.id == third.id })?.shortID == 3)
  #expect(finalLibrary.taskShortIDHighWaterMark == 3)
}

@Test func shortTaskIDHighWaterMarkSurvivesRepositoryRestart() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChaseShortIDs-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let storeURL = root.appendingPathComponent("Library.sqlite")
  var repository: LibraryRepository? = try LibraryRepository(url: storeURL)
  let project = Project(name: "Persistent IDs")
  _ = try await repository!.apply(.createProject(project))
  let first = WorkItem(projectID: project.id, title: "First")
  let firstState = try await repository!.apply(.createTask(first))
  #expect(firstState.tasks.first?.shortID == 1)
  _ = try await repository!.apply(.deleteTask(first.id, expectedRevision: first.revision))
  repository = nil

  repository = try LibraryRepository(url: storeURL)
  let afterRestart = try await repository!.load()
  #expect(afterRestart.taskShortIDHighWaterMark == 1)
  let second = WorkItem(projectID: project.id, title: "Second")
  let nextState = try await repository!.apply(.createTask(second))
  #expect(nextState.tasks.first?.shortID == 2)
  repository = nil
}

@Test func legacyAndMalformedShortTaskIDsRepairDeterministically() throws {
  let project = Project(name: "Migration")
  var earlier = WorkItem(projectID: project.id, title: "Earlier")
  earlier.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  earlier.createdAt = Date(timeIntervalSince1970: 1)
  earlier.shortID = 4
  var duplicate = WorkItem(projectID: project.id, title: "Duplicate")
  duplicate.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  duplicate.createdAt = Date(timeIntervalSince1970: 1)
  duplicate.shortID = 4
  var missing = WorkItem(projectID: project.id, title: "Missing")
  missing.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
  missing.createdAt = Date(timeIntervalSince1970: 2)
  var library = Library()
  library.projects = [project]
  library.tasks = [missing, duplicate, earlier]
  library.taskShortIDHighWaterMark = 2

  let encoded = try JSONEncoder().encode(library)
  let repaired = try JSONDecoder().decode(Library.self, from: encoded)
  #expect(repaired.tasks.first(where: { $0.id == earlier.id })?.shortID == 4)
  #expect(repaired.tasks.first(where: { $0.id == duplicate.id })?.shortID == 5)
  #expect(repaired.tasks.first(where: { $0.id == missing.id })?.shortID == 6)
  #expect(repaired.taskShortIDHighWaterMark == 6)
  let repairedIDs = repaired.tasks.map(\.id).sorted { $0.uuidString < $1.uuidString }
  let originalIDs = library.tasks.map(\.id).sorted { $0.uuidString < $1.uuidString }
  #expect(repairedIDs == originalIDs)
  try repaired.validate()

  var legacyObject = try #require(
    JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  legacyObject.removeValue(forKey: "taskShortIDHighWaterMark")
  var legacyTasks = try #require(legacyObject["tasks"] as? [[String: Any]])
  for index in legacyTasks.indices { legacyTasks[index].removeValue(forKey: "shortID") }
  legacyObject["tasks"] = legacyTasks
  let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
  let legacyLibrary = try JSONDecoder().decode(Library.self, from: legacyData)
  #expect(legacyLibrary.tasks.first(where: { $0.id == earlier.id })?.shortID == 1)
  #expect(legacyLibrary.tasks.first(where: { $0.id == duplicate.id })?.shortID == 2)
  #expect(legacyLibrary.tasks.first(where: { $0.id == missing.id })?.shortID == 3)
}

@Test func syncSnapshotCarriesCanonicalTaskIDAndAllocatorState() throws {
  let project = Project(name: "Sync IDs")
  var task = WorkItem(projectID: project.id, title: "Canonical task")
  task.shortID = 23
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library.taskShortIDHighWaterMark = 30
  let snapshot = SyncSnapshot(libraryID: UUID(), sequence: 3, library: library)
  let decoded = try JSONDecoder.syncDecoder.decode(
    SyncSnapshot.self, from: JSONEncoder.syncEncoder.encode(snapshot))
  let replica = try decoded.replica()
  #expect(replica.tasks.first?.id == task.id)
  #expect(replica.tasks.first?.shortID == 23)
  #expect(replica.taskShortIDHighWaterMark == 30)
  #expect(SyncProtocol.version == 16)
}

@Test func phonePlanFeedbackDirectRequestPreservesExactFeedbackAndRequestID() throws {
  let requestID = UUID()
  let taskID = UUID()
  let feedback = "Keep this exact line.\n\nAdd **a second section**.  "
  let request = SyncDirectRequest.replanWithFeedback(
    requestID: requestID, taskID: taskID, expectedRevision: 7, feedback: feedback)
  let decoded = try JSONDecoder.syncDecoder.decode(
    SyncDirectRequest.self, from: JSONEncoder.syncEncoder.encode(request))
  guard
    case .replanWithFeedback(let decodedRequestID, let decodedTaskID, let revision, let text) =
      decoded
  else {
    Issue.record("The phone feedback request did not round-trip as its direct request case")
    return
  }
  #expect(decodedRequestID == requestID)
  #expect(decodedTaskID == taskID)
  #expect(revision == 7)
  #expect(text == feedback)
}

@Test func projectGitChangePresentationIncludesStagedUnstagedAndUntrackedFiles() {
  let clean = SyncGitStatus(
    branch: "main", head: "abc", changedFileCount: 0, stagedFileCount: 0,
    unstagedFileCount: 0, untrackedFileCount: 0, isEmptyRepository: false)
  #expect(!clean.hasChanges)
  let dirty = SyncGitStatus(
    branch: "main", head: "abc", changedFileCount: 3, stagedFileCount: 1,
    unstagedFileCount: 1, untrackedFileCount: 1, isEmptyRepository: false)
  #expect(dirty.hasChanges)
  #expect(
    dirty.changedFileCount
      == dirty.stagedFileCount + dirty.unstagedFileCount + dirty.untrackedFileCount)
}

@Test func explicitTaskRunPreservesPlacementAndSnapshotsProjectSettings() throws {
  var project = Project(name: "Manual runner", directory: "/tmp/manual-runner")
  project.automationEnabled = false
  project.usesWorktrees = true
  project.executionProfile = .fullAccessNoPrompts
  var task = WorkItem(projectID: project.id, title: "Run this now", stage: .next)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  let phoneRequestID = UUID()
  let phoneFeedback = "Preserve this exact feedback.\nUse a concise checklist."

  library = try BoardReducer.apply(
    .runTaskNow(
      task.id, expectedRevision: task.revision, kind: .planning,
      configuration: fixtureModelConfiguration, phoneRequestID: phoneRequestID,
      phoneRequestDigest: "fixture-digest", handoffContext: phoneFeedback),
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
  #expect(library.runs[0].phoneRequestID == phoneRequestID)
  #expect(library.runs[0].phoneRequestDigest == "fixture-digest")
  #expect(library.runs[0].handoffContext == phoneFeedback)
  #expect(library.runs[0].modelConfiguration == fixtureModelConfiguration)

  let restored = try JSONDecoder().decode(
    Library.self, from: JSONEncoder().encode(library))
  #expect(restored.runs.first?.phoneRequestID == phoneRequestID)
  #expect(restored.runs.first?.phoneRequestDigest == "fixture-digest")
  #expect(restored.runs.first?.handoffContext == phoneFeedback)

  #expect(!library.projects[0].automationEnabled)
  #expect(library.runs[0].status == .queued)
}

@Test func taskAttachmentFilesStayOutsideSnapshotAndArchiveSeparatesImageBytes() throws {
  let png = try #require(
    Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j78kAAAAASUVORK5CYII="
    ))
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let attachment = try TaskAttachmentFiles.save(
    png, id: UUID(), displayName: "screen.png", mediaType: "image/png", baseURL: root)
  #expect(try TaskAttachmentFiles.read(attachment, baseURL: root) == png)

  let project = Project(name: "Attachment")
  var task = WorkItem(projectID: project.id, title: "Keep a screenshot")
  task.attachments = [attachment]
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  let snapshotData = try JSONEncoder.syncEncoder.encode(
    SyncSnapshot(libraryID: UUID(), sequence: 1, library: library))
  #expect(snapshotData.range(of: png) == nil)
  let snapshot = try JSONDecoder.syncDecoder.decode(SyncSnapshot.self, from: snapshotData)
  #expect(snapshot.tasks.first?.attachments.first?.sha256 == attachment.sha256)

  let archive = try BackupArchive.encode(library, baseURL: root)
  let restored = try BackupArchive.decode(archive)
  #expect(restored.library.tasks.first?.attachments == [attachment])
  #expect(restored.assets[attachment.id] == png)
}

@Test func oldTaskJsonDecodesWithNoAttachmentsAndInvalidImagesAreRejected() throws {
  let legacy = Data(
    "{\"projectID\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"Legacy\"}".utf8)
  let task = try JSONDecoder().decode(WorkItem.self, from: legacy)
  #expect(task.attachments.isEmpty)
  #expect(throws: BoardError.self) {
    try TaskAttachmentFiles.validate(Data([0x89, 0x50, 0x4e, 0x47]), mediaType: "image/png")
  }
}

@Test func attachmentMetadataMutationIsRevisionCheckedAndSyncedWithoutImageBytes() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Attachment sync")
  _ = try await repository.apply(.createProject(project))
  var task = WorkItem(projectID: project.id, title: "Attach image")
  _ = try await repository.apply(.createTask(task))
  let attachment = TaskAttachment(
    displayName: "shot.jpg", mediaType: "image/jpeg", byteCount: 3,
    sha256: String(repeating: "a", count: 64), transferState: .pendingUpload)
  let state = try await repository.syncStateSnapshot()
  task = try #require(state.library.tasks.first)
  let envelope = SyncEnvelope(
    libraryID: state.libraryID, deviceID: UUID(), expectedRevision: task.revision,
    command: .setTaskAttachments(id: task.id, attachments: [attachment]))
  guard case .applied(_, let snapshot) = try await repository.applyRemote(envelope) else {
    Issue.record("The attachment metadata update should be accepted.")
    return
  }
  #expect(snapshot.tasks.first?.attachments.first?.sha256 == attachment.sha256)
  let snapshotJSON = try JSONEncoder.syncEncoder.encode(snapshot)
  #expect(snapshotJSON.range(of: Data("image-bytes".utf8)) == nil)

  var stale = envelope
  stale.operationID = UUID()
  stale.clientSequence = 2
  stale.expectedRevision = task.revision
  guard case .conflict = try await repository.applyRemote(stale) else {
    Issue.record("A stale attachment edit should conflict.")
    return
  }
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

@Test func mobileTaskHandoffPromptMakesPlanningAndImplementationIntentExplicit() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("StageChaseMobilePrompt-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let project = Project(name: "Mobile prompt project", directory: root.path)
  var task = WorkItem(projectID: project.id, title: "Plan a mobile task")
  task.notes = "Keep the copied task context."

  #expect(MobileTaskHandoffPrompt.primaryIntent(for: task) == .planning)
  let planningPrompt = MobileTaskHandoffPrompt.make(
    for: task, project: project, intent: .planning)
  #expect(planningPrompt.contains("Create or revise only the plan"))
  #expect(planningPrompt.contains("\(project.id.uuidString.lowercased())"))
  #expect(planningPrompt.contains("\(task.id.uuidString.lowercased())"))
  #expect(planningPrompt.contains("Keep the copied task context."))
  #expect(!planningPrompt.contains("Execute this existing task"))

  let implementationPrompt = MobileTaskHandoffPrompt.make(
    for: task, project: project, intent: .implementation)
  #expect(implementationPrompt.contains("Execute this existing task"))
  #expect(implementationPrompt.contains("activity_kind: \"implementation\""))
  #expect(implementationPrompt.contains("Keep the copied task context."))
  #expect(!implementationPrompt.contains("Create or revise only the plan"))

  task.section = .planning
  task.status = .planning
  #expect(MobileTaskHandoffPrompt.primaryIntent(for: task) == .planning)

  task.section = .implementing
  #expect(MobileTaskHandoffPrompt.primaryIntent(for: task) == .implementation)

  task.section = .planning
  task.status = .planApproved
  #expect(MobileTaskHandoffPrompt.primaryIntent(for: task) == .implementation)

  task.planPath = "custom/plans/mobile-task.md"
  let planURL = root.appendingPathComponent(task.planPath!)
  try FileManager.default.createDirectory(
    at: planURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  try "## Saved plan\n\nUse this plan.".write(to: planURL, atomically: true, encoding: .utf8)
  #expect(
    MobileTaskHandoffPrompt.make(for: task, project: project, intent: .planning)
      .contains("Review the existing plan"))
  #expect(
    MobileTaskHandoffPrompt.make(for: task, project: project, intent: .implementation)
      .contains("Read and follow the existing task plan"))

  try FileManager.default.removeItem(at: planURL)
  #expect(
    MobileTaskHandoffPrompt.make(for: task, project: project, intent: .planning)
      .contains("If an attached path is present but its file is unreadable"))
  #expect(
    MobileTaskHandoffPrompt.make(for: task, project: project, intent: .implementation)
      .contains("No readable saved plan is attached"))
}

@Test func creatingProjectsNeverEditsExistingProject() throws {
  let a = Project(name: "First")
  let b = Project(name: "Second")
  var library = try BoardReducer.apply(.createProject(a), to: Library())
  library = try BoardReducer.apply(.createProject(b), to: library)
  #expect(library.projects.map(\.id) == [a.id, b.id])
  #expect(library.projects.map(\.projectOrder) == [0, 1])
  var edited = b
  edited.name = "Renamed"
  library = try BoardReducer.apply(.editProject(edited), to: library)
  #expect(library.projects[0].id == a.id)
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
  #expect(json.contains("hasSavedPlan"))
  let replica = try snapshot.replica()
  #expect(replica.projects[0].id == project.id)
  #expect(replica.projects[0].automationEnabled)
  #expect(replica.projects[0].usesWorktrees)
  #expect(replica.projects[0].modelOverride == project.modelOverride)
  #expect(replica.projects[0].executionProfile == .fullAccessNoPrompts)
  #expect(replica.projects[0].favoriteMakeTargets == project.favoriteMakeTargets)
  #expect(replica.tasks[0].notes == task.notes)
  #expect(replica.tasks[0].planPath == nil)
  #expect(replica.tasks[0].hasSavedPlan)
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

  #expect(decoded.version == 16)
  #expect(decoded.runs.first(where: { $0.id == linkedRun.id })?.threadID == "desktop-thread-123")
  #expect(decoded.runs.first(where: { $0.id == unlinkedRun.id })?.threadID == nil)
  #expect(replica.runs.first(where: { $0.id == linkedRun.id })?.threadID == "desktop-thread-123")
  #expect(replica.runs.first(where: { $0.id == unlinkedRun.id })?.threadID == nil)
}

@Test func favoriteAndModelTagDefaultsRoundTripAndReplicate() throws {
  let projectID = UUID()
  let legacyItemData = Data("{\"projectID\":\"\(projectID.uuidString)\",\"title\":\"Legacy\"}".utf8)
  let legacyItem = try JSONDecoder().decode(WorkItem.self, from: legacyItemData)
  #expect(!legacyItem.isFavorite)
  #expect(legacyItem.modelTag == nil)

  let project = Project(name: "Tags")
  var item = WorkItem(projectID: project.id, title: "Tagged")
  item.isFavorite = true
  item.modelTag = .high
  item.priority = .high
  item.revision = 8
  item.updatedAt = Date(timeIntervalSince1970: 100)
  let encodedItem = try JSONEncoder().encode(item)
  #expect(try JSONDecoder().decode(WorkItem.self, from: encodedItem) == item)

  var library = Library()
  library.projects = [project]
  library.tasks = [item]
  let snapshot = SyncSnapshot(libraryID: UUID(), sequence: 4, library: library)
  let decodedSnapshot = try JSONDecoder.syncDecoder.decode(
    SyncSnapshot.self, from: JSONEncoder.syncEncoder.encode(snapshot))
  let replica = try decodedSnapshot.replica()
  #expect(replica.tasks.first?.id == item.id)
  #expect(replica.tasks.first?.revision == item.revision)
  #expect(replica.tasks.first?.updatedAt == item.updatedAt)
  #expect(replica.tasks.first?.isFavorite == true)
  #expect(replica.tasks.first?.modelTag == .high)
  #expect(replica.tasks.first?.priority == .high)

  var legacySyncTask = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(SyncTask(item))) as? [String: Any])
  legacySyncTask.removeValue(forKey: "isFavorite")
  legacySyncTask.removeValue(forKey: "modelTag")
  let oldSyncTask = try JSONDecoder().decode(
    SyncTask.self, from: JSONSerialization.data(withJSONObject: legacySyncTask))
  #expect(!oldSyncTask.isFavorite)
  #expect(oldSyncTask.modelTag == nil)
}

@Test func favoriteAndModelTagMutationsAreRevisionCheckedAndIndependent() throws {
  let project = Project(name: "Tags")
  var item = WorkItem(projectID: project.id, title: "Task")
  item.priority = .low
  var library = Library()
  library.projects = [project]
  library.tasks = [item]

  let favorited = try BoardReducer.apply(
    .setTaskFavorite(item.id, true, expectedRevision: 0), to: library)
  #expect(favorited.tasks[0].isFavorite)
  #expect(favorited.tasks[0].revision == 1)
  #expect(favorited.tasks[0].priority == .low)
  let tagged = try BoardReducer.apply(
    .setTaskModelTag(item.id, .medium, expectedRevision: 1), to: favorited)
  #expect(tagged.tasks[0].modelTag == .medium)
  #expect(tagged.tasks[0].revision == 2)
  let cleared = try BoardReducer.apply(
    .setTaskModelTag(item.id, nil, expectedRevision: 2), to: tagged)
  #expect(cleared.tasks[0].modelTag == nil)
  let unstarred = try BoardReducer.apply(
    .setTaskFavorite(item.id, false, expectedRevision: 3), to: cleared)
  #expect(!unstarred.tasks[0].isFavorite)
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.setTaskFavorite(item.id, true, expectedRevision: 0), to: unstarred)
  }
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
  #expect(firstSnapshot.tasks.first?.shortID == 1)
  #expect(firstSnapshot.taskShortIDHighWaterMark == 1)

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
  #expect(edited.tasks[0].notes == "saved")

  let nextEdit = SyncEnvelope(
    libraryID: initial.libraryID, deviceID: deviceID, clientSequence: 3,
    expectedRevision: edited.tasks[0].revision,
    command: .editTask(id: taskID, title: "Latest title", notes: "Latest notes"))
  guard case .applied(_, let latest) = try await repository.applyRemote(nextEdit)
  else {
    Issue.record("A subsequent combined title and notes edit must use the advanced revision")
    return
  }
  #expect(latest.tasks[0].revision == edited.tasks[0].revision + 1)
  #expect(latest.tasks[0].title == "Latest title")
  #expect(latest.tasks[0].notes == "Latest notes")

  let stale = SyncEnvelope(
    libraryID: initial.libraryID, deviceID: deviceID, clientSequence: 4,
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
    libraryID: initial.libraryID, deviceID: deviceID, clientSequence: 5,
    expectedRevision: 2, command: .editTask(id: taskID, title: "Later", notes: ""))
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

@Test func phonePlanApprovalUsesRevisionCheckedSyncCommand() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Phone approval")
  _ = try await repository.apply(.createProject(project))
  var task = WorkItem(projectID: project.id, title: "Approve this plan", stage: .next)
  task.planPath = "to-do/plan.md"
  _ = try await repository.apply(.createTask(task))
  let state = try await repository.syncStateSnapshot()
  let command = SyncEnvelope(
    libraryID: state.libraryID, deviceID: UUID(), clientSequence: 1,
    expectedRevision: task.revision, command: .approvePlan(id: task.id))

  guard case .applied(_, let approved) = try await repository.applyRemote(command) else {
    Issue.record("Expected revision-matched plan approval to apply")
    return
  }
  let saved = try #require(approved.tasks.first)
  #expect(saved.status == .planApproved)
  #expect(saved.section == .planning)
  #expect(saved.completed == false)

  var stale = command
  stale.clientSequence = 2
  guard case .rejected = try await repository.applyRemote(stale) else {
    Issue.record("A repeated approval must be rejected after status changes")
    return
  }
}

@Test func phoneStatusChangeIsRevisionCheckedAndDoesNotMoveOrCompleteTask() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Phone status")
  _ = try await repository.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Change status", stage: .next)
  _ = try await repository.apply(.createTask(task))
  let state = try await repository.syncStateSnapshot()
  let change = SyncEnvelope(
    libraryID: state.libraryID, deviceID: UUID(), clientSequence: 1,
    expectedRevision: task.revision,
    command: .setTaskStatus(id: task.id, status: .reviewing))

  guard case .applied(_, let changed) = try await repository.applyRemote(change) else {
    Issue.record("Expected revision-matched phone status change to apply")
    return
  }
  let saved = try #require(changed.tasks.first)
  #expect(saved.status == .reviewing)
  #expect(saved.section == .planning)
  #expect(saved.completed == false)
  #expect(saved.revision == 1)

  var stale = change
  stale.clientSequence = 2
  let staleResult = try await repository.applyRemote(stale)
  if case .applied = staleResult {
    Issue.record("A stale status change must not be applied")
  }
  let afterStale = try await repository.load()
  #expect(afterStale.tasks.first?.status == .reviewing)
}

@Test func phoneFavoriteAndModelTagCommandsSyncWithRevisionChecks() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Phone tags")
  _ = try await repository.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Tag this task")
  _ = try await repository.apply(.createTask(task))
  let state = try await repository.syncStateSnapshot()
  let deviceID = UUID()
  let favorite = SyncEnvelope(
    libraryID: state.libraryID, deviceID: deviceID, clientSequence: 1,
    expectedRevision: task.revision,
    command: .setTaskFavorite(id: task.id, isFavorite: true))
  guard case .applied(_, let favorited) = try await repository.applyRemote(favorite) else {
    Issue.record("Expected the phone favorite command to apply")
    return
  }
  let tag = SyncEnvelope(
    libraryID: state.libraryID, deviceID: deviceID, clientSequence: 2,
    expectedRevision: 1, command: .setTaskModelTag(id: task.id, modelTag: .high))
  guard case .applied(_, let tagged) = try await repository.applyRemote(tag) else {
    Issue.record("Expected the phone model-tag command to apply")
    return
  }
  #expect(favorited.tasks.first?.isFavorite == true)
  #expect(tagged.tasks.first?.isFavorite == true)
  #expect(tagged.tasks.first?.modelTag == .high)
  #expect(tagged.tasks.first?.revision == 2)

  let stale = SyncEnvelope(
    libraryID: state.libraryID, deviceID: UUID(), clientSequence: 1,
    expectedRevision: 0, command: .setTaskFavorite(id: task.id, isFavorite: false))
  guard case .conflict = try await repository.applyRemote(stale) else {
    Issue.record("A stale favorite command must not overwrite newer task state")
    return
  }
  let final = try await repository.load()
  #expect(final.tasks.first?.isFavorite == true)
  #expect(final.tasks.first?.modelTag == .high)
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
  #expect(snapshot.version == 16)
  var oldSnapshot = snapshot
  oldSnapshot.version = SyncProtocol.version - 1
  #expect(throws: BoardError.self) { try oldSnapshot.replica() }
}

@Test func retiredUnreadAcknowledgmentsAreRejectedWithoutChangingLibrary() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "No unread state")
  _ = try await repository.apply(.createProject(project))
  let task = WorkItem(projectID: project.id, title: "Still available")
  _ = try await repository.apply(.createTask(task))
  let before = try await repository.load()
  let envelope = SyncEnvelope(
    libraryID: try await repository.syncStateSnapshot().libraryID, deviceID: UUID(),
    expectedRevision: task.revision,
    command: .acknowledgeTaskChanges(
      taskID: task.id, marker: RetiredUnreadMarker(date: .now, activityID: UUID())))
  let result = try await repository.applyRemote(envelope)
  guard case .rejected(let message) = result else {
    Issue.record("Retired unread acknowledgments must be rejected")
    return
  }
  #expect(message.localizedCaseInsensitiveContains("retired"))
  #expect(try await repository.load() == before)
}

@Test func projectSidebarCountsOnlyOpenTasksAndSeparatesReviewStates() {
  let project = Project(name: "Counts")
  var plan = WorkItem(projectID: project.id, title: "Plan", stage: .planned)
  plan.status = .planApproved
  var code = WorkItem(projectID: project.id, title: "Code", stage: .implementation)
  code.status = .reviewing
  let other = WorkItem(projectID: project.id, title: "Other")
  var completedReview = WorkItem(projectID: project.id, title: "Completed", stage: .implementation)
  completedReview.status = .reviewing
  completedReview.completed = true
  var library = Library()
  library.projects = [project]
  library.tasks = [plan, code, other, completedReview]
  let counts = library.sidebarCounts(for: project.id)
  #expect(counts.total == 3)
  #expect(counts.planReview == 1)
  #expect(counts.codeReview == 1)
  #expect(library.sidebarCounts(for: UUID()).total == 0)
}

@Test func oldActivityAndSnapshotUnreadMetadataDecodeWithoutRecreatingState() throws {
  let project = Project(name: "Legacy")
  let task = WorkItem(projectID: project.id, title: "Legacy task")
  let activity = Activity("Moved", projectID: project.id, taskID: task.id)
  var activityJSON = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(activity)) as? [String: Any])
  activityJSON["taskChange"] = "stageChanged"
  let decodedActivity = try JSONDecoder().decode(
    Activity.self, from: JSONSerialization.data(withJSONObject: activityJSON))
  #expect(decodedActivity.message == "Moved")

  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  let snapshot = SyncSnapshot(libraryID: UUID(), sequence: 1, library: library)
  var snapshotJSON = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder.syncEncoder.encode(snapshot)) as? [String: Any])
  snapshotJSON["taskReadMarkers"] = [
    task.id.uuidString: [
      "date": Date.now.timeIntervalSince1970
    ]
  ]
  snapshotJSON["projectReadMarkers"] = [
    project.id.uuidString: [
      "date": Date.now.timeIntervalSince1970
    ]
  ]
  let decodedSnapshot = try JSONDecoder.syncDecoder.decode(
    SyncSnapshot.self, from: JSONSerialization.data(withJSONObject: snapshotJSON))
  #expect(try decodedSnapshot.replica().tasks.first?.id == task.id)
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
  #expect(first.library.tasks.first?.shortID == 1)
  #expect(replay.library.tasks.first?.shortID == 1)
  #expect(replay.library.taskShortIDHighWaterMark == 1)
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
  #expect(library.tasks[0].status == .planApproved)
  var activeRun = library.runs[0]
  activeRun.status = .running
  library = try BoardReducer.apply(.updateRun(activeRun), to: library)
  library = try BoardReducer.apply(.finishRun(library.runs[0].id, planPath: nil), to: library)
  #expect(library.tasks[0].stage == .review)
  #expect(library.tasks[0].section == .implementing)
  #expect(library.tasks[0].completed)
  #expect(library.tasks[0].status == .planApproved)
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
  #expect(library.tasks[0].status == .planning)
  #expect(!library.tasks[0].completed)
  #expect(library.runs[0].status == .succeeded)
}

@Test func everyTaskStatusHasAnIconAndSemanticBadgeColor() {
  let styles = TaskStatus.allCases.map(\.badgeStyle)
  #expect(styles.count == 8)
  #expect(styles.allSatisfy { !$0.symbol.isEmpty })
  #expect(Set(styles.map(\.symbol)).count == TaskStatus.allCases.count)
  #expect(TaskStatus.planning.badgeStyle.color == .purple)
  #expect(TaskStatus.building.badgeStyle.color == .purple)
  #expect(TaskStatus.planApproved.badgeStyle.color == .blue)
  #expect(TaskStatus.reviewing.badgeStyle.color == .green)
  #expect(TaskStatus.triage.badgeStyle.color == .secondary)
  #expect(TaskStatus.quota.badgeStyle.color == .orange)
}

@Test func successfulImplementationMovesDirectlyToReviewingAndCompletionIsIndependent() throws {
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
  #expect(library.tasks[0].status == .reviewing)
  #expect(!library.tasks[0].completed)
  #expect(library.runs[0].status == .succeeded)

  library = try BoardReducer.apply(.complete(task.id, true, expectedRevision: 1), to: library)
  #expect(library.tasks[0].status == .reviewing)
  #expect(library.tasks[0].completed)
}

@Test func planApprovalRequiresSavedPlanAndChangesOnlyStatus() throws {
  let project = Project(name: "Approval")
  var task = WorkItem(projectID: project.id, title: "Plan it", stage: .next)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]

  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.approvePlan(task.id, expectedRevision: 0), to: library)
  }

  task.planPath = "to-do/plan.md"
  library.tasks[0] = task
  let approved = try BoardReducer.apply(.approvePlan(task.id, expectedRevision: 0), to: library)
  #expect(approved.tasks[0].status == .planApproved)
  #expect(approved.tasks[0].section == .planning)
  #expect(approved.tasks[0].stage == .next)
  #expect(!approved.tasks[0].completed)
  #expect(approved.tasks[0].revision == 1)
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.approvePlan(task.id, expectedRevision: 0), to: approved)
  }
}

@Test func manualStatusChangeLeavesSectionAndCompletionAlone() throws {
  let project = Project(name: "Manual status")
  var task = WorkItem(projectID: project.id, title: "Change status", stage: .next)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]

  library = try BoardReducer.apply(
    .setStatus(task.id, .reviewing, expectedRevision: task.revision), to: library)
  task = try #require(library.tasks.first)
  #expect(task.status == .reviewing)
  #expect(task.section == .planning)
  #expect(!task.completed)
  #expect(task.revision == 1)
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.setStatus(task.id, .error, expectedRevision: 0), to: library)
  }
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

@Test func legacyDoneStatusDecodesWithoutChangingCompletionFlag() throws {
  let payload: [String: Any] = [
    "id": "00000000-0000-0000-0000-000000000010",
    "projectID": "00000000-0000-0000-0000-000000000001",
    "title": "Legacy", "notes": "", "stage": "review", "rank": 0,
    "revision": 3, "createdAt": 0, "updatedAt": 0, "status": "done", "completed": true,
  ]
  let done = try JSONDecoder().decode(
    WorkItem.self, from: JSONSerialization.data(withJSONObject: payload))
  #expect(done.status == .reviewing)
  #expect(done.completed)
  #expect(done.revision == 3)

  let ready = try JSONDecoder().decode(
    TaskStatus.self, from: JSONEncoder().encode("ready"))
  let review = try JSONDecoder().decode(
    TaskStatus.self, from: JSONEncoder().encode("review"))
  #expect(ready == .planApproved)
  #expect(review == .reviewing)
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

@Test func planningAndImplementingPrioritizeAttentionThenRecentUpdates() throws {
  let project = Project(name: "Readiness")
  var waiting = WorkItem(projectID: project.id, title: "Waiting", stage: .next)
  waiting.status = .waiting
  waiting.updatedAt = Date(timeIntervalSince1970: 10)
  var error = WorkItem(projectID: project.id, title: "Error", stage: .next)
  error.status = .error
  error.updatedAt = Date(timeIntervalSince1970: 50)
  var quota = WorkItem(projectID: project.id, title: "Quota", stage: .next)
  quota.status = .quota
  quota.updatedAt = Date(timeIntervalSince1970: 40)
  var reviewing = WorkItem(projectID: project.id, title: "Reviewing", stage: .next)
  reviewing.status = .reviewing
  reviewing.updatedAt = Date(timeIntervalSince1970: 60)
  var planApproved = WorkItem(projectID: project.id, title: "Plan Approved", stage: .next)
  planApproved.status = .planApproved
  planApproved.updatedAt = Date(timeIntervalSince1970: 5)
  var olderPlanning = WorkItem(projectID: project.id, title: "Older planning", stage: .next)
  olderPlanning.updatedAt = Date(timeIntervalSince1970: 20)
  var newerPlanning = WorkItem(projectID: project.id, title: "Newer planning", stage: .next)
  newerPlanning.updatedAt = Date(timeIntervalSince1970: 30)
  newerPlanning.priority = .low
  olderPlanning.priority = .high
  var tiedEarlierID = WorkItem(projectID: project.id, title: "Tie A", stage: .next)
  tiedEarlierID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  tiedEarlierID.updatedAt = Date(timeIntervalSince1970: 70)
  var tiedLaterID = WorkItem(projectID: project.id, title: "Tie B", stage: .next)
  tiedLaterID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  tiedLaterID.updatedAt = tiedEarlierID.updatedAt

  var implementingWaiting = WorkItem(
    projectID: project.id, title: "Implementing waiting", stage: .implementation)
  implementingWaiting.status = .waiting
  implementingWaiting.updatedAt = Date(timeIntervalSince1970: 10)
  var implementingBuilding = WorkItem(
    projectID: project.id, title: "Implementing building", stage: .implementation)
  implementingBuilding.updatedAt = Date(timeIntervalSince1970: 90)
  var library = Library()
  library.projects = [project]
  library.tasks = [
    newerPlanning, reviewing, implementingBuilding, planApproved, quota, tiedLaterID, olderPlanning,
    implementingWaiting, error, waiting, tiedEarlierID,
  ]

  #expect(
    library.items(in: project.id, section: .planning).map(\.title) == [
      "Waiting", "Error", "Quota", "Reviewing", "Plan Approved", "Tie A", "Tie B",
      "Newer planning", "Older planning",
    ])
  #expect(
    library.items(in: project.id, section: .implementing).map(\.title) == [
      "Implementing waiting", "Implementing building",
    ])
  library = try BoardReducer.apply(.complete(reviewing.id, true, expectedRevision: 0), to: library)
  let completedReview = try #require(library.tasks.first(where: { $0.id == reviewing.id }))
  #expect(completedReview.completed)
  #expect(completedReview.status == .reviewing)
  #expect(completedReview.section == .planning)
}

@Test func inboxSortsByNewestCreationWithStableTiesAndCompletionFilter() {
  let project = Project(name: "Inbox order")
  var older = WorkItem(projectID: project.id, title: "Older")
  older.createdAt = Date(timeIntervalSince1970: 10)
  older.status = .waiting
  older.priority = .high
  older.rank = 0
  var tiedLaterID = WorkItem(projectID: project.id, title: "Tie B")
  tiedLaterID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  tiedLaterID.createdAt = Date(timeIntervalSince1970: 20)
  tiedLaterID.status = .error
  var tiedEarlierID = WorkItem(projectID: project.id, title: "Tie A")
  tiedEarlierID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  tiedEarlierID.createdAt = tiedLaterID.createdAt
  tiedEarlierID.status = .triage
  var newer = WorkItem(projectID: project.id, title: "Newer")
  newer.createdAt = Date(timeIntervalSince1970: 30)
  newer.status = .triage
  newer.priority = .low
  var completed = WorkItem(projectID: project.id, title: "Completed")
  completed.createdAt = Date(timeIntervalSince1970: 40)
  completed.completed = true

  var library = Library()
  library.projects = [project]
  library.tasks = [older, tiedLaterID, completed, newer, tiedEarlierID]

  #expect(
    library.items(in: project.id, section: .inbox).map(\.title)
      == ["Newer", "Tie A", "Tie B", "Older"])
  #expect(
    library.items(in: project.id, section: .inbox, completed: true).map(\.title)
      == ["Completed", "Newer", "Tie A", "Tie B", "Older"])
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

@Test func projectSoftDeletionPersistsAndRestoresAllRelatedDataAndFiles() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let sentinel = root.appendingPathComponent("repository-file.txt")
  try Data("keep this file".utf8).write(to: sentinel)
  let png = try #require(
    Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j78kAAAAASUVORK5CYII="
    ))
  let attachment = try TaskAttachmentFiles.save(
    png, id: UUID(), displayName: "screen.png", mediaType: "image/png", baseURL: root)
  let store = root.appendingPathComponent("Library.sqlite")
  var repository: LibraryRepository? = try LibraryRepository(url: store)
  var project = Project(name: "Retained", directory: root.path)
  project.projectOrder = 0
  project.automationEnabled = true
  project.favoriteMakeTargets = ["build"]
  _ = try await repository!.apply(.createProject(project))
  var task = WorkItem(projectID: project.id, title: "Retained task")
  task.notes = "Keep notes"
  task.planPath = "to-do/keep.md"
  task.attachments = [attachment]
  _ = try await repository!.apply(.createTask(task))
  var run = AgentRun(task: task, kind: .task)
  run.status = .readyForHandoff
  _ = try await repository!.apply(.createManualRun(run))
  run.status = .succeeded
  let before = try await repository!.apply(.updateRun(run))
  let deleted = try await repository!.apply(
    .setProjectDeleted(project.id, true, expectedRevision: 0))
  #expect(deleted.activeProjects.isEmpty)
  #expect(deleted.deletedProjects.count == 1)
  #expect(deleted.tasks == before.tasks)
  #expect(deleted.runs == before.runs)
  #expect(deleted.activity.dropLast() == before.activity[...])
  #expect(deleted.taskShortIDHighWaterMark == before.taskShortIDHighWaterMark)
  #expect(deleted.recentTasks.isEmpty)
  #expect(try Data(contentsOf: sentinel) == Data("keep this file".utf8))
  #expect(try TaskAttachmentFiles.read(attachment, baseURL: root) == png)
  let backup = try BackupArchive.decode(BackupArchive.encode(deleted, baseURL: root))
  #expect(backup.library.projects == deleted.projects)
  #expect(backup.library.tasks == deleted.tasks)
  #expect(backup.assets[attachment.id] == png)
  repository = nil
  repository = try LibraryRepository(url: store)
  let reloaded = try await repository!.load()
  #expect(reloaded.projects == deleted.projects)
  #expect(reloaded.tasks == deleted.tasks)
  let restored = try await repository!.apply(
    .setProjectDeleted(project.id, false, expectedRevision: 1))
  project.deletionRevision = 2
  #expect(restored.projects == [project])
  #expect(restored.tasks == before.tasks)
  #expect(restored.runs == before.runs)
  #expect(restored.recentTasks.count == 1)
  #expect(try TaskAttachmentFiles.read(attachment, baseURL: root) == png)
  #expect(try Data(contentsOf: sentinel) == Data("keep this file".utf8))
}

@Test func deletedProjectsRejectNewWorkAndStaleSettingsWhileActiveRunsBlockDeletion() throws {
  let project = Project(name: "Protected", directory: "/tmp/protected")
  let task = WorkItem(projectID: project.id, title: "Protected task")
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  for status in [RunStatus.queued, .running, .needsInput] {
    var run = AgentRun(task: task, kind: .implementation)
    run.status = status
    library.runs = [run]
    #expect(throws: BoardError.self) {
      try BoardReducer.apply(.setProjectDeleted(project.id, true, expectedRevision: 0), to: library)
    }
  }
  library.runs = []
  let deleted = try BoardReducer.apply(
    .setProjectDeleted(project.id, true, expectedRevision: 0), to: library)
  let newTask = WorkItem(projectID: project.id, title: "Must not be created")
  for mutation in [
    Mutation.createTask(newTask), .editProject(project),
    .runTaskNow(
      task.id, expectedRevision: task.revision, kind: .planning,
      configuration: fixtureModelConfiguration),
    .saveNotes(task.id, "Must not change", expectedRevision: task.revision),
    .deleteTask(task.id, expectedRevision: task.revision),
    .restoreTask(task.id, nil, expectedRevision: task.revision),
  ] {
    #expect(throws: BoardError.self) { try BoardReducer.apply(mutation, to: deleted) }
  }
  #expect(throws: BoardError.self) {
    try BoardReducer.apply(.setProjectDeleted(project.id, false, expectedRevision: 0), to: deleted)
  }
  let restored = try BoardReducer.apply(
    .setProjectDeleted(project.id, false, expectedRevision: 1), to: deleted)
  let edited = try BoardReducer.apply(.editProject(project), to: restored)
  #expect(edited.projects[0].deletionRevision == 2)
  #expect(!edited.projects[0].isDeleted)
}

@Test func remoteProjectDeletionRestorationIsIdempotentRevisionCheckedAndSynced() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Shared", directory: "/private/mac-only-folder")
  _ = try await repository.apply(.createProject(project))
  let state = try await repository.syncStateSnapshot()
  let device = UUID()
  let deletion = SyncEnvelope(
    libraryID: state.libraryID, deviceID: device, clientSequence: 1,
    expectedRevision: 0, command: .setProjectDeleted(id: project.id, deleted: true))
  guard case .applied(let sequence, let snapshot) = try await repository.applyRemote(deletion)
  else {
    Issue.record("Phone deletion was not applied")
    return
  }
  let replica = try JSONDecoder.syncDecoder.decode(
    SyncSnapshot.self, from: JSONEncoder.syncEncoder.encode(snapshot)
  ).replica()
  #expect(replica.deletedProjects.first?.id == project.id)
  #expect(replica.projects[0].deletionRevision == 1)
  #expect(replica.projects[0].directory.isEmpty)
  guard case .applied(let replaySequence, let replay) = try await repository.applyRemote(deletion)
  else {
    Issue.record("Deletion receipt was not replayed")
    return
  }
  #expect(sequence == replaySequence)
  #expect(replay.activity == snapshot.activity)
  let restoration = SyncEnvelope(
    libraryID: state.libraryID, deviceID: device, clientSequence: 2,
    expectedRevision: 1, command: .setProjectDeleted(id: project.id, deleted: false))
  guard case .applied(_, let restored) = try await repository.applyRemote(restoration) else {
    Issue.record("Phone restoration was not applied")
    return
  }
  #expect(try restored.replica().activeProjects.first?.id == project.id)
  let stale = SyncEnvelope(
    libraryID: state.libraryID, deviceID: UUID(), clientSequence: 1,
    expectedRevision: 0, command: .setProjectDeleted(id: project.id, deleted: true))
  guard case .conflict = try await repository.applyRemote(stale) else {
    Issue.record("Stale deletion must not overwrite a restoration")
    return
  }
  var unsupported = stale
  unsupported.version = 9
  guard case .rejected = try await repository.applyRemote(unsupported) else {
    Issue.record("Older client must be rejected")
    return
  }
  let final = try await repository.load()
  #expect(final.projects[0].directory == project.directory)
  #expect(!final.projects[0].isDeleted)
  #expect(final.projects[0].deletionRevision == 2)
}

@Test func projectReorderingPersistsAndLeavesDeletedProjectSlotsStable() throws {
  var library = Library()
  var first = Project(name: "First")
  var deleted = Project(name: "Deleted")
  var third = Project(name: "Third")
  var second = Project(name: "Second")
  first.projectOrder = 0
  deleted.projectOrder = 1
  deleted.deletedAt = Date(timeIntervalSince1970: 1)
  third.projectOrder = 2
  second.projectOrder = 3
  library.projects = [first, deleted, third, second]

  let reordered = try BoardReducer.apply(
    .reorderProjects([third.id, first.id, second.id]), to: library)
  #expect(reordered.activeProjects.map(\.id) == [third.id, first.id, second.id])
  #expect(
    ProjectOrdering.ordered(reordered.projects).map(\.id)
      == [third.id, deleted.id, first.id, second.id])
  #expect(reordered.projects.first(where: { $0.id == deleted.id })?.projectOrder == 1)

  var staleSettingsDraft = first
  staleSettingsDraft.name = "First renamed"
  let edited = try BoardReducer.apply(.editProject(staleSettingsDraft), to: reordered)
  #expect(edited.activeProjects.map(\.id) == [third.id, first.id, second.id])
  #expect(edited.projects.first(where: { $0.id == first.id })?.projectOrder == 2)

  let created = try BoardReducer.apply(.createProject(Project(name: "New")), to: edited)
  #expect(created.activeProjects.map(\.name) == ["Third", "First renamed", "Second", "New"])
  #expect(created.projects.first(where: { $0.name == "Deleted" })?.projectOrder == 1)
}

@Test func projectOrderingSnapshotRoundTripsAndNormalizesLegacyProjects() throws {
  var first = Project(name: "First")
  var second = Project(name: "Second")
  first.projectOrder = 1
  second.projectOrder = 0
  var library = Library()
  library.projects = [first, second]
  let snapshot = SyncSnapshot(libraryID: UUID(), sequence: 2, library: library)
  let decoded = try JSONDecoder.syncDecoder.decode(
    SyncSnapshot.self, from: JSONEncoder.syncEncoder.encode(snapshot))
  #expect(try decoded.replica().activeProjects.map(\.id) == [second.id, first.id])
  #expect(decoded.projects.first(where: { $0.id == first.id })?.projectOrder == 1)

  let legacyPayload =
    #"{"id":"00000000-0000-0000-0000-000000000099","name":"Legacy","directory":"","automationEnabled":false,"createdAt":0}"#
  let legacy = Data(legacyPayload.utf8)
  let legacyProject = try JSONDecoder().decode(Project.self, from: legacy)
  #expect(legacyProject.projectOrder == nil)
  var legacyProjects = [legacyProject]
  #expect(ProjectOrdering.normalize(&legacyProjects))
  #expect(legacyProjects[0].projectOrder == 0)
}

@Test func phoneProjectReorderUsesOrderDigestAndRejectsStaleIntent() async throws {
  let repository = try LibraryRepository(inMemory: true)
  let first = Project(name: "First")
  let second = Project(name: "Second")
  let third = Project(name: "Third")
  _ = try await repository.apply(.createProject(first))
  _ = try await repository.apply(.createProject(second))
  _ = try await repository.apply(.createProject(third))
  let state = try await repository.syncStateSnapshot()
  let digest = SyncCommandValidator.projectOrderDigest(in: state.library)
  let valid = SyncEnvelope(
    libraryID: state.libraryID, deviceID: UUID(), clientSequence: 1,
    command: .reorderProjects(ids: [third.id, first.id, second.id], orderDigest: digest))
  guard case .applied(_, let snapshot) = try await repository.applyRemote(valid) else {
    Issue.record("Phone project reorder was not applied")
    return
  }
  #expect(try snapshot.replica().activeProjects.map(\.id) == [third.id, first.id, second.id])

  let stale = SyncEnvelope(
    libraryID: state.libraryID, deviceID: UUID(), clientSequence: 1,
    command: .reorderProjects(ids: [first.id, second.id, third.id], orderDigest: digest))
  guard case .conflict = try await repository.applyRemote(stale) else {
    Issue.record("A stale project reorder must not overwrite the current order")
    return
  }
}

@Test func legacyProjectsDecodeAsActiveAndDeletedStateSurvivesCodable() throws {
  let legacy = Data("{\"name\":\"Legacy\"}".utf8)
  let project = try JSONDecoder().decode(Project.self, from: legacy)
  #expect(!project.isDeleted)
  #expect(project.deletionRevision == 0)
  var deleted = project
  deleted.deletedAt = Date(timeIntervalSince1970: 123)
  deleted.deletionRevision = 1
  #expect(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(deleted)) == deleted)
  var object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(SyncProject(project))) as? [String: Any]
  )
  object.removeValue(forKey: "deletedAt")
  object.removeValue(forKey: "deletionRevision")
  let oldProject = try JSONDecoder().decode(
    SyncProject.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(oldProject.deletedAt == nil)
  #expect(oldProject.deletionRevision == nil)
}

@Test(arguments: [RunKind.implementation, .task, .planning])
func externalStartMovesOnlyExecutionToBuilding(kind: RunKind) async throws {
  let repository = try LibraryRepository(inMemory: true)
  let project = Project(name: "Execution start")
  _ = try await repository.apply(.createProject(project))
  var task = WorkItem(projectID: project.id, title: "Start", stage: .planned)
  task.planPath = "to-do/existing-plan.md"
  _ = try await repository.apply(.createTask(task))
  var run = AgentRun(task: task, kind: kind)
  run.source = .codexDesktop
  run.status = .running
  let started = try await repository.applyMCP(
    .beginExternalRun(run), operationID: run.id, fingerprint: "start")
  let saved = try #require(started.library.tasks.first)
  #expect(saved.stage == (kind == .planning ? .planned : .implementation))
  #expect(saved.section == (kind == .planning ? .planning : .implementing))
  #expect(saved.status == (kind == .planning ? .planApproved : .building))
  #expect(saved.revision == (kind == .planning ? 0 : 1))
  #expect(saved.planPath == task.planPath)
  #expect(!saved.completed)
  #expect(started.library.runs.count == 1)
  let replay = try await repository.applyMCP(
    .beginExternalRun(run), operationID: run.id, fingerprint: "start")
  #expect(replay.replayed)
  #expect(replay.library.tasks.first == saved)
}

@Test func ownedExecutionMovesWhenRunningAndDoesNotMoveAgainOnProgress() throws {
  let project = Project(name: "Execution", directory: "/tmp/fixture")
  let task = WorkItem(projectID: project.id, title: "Build", stage: .planned)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library = try BoardReducer.apply(
    .runTaskNow(
      task.id, expectedRevision: 0, kind: .implementation,
      configuration: fixtureModelConfiguration), to: library)
  var run = try #require(library.runs.first)
  library = try BoardReducer.apply(.updateRun(run), to: library)
  #expect(library.tasks[0] == task)
  run.status = .running
  library = try BoardReducer.apply(.updateRun(run), to: library)
  #expect(library.tasks[0].stage == .implementation)
  #expect(library.tasks[0].section == .implementing)
  #expect(library.tasks[0].status == .building)
  #expect(library.tasks[0].revision == 1)
  #expect(library.runs.count == 1)
  library = try BoardReducer.apply(.move(task.id, .review, expectedRevision: 1), to: library)
  let moved = library.tasks[0]
  library = try BoardReducer.apply(.updateRun(run), to: library)
  #expect(library.tasks[0] == moved)
  run.status = .failed
  run.error = "Service unavailable"
  library = try BoardReducer.apply(.updateRun(run), to: library)
  library = try BoardReducer.apply(.retry(run.id), to: library)
  run = library.runs[0]
  run.status = .running
  library = try BoardReducer.apply(.updateRun(run), to: library)
  #expect(library.tasks[0].stage == .implementation)
  #expect(library.tasks[0].status == .building)
}

@Test func planningProgressNeverBecomesBuilding() throws {
  let project = Project(name: "Planning", directory: "/tmp/fixture")
  let task = WorkItem(projectID: project.id, title: "Plan", stage: .next)
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  library = try BoardReducer.apply(
    .runTaskNow(
      task.id, expectedRevision: 0, kind: .planning,
      configuration: fixtureModelConfiguration), to: library)
  var run = library.runs[0]
  run.status = .running
  library = try BoardReducer.apply(.updateRun(run), to: library)
  #expect(library.tasks[0].status == .planning)
  #expect(library.tasks[0].stage == .next)
  #expect(library.tasks[0].section == .planning)

  var external = AgentRun(task: library.tasks[0], kind: .planning)
  external.source = .codexDesktop
  external.status = .running
  library = try BoardReducer.apply(.beginExternalRun(external), to: library)
  library = try BoardReducer.apply(
    .reportExternalRun(
      external.id, "Drafting plan", .running, expectedTaskRevision: library.tasks[0].revision),
    to: library)
  #expect(library.tasks[0].status == .planning)
  #expect(library.tasks[0].stage == .next)
}

@Test func externalExecutionDoesNotReopenOrMoveCompletedTask() throws {
  let project = Project(name: "Completed")
  var task = WorkItem(projectID: project.id, title: "Done", stage: .review)
  task.completed = true
  var library = Library()
  library.projects = [project]
  library.tasks = [task]
  var run = AgentRun(task: task, kind: .task)
  run.source = .codexDesktop
  run.status = .running
  library = try BoardReducer.apply(.beginExternalRun(run), to: library)
  #expect(library.tasks[0] == task)
}
