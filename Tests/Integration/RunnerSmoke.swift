import Foundation

private let fixtureModelConfiguration = ResolvedCodexConfiguration(
  selection: .latestLuna, modelID: "gpt-6.10-luna", effort: "high", scope: .global)

@main struct RunnerSmoke {
  @MainActor static func wait(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw BoardError.invalid("Fixture timed out")
  }
  @MainActor static func main() async throws {
    try await testMCPCompletionCannotBeChangedByLegacyTool()
    try await testMovePersistsWhenRunnerSetupFails()
    try await testGitService()
    let promptProject = Project(name: "Prompt fixture", directory: "/tmp/prompt-fixture")
    let promptTask = WorkItem(projectID: promptProject.id, title: "Readable prompt title")
    guard
      TaskHandoffPrompt.make(for: promptTask, project: promptProject)
        .hasPrefix("Task: Readable prompt title\n\n")
    else { throw BoardError.invalid("Manual task prompt does not start with its exact title") }
    let unusualTitle = "  Résumé: 東京!  "
    guard
      CodexRunner.sessionName(for: .planning, taskTitle: unusualTitle) == "Plan: \(unusualTitle)",
      CodexRunner.sessionName(for: .implementation, taskTitle: unusualTitle)
        == "Code: \(unusualTitle)",
      CodexRunner.sessionName(for: .task, taskTitle: unusualTitle) == "Code: \(unusualTitle)"
    else {
      throw BoardError.invalid("Session name prefixes or task-title preservation are incorrect")
    }
    let fixture = CommandLine.arguments[1]
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "stagechase-smoke-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let repo = try LibraryRepository(inMemory: true)
    let preferences = UserDefaults(suiteName: "StageChase.RunnerSmoke.\(UUID().uuidString)")!
    preferences.set(false, forKey: "localSyncEnabled")
    let model = AppModel(repository: repo, preferences: preferences, preview: false)
    guard model.planFormatPrompt == AppModel.defaultPlanFormatPrompt else {
      throw BoardError.invalid("The first-launch plan format prompt did not use its default")
    }
    let customPlanFormat = """
      PLAN_FORMAT_SENTINEL
      ## User requirements
      ## Architecture and data model
      ## Basic test cases
      ## High-level implementation details
      """
    model.setPlanFormatPrompt(customPlanFormat)
    guard model.planFormatPrompt == customPlanFormat else {
      throw BoardError.invalid("The custom plan format prompt was not saved")
    }
    let restoredPlanFormat = AppModel(repository: repo, preferences: preferences, preview: false)
    guard restoredPlanFormat.planFormatPrompt == customPlanFormat else {
      throw BoardError.invalid(
        "The plan format prompt did not persist across AppModel reconstruction")
    }
    model.setPlanFormatPrompt(" \n ")
    guard model.resolvedPlanFormatPrompt == AppModel.defaultPlanFormatPrompt else {
      throw BoardError.invalid("A blank plan format prompt did not fall back to the default")
    }
    model.resetPlanFormatPrompt()
    guard model.planFormatPrompt == AppModel.defaultPlanFormatPrompt,
      preferences.string(forKey: AppModel.planFormatPromptPreferenceKey) == nil
    else { throw BoardError.invalid("Reset did not restore the default plan format prompt") }
    model.setPlanFormatPrompt(
      String(repeating: "x", count: AppModel.maximumPlanFormatPromptCharacters + 1))
    guard model.planFormatPrompt.count == AppModel.maximumPlanFormatPromptCharacters,
      model.planFormatPromptError != nil
    else { throw BoardError.invalid("An oversized plan format prompt was not bounded visibly") }
    model.setPlanFormatPrompt(customPlanFormat)
    print("PASS: plan format prompt defaults, persists, falls back when blank, and resets")
    guard model.approvalMode == .approveForMe, model.approvalModeError == nil else {
      throw BoardError.invalid("Missing approval mode must default to Approve for me")
    }
    model.setApprovalMode(.askMe)
    guard model.library.runs.isEmpty else {
      throw BoardError.invalid("Changing the approval setting created a Codex run")
    }
    let restoredPreferences = AppModel(repository: repo, preferences: preferences, preview: false)
    guard restoredPreferences.approvalMode == .askMe else {
      throw BoardError.invalid("Approval mode did not persist across AppModel reconstruction")
    }
    let freshPreferences = UserDefaults(suiteName: "StageChase.RunnerSmoke.Fresh.\(UUID())")!
    guard
      AppModel(repository: repo, preferences: freshPreferences, preview: false).approvalMode
        == .approveForMe
        && AppModel(repository: repo, preferences: freshPreferences, preview: false)
          .planFormatPrompt
          == AppModel.defaultPlanFormatPrompt
    else {
      throw BoardError.invalid("A fresh preference suite did not default to Approve for me")
    }
    let corruptPreferences = UserDefaults(suiteName: "StageChase.RunnerSmoke.Invalid.\(UUID())")!
    corruptPreferences.set("unknown-mode", forKey: "codexApprovalMode")
    let corruptModel = AppModel(repository: repo, preferences: corruptPreferences, preview: false)
    guard corruptModel.approvalModeError != nil else {
      throw BoardError.invalid("Invalid saved approval mode was not surfaced")
    }
    model.setApprovalMode(.approveForMe)
    await model.load()
    try await testTaskWorktreeCommit(model: model)
    try await testProjectCommit(model: model)
    model.runner = CodexRunner(model: model, executableOverride: fixture)
    var project = Project(name: "Fixture", directory: folder.path)
    project.automationEnabled = true
    guard await model.saveProject(project, isNew: true) else {
      throw BoardError.invalid(model.error ?? "project")
    }
    for title in [
      "Plan fixture", "MISSING_PLAN_FIXTURE", "EMPTY_PLAN_FIXTURE", "BLOCKED_FIXTURE",
      "UNMARKED_FIXTURE", "EMPTY_COMPLETED_FIXTURE",
      "APPROVAL_FIXTURE", "UNSAFE_FIXTURE", "FULL_ACCESS_FIXTURE",
      "FULL_ACCESS_BLOCKED_FIXTURE", "STOP_FIXTURE",
      "CLOSE_FIXTURE", "NAME_FAILURE_FIXTURE",
    ] {
      print("START: \(title)")
      fflush(nil)
      project.executionProfile =
        title.contains("FULL_ACCESS")
        ? .fullAccessNoPrompts : .workspaceAccessNoPrompts
      guard await model.saveProject(project, isNew: false) else {
        throw BoardError.invalid(model.error ?? "project profile")
      }
      let item = WorkItem(projectID: project.id, title: title, stage: .next)
      _ = await model.perform(.createTask(item, configuration: fixtureModelConfiguration))
      let reservedPath = WorkItem.canonicalPlanPath(for: item.id, title: item.title)
      guard model.library.tasks.first(where: { $0.id == item.id })?.planPath == reservedPath,
        let queuedRun = model.library.latestRun(for: item.id), queuedRun.taskID == item.id,
        queuedRun.kind == .planning, queuedRun.status == .queued,
        queuedRun.executionProfile == project.executionProfile
      else {
        throw BoardError.invalid(
          "Planning path and queued run were not persisted together before start")
      }
      model.kickRunner()
      if title == "STOP_FIXTURE" {
        try await wait { model.library.latestRun(for: item.id)?.turnID != nil }
        await model.stop(model.library.latestRun(for: item.id)!.id)
      }
      if title == "CLOSE_FIXTURE" {
        do {
          try await wait { model.library.latestRun(for: item.id)?.turnID != nil }
        } catch {
          print(
            "DEBUG: start state=\(String(describing: model.library.latestRun(for: item.id))) "
              + "message=\(model.runnerMessage)")
          fflush(nil)
          throw error
        }
        let run = model.library.latestRun(for: item.id)!
        guard
          let previousRun = model.library.runs.first(where: {
            $0.id != run.id && $0.status == .succeeded
          }),
          model.runner?.closeAvailability(runID: previousRun.id)?.contains("Another Codex run")
            == true
        else { throw BoardError.invalid("Close did not guard another active run") }
        await model.closeCodexSession(run.id)
        do {
          try await wait {
            model.library.runs.first(where: { $0.id == run.id })?.status == .interrupted
          }
        } catch {
          print(
            "DEBUG: close status=\(model.library.runs.first(where: { $0.id == run.id })?.status.rawValue ?? "missing") "
              + "message=\(model.runnerMessage)")
          fflush(nil)
          throw error
        }
      }
      do {
        try await wait { model.library.latestRun(for: item.id)?.status.isActive == false }
      } catch {
        print(
          "DEBUG: \(String(describing: model.library.latestRun(for: item.id))) error=\(model.error ?? "none")"
        )
        fflush(nil)
        throw error
      }
      let run = model.library.latestRun(for: item.id)!
      let expected: RunStatus
      switch title {
      case "BLOCKED_FIXTURE", "FULL_ACCESS_BLOCKED_FIXTURE", "UNMARKED_FIXTURE",
        "EMPTY_COMPLETED_FIXTURE", "MISSING_PLAN_FIXTURE", "EMPTY_PLAN_FIXTURE":
        expected = .failed
      case "APPROVAL_FIXTURE", "UNSAFE_FIXTURE": expected = .failed
      case "STOP_FIXTURE": expected = .cancelled
      case "CLOSE_FIXTURE": expected = .interrupted
      default: expected = .succeeded
      }
      guard run.status == expected else {
        throw BoardError.invalid("\(title): \(run.status) / \(run.error ?? model.error ?? "")")
      }
      let expectedStage: WorkflowStage = .next
      guard let finishedTask = model.library.tasks.first(where: { $0.id == item.id }),
        finishedTask.stage == expectedStage,
        finishedTask.planPath == WorkItem.canonicalPlanPath(for: item.id, title: item.title)
      else {
        throw BoardError.invalid("Unexpected stage or changed reserved plan path")
      }
      guard !model.library.activity.filter({ $0.runID == run.id }).isEmpty else {
        throw BoardError.invalid("Missing logs")
      }
      if title == "Plan fixture" {
        var linkedRun = AgentRun(task: finishedTask, kind: .task)
        linkedRun.status = .readyForHandoff
        linkedRun.threadID = run.threadID
        _ = await model.perform(.createManualRun(linkedRun))
        guard let trackedRun = model.library.latestRun(for: item.id) else {
          throw BoardError.invalid("Manual session fixture was not saved")
        }
        let activityCount = model.library.activity.filter { $0.runID == trackedRun.id }.count
        guard await model.refreshCodexStatus(trackedRun.id),
          let refreshedRun = model.library.runs.first(where: { $0.id == trackedRun.id }),
          refreshedRun.status == .succeeded,
          refreshedRun.summary.contains("Fixture verified"),
          model.library.activity.filter({ $0.runID == trackedRun.id }).count == activityCount,
          let refreshedTask = model.library.tasks.first(where: { $0.id == item.id }),
          refreshedTask.stage == .next, !refreshedTask.completed
        else {
          throw BoardError.invalid("Explicit session refresh lost status, activity, or task state")
        }
        print(
          "PASS: linked status refresh updates latest activity without duplicate events or task changes"
        )
      }
      print("PASS: \(title) → \(run.status.rawValue), task in \(expectedStage.rawValue)")
      if title == "APPROVAL_FIXTURE" {
        guard run.error?.contains("no-prompt policy") == true else {
          throw BoardError.invalid("An unexpected approval request was not reported clearly")
        }
      }
      if title == "UNSAFE_FIXTURE" {
        guard run.error?.contains("broader access") == true else {
          throw BoardError.invalid("Unsafe request did not fail visibly")
        }
      }
      if title == "NAME_FAILURE_FIXTURE" {
        guard run.status == .succeeded, let threadID = run.threadID, !threadID.isEmpty else {
          throw BoardError.invalid("A best-effort session naming failure changed the run outcome")
        }
      }
      if title == "FULL_ACCESS_FIXTURE" || title == "FULL_ACCESS_BLOCKED_FIXTURE" {
        guard run.executionProfile == .fullAccessNoPrompts,
          run.status == (title == "FULL_ACCESS_FIXTURE" ? .succeeded : .failed)
        else { throw BoardError.invalid("Full-access profile was not saved with its run") }
      }
      if title == "CLOSE_FIXTURE" {
        guard
          run.threadID != nil, run.turnID != nil, run.workDirectory == folder.path,
          model.library.tasks.first(where: { $0.id == item.id })?.completed == false
        else { throw BoardError.invalid("Close lost active session identity or task state") }
        let activityCount = model.library.activity.filter {
          $0.runID == run.id && $0.message == "Session released from StageChase. Continue in Codex."
        }.count
        await model.closeCodexSession(run.id)
        let repeatedActivityCount = model.library.activity.filter {
          $0.runID == run.id && $0.message == "Session released from StageChase. Continue in Codex."
        }.count
        guard repeatedActivityCount == activityCount else {
          throw BoardError.invalid("Repeated session release duplicated its activity")
        }
        print("PASS: active close preserves session identity and is idempotent")
        let queued = WorkItem(projectID: project.id, title: "QUEUED_AFTER_HANDOFF", stage: .next)
        let confirmed = WorkItem(
          projectID: project.id, title: "CONFIRMED_AFTER_HANDOFF", stage: .next)
        _ = await model.perform(.createTask(queued, configuration: fixtureModelConfiguration))
        guard model.library.latestRun(for: queued.id)?.status == .queued else {
          throw BoardError.invalid("Expected queued work after close")
        }
        _ = await model.perform(.createTask(confirmed, configuration: fixtureModelConfiguration))
        model.kickRunner()
        do {
          try await wait {
            model.library.latestRun(for: queued.id)?.status.isActive == false
              && model.library.latestRun(for: confirmed.id)?.status.isActive == false
          }
        } catch {
          print(
            "DEBUG: queued=\(String(describing: model.library.latestRun(for: queued.id))) "
              + "confirmed=\(String(describing: model.library.latestRun(for: confirmed.id))) "
              + "message=\(model.runnerMessage)")
          fflush(nil)
          throw error
        }
        guard model.library.latestRun(for: queued.id)?.status == .succeeded,
          model.library.latestRun(for: confirmed.id)?.status == .succeeded
        else {
          throw BoardError.invalid("Explicit queue resume did not complete both fixture runs")
        }
        print("PASS: close pauses queued work until a later explicit runner action")
      }
      if title == "Plan fixture" {
        let savedPlanPath = model.library.tasks.first(where: { $0.id == item.id })?.planPath
        let summary = run.summary
        await model.closeCodexSession(run.id)
        guard let saved = model.library.runs.first(where: { $0.id == run.id }),
          saved.status == .succeeded, saved.summary == summary,
          model.library.tasks.first(where: { $0.id == item.id })?.stage == .next,
          model.library.tasks.first(where: { $0.id == item.id })?.planPath == savedPlanPath
        else { throw BoardError.invalid("Closing a successful run changed its result") }
        print("PASS: successful close preserves outcome, stage, summary, and plan")
      }
    }
    let arrivingPlanTask = WorkItem(projectID: project.id, title: "Arriving plan fixture")
    _ = await model.perform(.createTask(arrivingPlanTask))
    var attachedTask = model.library.tasks.first(where: { $0.id == arrivingPlanTask.id })!
    attachedTask.planPath = "to-do/arrived.md"
    let arrivedPlanURL = folder.appendingPathComponent("to-do/arrived.md")
    try FileManager.default.createDirectory(
      at: arrivedPlanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "# New plan\n\nRead after refresh.\n".write(
      to: arrivedPlanURL, atomically: true, encoding: .utf8)
    _ = try await repo.apply(.editTask(attachedTask, expectedRevision: attachedTask.revision))
    await model.refreshTask(arrivingPlanTask.id)
    guard
      model.library.tasks.first(where: { $0.id == arrivingPlanTask.id })?.planPath
        == "to-do/arrived.md",
      model.taskRefreshMessages[arrivingPlanTask.id]?.contains("Saved plan is available") == true,
      PlanHandoffPrompt.hasReadablePlan(
        for: model.library.tasks.first(where: { $0.id == arrivingPlanTask.id })!, project: project)
    else {
      throw BoardError.invalid("Task refresh did not discover a newly attached readable plan")
    }
    try "# Changed plan\n\nRead the current contents.\n".write(
      to: arrivedPlanURL, atomically: true, encoding: .utf8)
    await model.refreshTask(arrivingPlanTask.id)
    guard try String(contentsOf: arrivedPlanURL, encoding: .utf8).contains("Changed plan") else {
      throw BoardError.invalid("Task refresh did not reread the changed plan file")
    }
    print("PASS: task refresh discovers new plan attachments and rechecks changed files")

    var unlinked = WorkItem(projectID: project.id, title: "Unlinked refresh fixture")
    unlinked.planPath = "to-do/missing-plan.md"
    _ = await model.perform(.createTask(unlinked))
    await model.refreshTask(unlinked.id, preservingEdits: true)
    guard model.taskRefreshMessages[unlinked.id]?.contains("No linked Codex session") == true,
      model.taskRefreshMessages[unlinked.id]?.contains("plan is unavailable") == true,
      model.taskRefreshMessages[unlinked.id]?.contains("unsaved edits are preserved") == true,
      model.library.tasks.first(where: { $0.id == unlinked.id })?.stage == .inbox,
      model.library.tasks.first(where: { $0.id == unlinked.id })?.completed == false,
      model.library.latestRun(for: unlinked.id) == nil
    else { throw BoardError.invalid("Unlinked refresh changed task state or missed its result") }

    var readFailureRun = AgentRun(task: unlinked, kind: .task)
    readFailureRun.status = .readyForHandoff
    readFailureRun.threadID = "fixture-read-failure"
    readFailureRun.error = "Existing error state"
    _ = await model.perform(.createManualRun(readFailureRun))
    guard !(await model.refreshCodexStatus(readFailureRun.id)),
      let preservedRun = model.library.runs.first(where: { $0.id == readFailureRun.id }),
      preservedRun.status == .readyForHandoff,
      preservedRun.error == "Existing error state",
      model.error?.contains("fixture read failure") == true
    else { throw BoardError.invalid("Failed session read did not preserve the saved run state") }

    var slowReadRun = AgentRun(task: unlinked, kind: .task)
    slowReadRun.status = .readyForHandoff
    slowReadRun.threadID = "fixture-slow-read"
    _ = await model.perform(.createManualRun(slowReadRun))
    guard let savedSlowRun = model.library.latestRun(for: unlinked.id) else {
      throw BoardError.invalid("Repeated-refresh fixture was not saved")
    }
    let runActivityCount = model.library.activity.filter { $0.runID == savedSlowRun.id }.count
    let firstStatusRefresh = Task { @MainActor in
      await model.refreshCodexStatus(savedSlowRun.id)
    }
    try await wait { model.runStatusRefreshInFlight.contains(savedSlowRun.id) }
    guard !(await model.refreshCodexStatus(savedSlowRun.id)), await firstStatusRefresh.value,
      !model.runStatusRefreshInFlight.contains(savedSlowRun.id),
      model.library.activity.filter({ $0.runID == savedSlowRun.id }).count == runActivityCount
    else { throw BoardError.invalid("Overlapping status refreshes were not safely coalesced") }
    print("PASS: unlinked and failed session refreshes preserve task and retry state")
    print("Offline runner integration checks passed; no real agent turns were started.")
    var blocked = model.library.tasks.first { $0.title == "FULL_ACCESS_BLOCKED_FIXTURE" }!
    let previousRun = model.library.latestRun(for: blocked.id)!
    let runCount = model.library.runs.count
    blocked.title = "FULL_ACCESS_RETRY_FIXTURE"
    _ = await model.perform(.editTask(blocked, expectedRevision: blocked.revision))
    project.executionProfile = .workspaceAccessNoPrompts
    _ = await model.saveProject(project, isNew: false)
    await model.retry(previousRun.id)
    try await wait { model.library.latestRun(for: blocked.id)?.status.isActive == false }
    guard let retried = model.library.latestRun(for: blocked.id), retried.status == .succeeded,
      retried.id == previousRun.id, retried.threadID == previousRun.threadID,
      retried.executionProfile == .fullAccessNoPrompts,
      model.library.runs.count == runCount
    else { throw BoardError.invalid("Retry duplicated or lost a run") }
    print("PASS: failed run retries in the same session without duplication")
    let undo = UndoManager()
    undo.groupsByEvent = false
    model.undoManager = undo
    let manual = WorkItem(projectID: project.id, title: "Undo fixture")
    undo.beginUndoGrouping()
    _ = await model.perform(.createTask(manual))
    undo.endUndoGrouping()
    undo.undo()
    try await wait { !model.library.tasks.contains(where: { $0.id == manual.id }) }
    undo.redo()
    try await wait { model.library.tasks.contains(where: { $0.id == manual.id }) }
    print("PASS: native UndoManager add → undo → redo")
    let gitRoot = folder.appendingPathComponent("repository")
    try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
    func git(_ arguments: [String]) throws {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      task.arguments = ["-C", gitRoot.path] + arguments
      task.standardOutput = FileHandle.nullDevice
      task.standardError = FileHandle.nullDevice
      try task.run()
      task.waitUntilExit()
      guard task.terminationStatus == 0 else {
        throw BoardError.invalid("Fixture Git setup failed")
      }
    }
    try git(["init", "-q"])
    let readme = gitRoot.appendingPathComponent("README.md")
    try "Committed base\n".write(to: readme, atomically: true, encoding: .utf8)
    try git(["add", "README.md"])
    try git([
      "-c", "user.name=StageChase Fixture", "-c", "user.email=fixture@example.invalid", "commit",
      "-qm", "Fixture",
    ])
    try "Uncommitted user work\n".write(to: readme, atomically: true, encoding: .utf8)
    let plan = gitRoot.appendingPathComponent("to-do/fixture.md")
    try FileManager.default.createDirectory(
      at: plan.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "# Implement fixture\n".write(to: plan, atomically: true, encoding: .utf8)
    var gitProject = Project(name: "Git fixture", directory: gitRoot.path)
    gitProject.automationEnabled = true
    gitProject.usesWorktrees = true
    _ = await model.saveProject(gitProject, isNew: true)
    model.runner = CodexRunner(
      model: model, executableOverride: fixture,
      worktreeRootOverride: folder.appendingPathComponent("worktrees"))
    var implementation = WorkItem(
      projectID: gitProject.id, title: "Implement fixture", stage: .implementation)
    implementation.planPath = "to-do/fixture.md"
    _ = await model.perform(.createTask(implementation, configuration: fixtureModelConfiguration))
    model.kickRunner()
    try await wait { model.library.latestRun(for: implementation.id)?.status.isActive == false }
    guard let run = model.library.latestRun(for: implementation.id), run.status == .succeeded,
      let path = run.workDirectory, path != gitRoot.path,
      run.usesWorktrees == true,
      run.threadID != nil,
      run.modelConfiguration == fixtureModelConfiguration
    else { throw BoardError.invalid("Missing isolated worktree") }
    let original = try String(contentsOf: readme, encoding: .utf8)
    let isolated = try String(
      contentsOf: URL(fileURLWithPath: path).appendingPathComponent("README.md"), encoding: .utf8)
    guard original == "Uncommitted user work\n", isolated == "Committed base\n",
      FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: path).appendingPathComponent("to-do/fixture.md").path),
      model.library.tasks.first(where: { $0.id == implementation.id })?.stage == .implementation
    else {
      throw BoardError.invalid("Dirty checkout isolation failed")
    }
    print(
      "PASS: dirty checkout isolated, original edits preserved, plan copied, task column unchanged")

    var directProject = gitProject
    directProject.usesWorktrees = false
    _ = await model.perform(.editProject(directProject))
    let directImplementation = WorkItem(
      projectID: directProject.id, title: "Direct implementation fixture",
      stage: .implementation)
    _ = await model.perform(
      .createTask(directImplementation, configuration: fixtureModelConfiguration))
    model.kickRunner()
    try await wait {
      model.library.latestRun(for: directImplementation.id)?.status.isActive == false
    }
    guard let directRun = model.library.latestRun(for: directImplementation.id),
      directRun.status == .succeeded, directRun.workDirectory == gitRoot.path,
      directRun.usesWorktrees == false
    else { throw BoardError.invalid("Disabled worktrees did not use the project folder") }
    print("PASS: dirty implementation with worktrees disabled uses the project folder")
  }

