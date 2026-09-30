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
    let fixture = CommandLine.arguments[1]
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "stagechase-smoke-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let repo = try LibraryRepository(inMemory: true)
    let preferences = UserDefaults(suiteName: "StageChase.RunnerSmoke.\(UUID().uuidString)")!
    preferences.set(false, forKey: "localSyncEnabled")
    let model = AppModel(repository: repo, preferences: preferences, preview: false)
    await model.load()
    model.runner = CodexRunner(model: model, executableOverride: fixture)
    var project = Project(name: "Fixture", directory: folder.path)
    project.automationEnabled = true
    guard await model.saveProject(project, isNew: true) else {
      throw BoardError.invalid(model.error ?? "project")
    }
    for title in [
      "Plan fixture", "BLOCKED_FIXTURE", "APPROVAL_FIXTURE", "STOP_FIXTURE", "CLOSE_FIXTURE",
    ] {
      print("START: \(title)")
      fflush(nil)
      let item = WorkItem(projectID: project.id, title: title, stage: .next)
      _ = await model.perform(.createTask(item, configuration: fixtureModelConfiguration))
      model.kickRunner()
      if title == "APPROVAL_FIXTURE" {
        try await wait { model.runner?.approval != nil }
        try await wait { model.library.latestRun(for: item.id)?.status == .needsInput }
        await model.runner?.answerApproval(allow: true)
      }
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
      case "BLOCKED_FIXTURE": expected = .failed
      case "STOP_FIXTURE": expected = .cancelled
      case "CLOSE_FIXTURE": expected = .interrupted
      default: expected = .succeeded
      }
      guard run.status == expected else {
        throw BoardError.invalid("\(title): \(run.status) / \(run.error ?? model.error ?? "")")
      }
      let expectedStage: WorkflowStage = expected == .succeeded ? .planned : .next
      guard model.library.tasks.first(where: { $0.id == item.id })?.stage == expectedStage else {
        throw BoardError.invalid("Unexpected stage")
      }
      guard !model.library.activity.filter({ $0.runID == run.id }).isEmpty else {
        throw BoardError.invalid("Missing logs")
      }
      print("PASS: \(title) → \(run.status.rawValue), task in \(expectedStage.rawValue)")
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
          model.library.tasks.first(where: { $0.id == item.id })?.stage == .planned,
          model.library.tasks.first(where: { $0.id == item.id })?.planPath == savedPlanPath
        else { throw BoardError.invalid("Closing a successful run changed its result") }
        print("PASS: successful close preserves outcome, stage, summary, and plan")
      }
    }
    print("Offline runner integration checks passed; no real agent turns were started.")
    var blocked = model.library.tasks.first { $0.title == "BLOCKED_FIXTURE" }!
    let previousRun = model.library.latestRun(for: blocked.id)!
    let runCount = model.library.runs.count
    blocked.title = "Retry fixture"
    _ = await model.perform(.editTask(blocked, expectedRevision: blocked.revision))
    await model.retry(previousRun.id)
    try await wait { model.library.latestRun(for: blocked.id)?.status.isActive == false }
    guard let retried = model.library.latestRun(for: blocked.id), retried.status == .succeeded,
      retried.id == previousRun.id, retried.threadID == previousRun.threadID,
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
      run.modelConfiguration == fixtureModelConfiguration
    else { throw BoardError.invalid("Missing isolated worktree") }
    let original = try String(contentsOf: readme, encoding: .utf8)
    let isolated = try String(
      contentsOf: URL(fileURLWithPath: path).appendingPathComponent("README.md"), encoding: .utf8)
    guard original == "Uncommitted user work\n", isolated == "Committed base\n",
      FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: path).appendingPathComponent("to-do/fixture.md").path),
      model.library.tasks.first(where: { $0.id == implementation.id })?.stage == .review
    else {
      throw BoardError.invalid("Dirty checkout isolation failed")
    }
    print("PASS: dirty checkout isolated, original edits preserved, plan copied, task → Review")
  }
}