  @MainActor static func testMCPCompletionCannotBeChangedByLegacyTool() async throws {
    let repository = try LibraryRepository(inMemory: true)
    let project = Project(name: "MCP completion fixture")
    _ = try await repository.apply(.createProject(project))
    let task = WorkItem(projectID: project.id, title: "Completion stays user controlled")
    _ = try await repository.apply(.createTask(task))
    let server = MCPServer(repository: repository)
    let names = MCPServer.tools.compactMap { $0["name"] as? String }
    guard !names.contains("set_task_completed") else {
      throw BoardError.invalid("MCP discovery still advertises task completion")
    }
    do {
      _ = try await server.callTool(
        "set_task_completed",
        arguments: [
          "project_id": project.id.uuidString, "task_id": task.id.uuidString,
          "operation_id": UUID().uuidString, "expected_revision": 0, "completed": true,
        ])
      throw BoardError.invalid("The legacy MCP completion tool unexpectedly succeeded")
    } catch let error as BoardError {
      guard case .invalid(let message) = error, message.contains("Unknown StageChase tool") else {
        throw BoardError.invalid("The legacy MCP completion call failed for the wrong reason")
      }
    }
    let saved = try await repository.load()
    guard let savedTask = saved.tasks.first(where: { $0.id == task.id }),
      savedTask.completed == task.completed, savedTask.stage == task.stage,
      savedTask.revision == task.revision
    else { throw BoardError.invalid("A legacy MCP completion call changed the task") }
    print("PASS: MCP no longer advertises or accepts the legacy completion write")
  }

  @MainActor static func testMovePersistsWhenRunnerSetupFails() async throws {
    let repository = try LibraryRepository(inMemory: true)
    let preferences = UserDefaults(suiteName: "StageChase.MoveSmoke.\(UUID().uuidString)")!
    preferences.set(false, forKey: "localSyncEnabled")
    let model = AppModel(repository: repository, preferences: preferences, preview: true)
    await model.load()
    var project = Project(name: "Move without runner", directory: "/tmp/move-without-runner")
    project.automationEnabled = true
    guard await model.perform(.createProject(project)) else {
      throw BoardError.invalid(model.error ?? "Could not create move fixture project")
    }
    let task = WorkItem(projectID: project.id, title: "Move before preparing Codex")
    guard await model.perform(.createTask(task)) else {
      throw BoardError.invalid(model.error ?? "Could not create move fixture task")
    }
    model.autoInvokeCodex = true
    model.requestMove(task, to: .implementation)
    try await wait {
      model.library.tasks.first(where: { $0.id == task.id })?.stage == .implementation
        && model.pendingMove?.loading == false
    }
    guard model.pendingMove?.error?.contains("preview mode") == true,
      model.library.tasks.first(where: { $0.id == task.id })?.stage == .implementation,
      model.library.runs.isEmpty
    else { throw BoardError.invalid("Runner setup failure blocked or reversed the stage move") }
    print("PASS: a missing runner leaves the moved task placed and queues no Codex run")
  }

  static func testGitService() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stagechase-git-smoke-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try runGit(["init", "-q"], at: root)
    _ = try runGit(["config", "user.name", "StageChase Fixture"], at: root)
    _ = try runGit(["config", "user.email", "fixture@example.invalid"], at: root)
    let service = GitService()

    let empty = try await service.status(in: root)
    guard empty.head == nil, empty.changedFileCount == 0 else {
      throw BoardError.invalid("An empty Git repository status was not reported correctly")
    }
    let tracked = root.appendingPathComponent("tracked.txt")
    try "original\n".write(to: tracked, atomically: true, encoding: .utf8)
    _ = try runGit(["add", "tracked.txt"], at: root)
    _ = try runGit(["commit", "-m", "fixture base"], at: root)
    try "staged version\n".write(to: tracked, atomically: true, encoding: .utf8)
    _ = try runGit(["add", "tracked.txt"], at: root)
    try "tracked edit\n".write(to: tracked, atomically: true, encoding: .utf8)
    try "new file\n".write(
      to: root.appendingPathComponent("new file.txt"), atomically: true, encoding: .utf8)
    let dirty = try await service.status(in: root)
    guard dirty.changedFileCount == 2, dirty.stagedFileCount == 1,
      dirty.untrackedFileCount == 1, dirty.unstagedFileCount == 1
    else {
      throw BoardError.invalid("Git status did not safely count untracked filenames")
    }
    let result = try await service.commitAll(in: root, taskTitle: "  Add Git status\nfor tasks  ")
    let clean = try await service.status(in: root)
    let message = String(
      decoding: try runGit(["log", "-1", "--format=%s"], at: root), as: UTF8.self
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.head == result.hash, clean.changedFileCount == 0,
      message == "Add Git status for tasks"
    else {
      throw BoardError.invalid("Git task commit did not stage all changes or normalize its title")
    }
    try "external commit\n".write(to: tracked, atomically: true, encoding: .utf8)
    _ = try runGit(["add", "tracked.txt"], at: root)
    _ = try runGit(["commit", "-m", "external commit"], at: root)
    let afterExternalCommit = try await service.status(in: root)
    guard afterExternalCommit.head != result.hash, afterExternalCommit.changedFileCount == 0 else {
      throw BoardError.invalid("Git status did not refresh current HEAD after an external commit")
    }
    do {
      _ = try await service.commitAll(in: root, taskTitle: "Empty commit check")
      throw BoardError.invalid("Git service allowed an empty task commit")
    } catch GitServiceError.noChanges {}
    let nonRepository = FileManager.default.temporaryDirectory
      .appendingPathComponent("stagechase-nonrepo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: nonRepository, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: nonRepository) }
    do {
      _ = try await service.status(in: nonRepository)
      throw BoardError.invalid("Git service treated a non-repository folder as valid")
    } catch GitServiceError.command {}
    print(
      "PASS: Git status tracks clean, dirty, untracked, and empty-repository states; task commits stage all changes"
    )
  }

  @MainActor static func testTaskWorktreeCommit(model: AppModel) async throws {
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent("stagechase-task-worktree-\(UUID().uuidString)", isDirectory: true)
    let root = parent.appendingPathComponent("project", isDirectory: true)
    let worktree = parent.appendingPathComponent("worktree", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    _ = try runGit(["init", "-q"], at: root)
    _ = try runGit(["config", "user.name", "StageChase Fixture"], at: root)
    _ = try runGit(["config", "user.email", "fixture@example.invalid"], at: root)
    try "base\n".write(
      to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    _ = try runGit(["add", "file.txt"], at: root)
    _ = try runGit(["commit", "-m", "base"], at: root)
    _ = try runGit(["worktree", "add", "--detach", worktree.path, "HEAD"], at: root)

    let project = Project(name: "Task worktree fixture", directory: root.path)
    guard await model.saveProject(project, isNew: true) else {
      throw BoardError.invalid(model.error ?? "Could not create the task worktree fixture project")
    }
    let task = WorkItem(projectID: project.id, title: "Commit run worktree")
    guard await model.perform(.createTask(task)) else {
      throw BoardError.invalid(model.error ?? "Could not create the task worktree fixture task")
    }
    var run = AgentRun(task: task, kind: .implementation)
    run.status = .succeeded
    run.workDirectory = worktree.path
    model.library.runs.append(run)
    try "worktree change\n".write(
      to: worktree.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

    guard model.taskUsesSeparateGitWorktree(taskID: task.id) else {
      throw BoardError.invalid("Task Git status did not select its recorded run worktree")
    }
    await model.commitTaskChanges(taskID: task.id)
    let worktreeMessage = String(
      decoding: try runGit(["log", "-1", "--format=%s"], at: worktree), as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let rootStatus = try runGit(["status", "--porcelain"], at: root)
    guard worktreeMessage == "Commit run worktree", rootStatus.isEmpty else {
      throw BoardError.invalid("Task commit did not target only the recorded run worktree")
    }
    print(
      "PASS: task commits target their recorded worktree while project Git status remains scoped to the checkout"
    )
  }

  @MainActor static func testProjectCommit(model: AppModel) async throws {
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent("stagechase-project-commit-\(UUID().uuidString)", isDirectory: true)
    let root = parent.appendingPathComponent("project", isDirectory: true)
    let worktree = parent.appendingPathComponent("worktree", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    _ = try runGit(["init", "-q"], at: root)
    _ = try runGit(["config", "user.name", "StageChase Fixture"], at: root)
    _ = try runGit(["config", "user.email", "fixture@example.invalid"], at: root)
    try "base\n".write(
      to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    _ = try runGit(["add", "file.txt"], at: root)
    _ = try runGit(["commit", "-m", "base"], at: root)
    _ = try runGit(["worktree", "add", "--detach", worktree.path, "HEAD"], at: root)

    let project = Project(name: "Project commit fixture", directory: root.path)
    guard await model.saveProject(project, isNew: true) else {
      throw BoardError.invalid(model.error ?? "Could not create the project commit fixture")
    }
    await model.commitProjectChanges(projectID: project.id)
    guard model.gitActionMessages[project.id]?.contains("Mark a task complete") == true,
      try runGit(["log", "-1", "--format=%s"], at: root) == Data("base\n".utf8)
    else { throw BoardError.invalid("A project without a completed task created a commit") }

    let older = WorkItem(projectID: project.id, title: "Older completed task")
    guard await model.perform(.createTask(older)),
      await model.perform(.complete(older.id, true, expectedRevision: older.revision))
    else { throw BoardError.invalid(model.error ?? "Could not complete the older fixture task") }
    try await Task.sleep(for: .milliseconds(5))
    let latest = WorkItem(projectID: project.id, title: "Complete\n newest project task")
    guard await model.perform(.createTask(latest)),
      await model.perform(.complete(latest.id, true, expectedRevision: latest.revision))
    else { throw BoardError.invalid(model.error ?? "Could not complete the latest fixture task") }
    guard var olderAfterCompletion = model.library.tasks.first(where: { $0.id == older.id }) else {
      throw BoardError.invalid("The older fixture task was not saved")
    }
    olderAfterCompletion.title = "Edited old completed task"
    guard
      await model.perform(
        .editTask(olderAfterCompletion, expectedRevision: olderAfterCompletion.revision))
    else { throw BoardError.invalid(model.error ?? "Could not edit the older completed task") }

    var latestRun = AgentRun(task: latest, kind: .implementation)
    latestRun.status = .succeeded
    latestRun.workDirectory = worktree.path
    model.library.runs.append(latestRun)
    try "project folder change\n".write(
      to: root.appendingPathComponent("project-only.txt"), atomically: true, encoding: .utf8)
    try "worktree must stay dirty\n".write(
      to: worktree.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

    guard model.taskUsesSeparateGitWorktree(taskID: latest.id) else {
      throw BoardError.invalid("The project commit fixture did not attach a separate task worktree")
    }
    await model.commitProjectChanges(projectID: project.id)
    let projectMessage = String(
      decoding: try runGit(["log", "-1", "--format=%s"], at: root), as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let projectStatus = try await GitService().status(in: root)
    let worktreeStatus = String(
      decoding: try runGit(["status", "--porcelain"], at: worktree), as: UTF8.self)
    guard projectMessage == "Complete newest project task", projectStatus.head != nil,
      projectStatus.changedFileCount == 0,
      model.gitStatuses[project.id]?.head == projectStatus.head,
      !worktreeStatus.isEmpty,
      model.gitActionMessages[project.id]?.contains("Complete newest project task") == true
    else {
      throw BoardError.invalid(
        "Project commit did not use the latest completed title, refresh status, or target only the configured folder"
      )
    }
    print(
      "PASS: project commit uses the latest completed task title, refreshes status, and targets the configured folder instead of a task worktree"
    )
  }

  static func runGit(_ arguments: [String], at root: URL) throws -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = root
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw BoardError.invalid(String(decoding: data, as: UTF8.self))
    }
    return data
  }
}
