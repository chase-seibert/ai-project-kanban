import SwiftUI

struct AgentApproval {
  let id: Any
  let runID: UUID
  let method: String
  let message: String
}

@MainActor @Observable final class CodexRunner {
  private weak var model: AppModel?
  private let connection: any AgentConnection
  private var activeID: UUID?
  private var draining = false
  private var queuePausedForHandoff = false
  private var closingRunID: UUID?
  private var ownedThreads = Set<String>()
  private var connectionGeneration: UInt64 = 0
  private var handlingCompletion = false
  private var eventQueue: [(UInt64, String, [String: Any])] = []
  private var consumingEvents = false
  private var terminalTurnIDs = Set<String>()
  private var finalOutcome: String?
  private var fileChangeDetails: [String: String] = [:]
  private var connectedExecutable: String?
  private let executableOverride: String?
  private let worktreeRootOverride: URL?
  var approval: AgentApproval?
  init(
    model: AppModel, executableOverride: String? = nil,
    connection: any AgentConnection = CodexConnection(), worktreeRootOverride: URL? = nil
  ) {
    self.model = model
    self.executableOverride = executableOverride
    self.connection = connection
    self.worktreeRootOverride = worktreeRootOverride
    connection.notification = { [weak self] method, params in self?.enqueueEvent(method, params) }
    connection.request = { [weak self] id, method, params in
      var request = params
      request["_requestID"] = id
      self?.enqueueEvent(method, request)
    }
    connection.disconnected = { [weak self] message in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.ownedThreads.removeAll()
        self.connectedExecutable = nil
        self.connectionGeneration &+= 1
        await self.fail(message)
      }
    }
  }

  private func executable() throws -> String {
    if let executableOverride { return executableOverride }
    let custom = UserDefaults.standard.string(forKey: "codexExecutable") ?? ""
    let candidates =
      custom.isEmpty
      ? [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
      ] : [custom]
    guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    else {
      throw BoardError.invalid("Codex was not found. Set its executable path in Settings.")
    }
    return path
  }

  private func connect(executable path: String) async throws {
    let wasConnected = connection.connected
    try await connection.connect(executable: path)
    if !wasConnected { connectionGeneration &+= 1 }
    connectedExecutable = path
  }

  func refreshModelCatalog() async throws -> [CodexModelOption] {
    let path = try executable()
    if let connectedExecutable, connectedExecutable != path {
      guard activeID == nil else {
        throw BoardError.invalid("Finish the active Codex run before changing the executable.")
      }
      try await connection.shutdown()
      ownedThreads.removeAll()
      self.connectedExecutable = nil
    }
    try await connect(executable: path)
    var cursor: String?
    var seen = Set<String>()
    var models: [CodexModelOption] = []
    for _ in 0..<20 {
      var params: [String: Any] = ["limit": 100, "includeHidden": false]
      if let cursor { params["cursor"] = cursor }
      let result = try await connection.call("model/list", params)
      guard let data = result["data"] as? [[String: Any]] else {
        throw BoardError.invalid("Codex returned an invalid model catalog.")
      }
      models.append(
        contentsOf: data.compactMap { entry in
          guard let id = entry["id"] as? String, let name = entry["displayName"] as? String else {
            return nil
          }
          let efforts = (entry["supportedReasoningEfforts"] as? [[String: Any]] ?? [])
            .compactMap { $0["reasoningEffort"] as? String }
          return CodexModelOption(
            id: id, displayName: name, hidden: entry["hidden"] as? Bool ?? false,
            reasoningEfforts: efforts)
        })
      guard let next = result["nextCursor"] as? String, !next.isEmpty else { return models }
      guard seen.insert(next).inserted else {
        throw BoardError.invalid("Codex repeated a model catalog page. Refresh and try again.")
      }
      cursor = next
    }
    throw BoardError.invalid("Codex model catalog exceeded the safe page limit.")
  }

  func checkConnection() async {
    do {
      let path = try executable()
      if let connectedExecutable, connectedExecutable != path {
        guard activeID == nil else {
          throw BoardError.invalid("Finish the active Codex run before changing the executable.")
        }
        try await connection.shutdown()
        ownedThreads.removeAll()
        self.connectedExecutable = nil
      }
      try await connect(executable: path)
      let result = try await connection.call("account/read", ["refreshToken": false])
      let authenticated = !(result["account"] is NSNull) && result["account"] != nil
      model?.runnerMessage =
        authenticated
        ? "Codex connected · signed in · StageChase model settings will be used"
        : "Codex connected · sign in with Codex before starting a run"
    } catch { model?.runnerMessage = error.localizedDescription }
  }

  func drain() {
    guard !queuePausedForHandoff, closingRunID == nil, !draining, activeID == nil,
      let model, !model.isPreview,
      let run = model.library.runs.filter({ $0.status == .queued }).sorted(by: {
        $0.createdAt < $1.createdAt
      }).first
    else { return }
    draining = true
    activeID = run.id
    finalOutcome = nil
    fileChangeDetails.removeAll()
    Task {
      await start(run)
      draining = false
      if activeID == nil, model.library.runs.first(where: { $0.id == run.id })?.status == .succeeded
      {
        drain()
      }
    }
  }

  func resumeQueueAndDrain() {
    queuePausedForHandoff = false
    drain()
  }

  func closeAvailability(runID: UUID) -> String? {
    guard let run = model?.library.runs.first(where: { $0.id == runID }),
      let threadID = run.threadID, !threadID.isEmpty
    else { return "This run has no saved Codex session to release." }
    if closingRunID == runID { return "Closing…" }
    if closingRunID != nil { return "Another session is closing." }
    if activeID != nil && activeID != runID {
      return "Another Codex run must finish or be stopped before this session can close."
    }
    return nil
  }

  func closeSession(runID: UUID) async {
    guard let model, let run = model.library.runs.first(where: { $0.id == runID }),
      let threadID = run.threadID, !threadID.isEmpty
    else {
      model?.runnerMessage = "This run has no saved Codex session to release."
      return
    }
    guard closingRunID == nil else { return }
    guard activeID == nil || activeID == runID else {
      model.runnerMessage =
        "Another Codex run must finish or be stopped before this session can close."
      return
    }
    closingRunID = runID
    queuePausedForHandoff = true
    let shouldShutdown = ownedThreads.contains(threadID) && connection.connected
    if activeID == runID, let turn = run.turnID {
      do {
        _ = try await connection.call(
          "turn/interrupt", ["threadId": threadID, "turnId": turn], timeout: .seconds(1))
      } catch {
        // Confirmed process shutdown below can still establish release.
      }
      for _ in 0..<10 {
        if terminalTurnIDs.contains(turn) { break }
        try? await Task.sleep(for: .milliseconds(50))
      }
      terminalTurnIDs.remove(turn)
    }
    do {
      guard closingRunID == runID else { return }
      if shouldShutdown { try await connection.shutdown() }
      if shouldShutdown {
        ownedThreads.removeAll()
        connectedExecutable = nil
        connectionGeneration &+= 1
      }
      approval = nil
      if activeID == runID { activeID = nil }
      if activeID == nil { draining = false }
      guard await model.perform(.closeRun(runID)) else {
        closingRunID = nil
        model.runnerMessage =
          "The Codex session was released, but StageChase could not save that handoff. Retry Close Codex session to finish recording it."
        return
      }
      model.runnerMessage =
        "Session released from StageChase. Open the saved session in Codex to continue."
      closingRunID = nil
    } catch {
      closingRunID = nil
      model.runnerMessage = error.localizedDescription
    }
  }

  private func start(_ initial: AgentRun) async {
    guard let model,
      let item = model.library.tasks.first(where: { $0.id == initial.taskID }),
      let project = model.library.projects.first(where: { $0.id == initial.projectID }),
      project.automationEnabled
    else {
      await fail("Project automation is disabled or the task is missing.")
      return
    }
    do {
      var directoryFlag: ObjCBool = false
      let root = URL(fileURLWithPath: project.directory).standardizedFileURL
        .resolvingSymlinksInPath()
      guard project.directory.hasPrefix("/"), root.path != "/",
        root.path != FileManager.default.homeDirectoryForCurrentUser.path,
        FileManager.default.fileExists(atPath: root.path, isDirectory: &directoryFlag),
        directoryFlag.boolValue
      else {
        throw BoardError.invalid("Choose a specific, existing project folder in project settings.")
      }
      try await connect(executable: executable())
      let account = try await connection.call("account/read", ["refreshToken": false])
      guard account["account"] != nil, !(account["account"] is NSNull) else {
        throw BoardError.invalid("Sign in to Codex, then retry this run.")
      }
      guard let configuration = (currentRun() ?? initial).modelConfiguration else {
        throw BoardError.invalid(
          "This run has no confirmed model choice. Retry it and confirm a model first.")
      }
      let catalog = try await refreshModelCatalog()
      guard let selectedModel = catalog.first(where: { $0.id == configuration.modelID }),
        selectedModel.reasoningEfforts.contains(configuration.effort)
      else {
        throw BoardError.invalid(
          "The saved model or reasoning effort is no longer available. Choose a new model for a new run."
        )
      }
      guard activeID == initial.id else { return }
      var run = currentRun() ?? initial
      run.status = .running
      run.summary = "Preparing the workspace…"
      run.updatedAt = .now
      guard await model.perform(.updateRun(run)) else {
        activeID = nil
        return
      }
      let directory = try await workingDirectory(run: run, projectRoot: root, item: item)
      guard activeID == initial.id else { return }
      run = currentRun() ?? run
      run.workDirectory = directory.path
      guard await model.perform(.updateRun(run)) else {
        throw BoardError.invalid("Could not save the working directory.")
      }
      let result: [String: Any]
      if let thread = run.threadID {
        result = try await connection.call(
          "thread/resume",
          [
            "threadId": thread, "cwd": directory.path, "approvalPolicy": "on-request",
            "sandbox": "workspace-write", "model": configuration.modelID,
          ])
      } else {
        result = try await connection.call(
          "thread/start",
          [
            "cwd": directory.path, "approvalPolicy": "on-request", "sandbox": "workspace-write",
            "model": configuration.modelID,
          ])
      }
      guard let thread = result["thread"] as? [String: Any], let threadID = thread["id"] as? String
      else { throw BoardError.invalid("Codex returned no session ID.") }
      guard activeID == initial.id else { return }
      run = currentRun() ?? run
      run.threadID = threadID
      ownedThreads.insert(threadID)
      run.summary = "Codex is starting \(run.kind.rawValue)…"
      guard await model.perform(.updateRun(run)) else {
        throw BoardError.invalid("Could not save the Codex session ID. The turn was not started.")
      }
      _ = try? await connection.call(
        "thread/name/set", ["threadId": threadID, "name": "StageChase · \(item.title)"])
      guard activeID == initial.id, closingRunID != initial.id else { return }
      let resultTurn = try await connection.call(
        "turn/start",
        [
          "threadId": threadID,
          "input": [["type": "text", "text": prompt(item: item, run: run), "text_elements": []]],
          "cwd": directory.path,
          "approvalPolicy": "on-request",
          "model": configuration.modelID,
          "effort": configuration.effort,
          "sandboxPolicy": [
            "type": "workspaceWrite", "writableRoots": [directory.path], "networkAccess": false,
          ],
          "outputSchema": [
            "type": "object", "additionalProperties": false,
            "properties": [
              "outcome": ["type": "string", "enum": ["completed", "blocked"]],
              "summary": ["type": "string"],
            ],
            "required": ["outcome", "summary"],
          ],
        ])
      if activeID == initial.id, closingRunID != initial.id, var latest = currentRun(),
        let turn = resultTurn["turn"] as? [String: Any]
      {
        latest.turnID = turn["id"] as? String
        await model.perform(.updateRun(latest))
      }
      model.runnerMessage = "Codex is connected. Progress and approval requests appear here."
    } catch {
      if closingRunID != initial.id, activeID == initial.id {
        await fail(error.localizedDescription)
      }
    }
  }

  private func prompt(item: WorkItem, run: AgentRun) -> String {
    let common = """
      You are working on a StageChase task in this project. Follow its AGENTS.md instructions.
      Task: \(item.title)
      Details: \(item.notes)
      Do not commit, push, publish, deploy, send messages, or delete unrelated files. Do not mark the task complete.
      Keep progress updates concise and use the plan tool so StageChase can display progress. Ask for approval when required; never bypass sandbox restrictions.
      Your final structured response must use outcome=completed only when the requested work and verification are finished; otherwise use outcome=blocked and explain what remains in summary.
      """
    if run.kind == .planning {
      return common + """

        Plan only; do not implement application code. Inspect the relevant project, then write a concrete implementation plan to to-do/\(item.id.uuidString.lowercased()).md.
        Include the problem, scope, steps, risks, and verification. This is the only file you may create or modify for this planning turn.
        If this is a retry, inspect the existing plan and session progress before doing more work. End by stating the saved plan path.
        """
    }
    return common + """

      Implement the approved plan at \(item.planPath ?? ""). Read that file first. Preserve all unrelated work.
      If this is a retry, inspect changes already made and continue; do not repeat completed operations.
      Run focused tests and summarize verification, changed files, and any remaining limitations. If blocked or incomplete, clearly report failure rather than claiming completion.
      """
  }

  private func workingDirectory(run: AgentRun, projectRoot: URL, item: WorkItem) async throws -> URL
  {
    if let existing = run.workDirectory {
      guard FileManager.default.fileExists(atPath: existing) else {
        throw BoardError.invalid("The saved working folder is missing. Restore it before retrying.")
      }
      let directory = URL(fileURLWithPath: existing)
      if run.kind == .implementation, let relative = item.planPath {
        let destination = try safePlan(relative, root: directory)
        if !FileManager.default.fileExists(atPath: destination.path) {
          let data = try Data(contentsOf: safePlan(relative, root: projectRoot))
          try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
          try data.write(to: destination, options: .atomic)
        }
      }
      return directory
    }
    if run.kind == .planning { return projectRoot }
    guard let relative = item.planPath else {
      throw BoardError.invalid("Implementation needs a saved plan.")
    }
    let plan = try safePlan(relative, root: projectRoot)
    let data = try Data(contentsOf: plan)
    guard !data.isEmpty else { throw BoardError.invalid("The saved plan is empty.") }
    let topLevel = try await runGit(["rev-parse", "--show-toplevel"], at: projectRoot)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      URL(fileURLWithPath: topLevel).resolvingSymlinksInPath()
        == projectRoot.resolvingSymlinksInPath()
    else {
      throw BoardError.invalid(
        "Implementation requires the repository root folder, not one of its subfolders.")
    }
    let status = try await runGit(["status", "--porcelain"], at: projectRoot)
    guard !status.isEmpty else { return projectRoot }
    let parent: URL
    if let worktreeRootOverride {
      parent = worktreeRootOverride
    } else {
      parent = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("StageChase/Worktrees", isDirectory: true)
    }
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let worktree = parent.appendingPathComponent(run.id.uuidString)
    _ = try await runGit(["worktree", "add", "--detach", worktree.path, "HEAD"], at: projectRoot)
    // Persist immediately so an interrupted retry reuses this exact checkout.
    if var current = currentRun() {
      current.workDirectory = worktree.path
      guard await model?.perform(.updateRun(current)) == true else {
        throw BoardError.invalid(
          "Worktree created but its record could not be saved: \(worktree.path)")
      }
    }
    let destination = try safePlan(relative, root: worktree)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: destination, options: .atomic)
    await log(
      "Original checkout has local changes. Using an isolated HEAD worktree at \(worktree.path). Only the approved plan was copied; other uncommitted changes remain in the original checkout."
    )
    return worktree
  }

  private func safePlan(_ relative: String, root: URL) throws -> URL {
    try PlanFileStore.resolve(projectDirectory: root.path, relativePath: relative)
  }

  private func enqueueEvent(_ method: String, _ params: [String: Any]) {
    guard activeID != nil else { return }
    // Retain completed public items, not private reasoning or token-by-token deltas.
    guard
      params["_requestID"] != nil
        || [
          "turn/started", "turn/completed", "turn/plan/updated", "item/started", "item/completed",
          "error",
        ].contains(method)
    else { return }
    eventQueue.append((connectionGeneration, method, params))
    guard !consumingEvents else { return }
    consumingEvents = true
    Task {
      while !eventQueue.isEmpty {
        let (generation, method, params) = eventQueue.removeFirst()
        guard generation == connectionGeneration else { continue }
        await event(method, params)
      }
      consumingEvents = false
    }
  }

  private func event(_ method: String, _ params: [String: Any]) async {
    if let id = params["_requestID"] {
      await handleRequest(id, method, params)
      return
    }
    if method == "turn/completed",
      let turnID = (params["turn"] as? [String: Any])?["id"] as? String
    {
      terminalTurnIDs.insert(turnID)
    }
    guard closingRunID == nil, let model, var run = currentRun(),
      params["threadId"] as? String == run.threadID
    else { return }
    run.updatedAt = .now
    switch method {
    case "turn/started":
      run.turnID = (params["turn"] as? [String: Any])?["id"] as? String
      run.summary = "Codex is working…"
      await model.perform(.updateRun(run))
    case "turn/plan/updated":
      run.steps = (params["plan"] as? [[String: Any]] ?? []).compactMap {
        guard let text = $0["step"] as? String, let status = $0["status"] as? String else {
          return nil
        }
        return ProgressStep(text: text, status: status)
      }
      if let explanation = params["explanation"] as? String, !explanation.isEmpty {
        run.summary = String(explanation.prefix(1000))
      }
      await model.perform(.updateRun(run))
    case "item/started", "item/completed":
      guard let item = params["item"] as? [String: Any], let type = item["type"] as? String else {
        return
      }
      if type == "commandExecution", let command = item["command"] as? String {
        run.summary = String(("Running: " + command).prefix(600))
        await model.perform(.updateRun(run))
        if method == "item/completed" {
          let output = item["aggregatedOutput"] as? String ?? ""
          await log("$ \(command)\n\(String(output.suffix(6000)))")
        }
      } else if method == "item/completed", type == "agentMessage",
        let text = item["text"] as? String
      {
        if let data = text.data(using: .utf8),
          let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let outcome = result["outcome"] as? String
        {
          finalOutcome = outcome
          run.summary = String((result["summary"] as? String ?? text).prefix(1600))
        } else {
          run.summary = String(text.prefix(1600))
        }
        await model.perform(.updateRun(run))
        await log(String(text.prefix(16000)))
      } else if type == "fileChange" {
        let changes = item["changes"] as? [[String: Any]] ?? []
        if let itemID = item["id"] as? String {
          fileChangeDetails[itemID] = changes.map { change in
            (change["path"] as? String ?? "Unknown path") + "\n"
              + String((change["diff"] as? String ?? "").prefix(12000))
          }.joined(separator: "\n\n")
        }
        if method == "item/completed" {
          await log(
            "Files changed: " + changes.compactMap { $0["path"] as? String }.joined(separator: ", ")
          )
        }
      }
    case "turn/completed":
      if let eventTurnID = (params["turn"] as? [String: Any])?["id"] as? String,
        let currentTurnID = run.turnID, eventTurnID != currentTurnID
      {
        return
      }
      guard !handlingCompletion else { return }
      handlingCompletion = true
      defer { handlingCompletion = false }
      let turn = params["turn"] as? [String: Any] ?? [:]
      if turn["status"] as? String == "completed" {
        do {
          guard finalOutcome == "completed" else {
            throw BoardError.invalid("Codex did not confirm successful completion. \(run.summary)")
          }
          var planPath: String?
          if run.kind == .planning {
            let relative = "to-do/\(run.taskID.uuidString.lowercased()).md"
            let root = URL(fileURLWithPath: run.workDirectory ?? "")
            let path = try safePlan(relative, root: root)
            guard let text = try? String(contentsOf: path, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
              throw BoardError.invalid(
                "Codex ended without writing the expected plan. Inspect the session, then retry.")
            }
            planPath = relative
          }
          guard closingRunID != run.id else { return }
          guard await model.perform(.finishRun(run.id, planPath: planPath)) else {
            throw BoardError.invalid(
              "Could not save completion; review the session before retrying.")
          }
          activeID = nil
          approval = nil
          drain()
        } catch { await fail(error.localizedDescription) }
      } else {
        let error = turn["error"] as? [String: Any]
        await fail(
          error?["message"] as? String ?? "Codex turn \(turn["status"] as? String ?? "stopped").")
      }
    case "error":
      if params["willRetry"] as? Bool != true {
        let error = params["error"] as? [String: Any]
        await fail(error?["message"] as? String ?? "Codex reported an error.")
      }
    default: break
    }
  }

  private func handleRequest(_ id: Any, _ method: String, _ params: [String: Any]) async {
    guard closingRunID == nil else {
      try? connection.reject(id: id, message: "StageChase is closing this session.")
      return
    }
    guard let run = currentRun() else {
      try? connection.reject(id: id, message: "No active StageChase run")
      return
    }
    guard approval == nil, params["threadId"] as? String == run.threadID else {
      try? connection.reject(id: id, message: "Mismatched or concurrent approval request")
      await fail("Codex sent overlapping approval requests. Continue in the saved Codex session.")
      return
    }
    if method == "item/commandExecution/requestApproval"
      || method == "item/fileChange/requestApproval"
    {
      let fileRequest = method == "item/fileChange/requestApproval"
      let diff = (params["itemId"] as? String).flatMap { fileChangeDetails[$0] }
      let needsBroaderGrant = params["grantRoot"] as? String != nil
      let unsupportedCommand =
        !fileRequest
        && ((params["command"] as? String)?.isEmpty != false
          || (params["kind"] as? String ?? "command") != "command")
      guard !(fileRequest && (diff?.isEmpty != false || needsBroaderGrant)), !unsupportedCommand
      else {
        try? connection.respond(id: id, result: ["decision": "cancel"])
        await fail(
          "This permission request needs more context or broader access than StageChase can safely present. Review it in the saved Codex session."
        )
        return
      }
      var details = [
        params["reason"] as? String, params["command"] as? String, params["cwd"] as? String,
      ].compactMap { $0 }.joined(separator: "\n")
      if fileRequest, let diff { details += "\n\n" + diff }
      approval = AgentApproval(
        id: id, runID: run.id, method: method,
        message: details.isEmpty ? "Codex requests permission to modify project files." : details)
      guard var latest = currentRun() else { return }
      latest.status = .needsInput
      latest.summary = "Waiting for your approval in StageChase."
      await model?.perform(.updateRun(latest))
      model?.showActivity = true
    } else {
      try? connection.reject(
        id: id,
        message: "StageChase cannot answer this interactive request. Stop and continue in Codex.")
      await fail(
        "Codex needs an interactive response (\(method)). Open the saved session in Codex to continue."
      )
    }
  }

  func answerApproval(allow: Bool) async {
    guard let approval, approval.runID == activeID, closingRunID == nil else { return }
    do {
      if var run = currentRun() {
        run.status = .running
        run.summary =
          allow
          ? "Approved once. Codex is continuing."
          : "Permission denied. Codex is continuing within its permissions."
        await model?.perform(.updateRun(run))
      }
      try connection.respond(id: approval.id, result: ["decision": allow ? "accept" : "decline"])
      self.approval = nil
    } catch { await fail(error.localizedDescription) }
  }

  func stop(_ id: UUID) async {
    guard let model, var run = model.library.runs.first(where: { $0.id == id }), run.status.isActive
    else { return }
    if activeID == id {
      // Stop the owned server as well as the turn; an interrupted start cannot later launch work.
      activeID = nil
      if let thread = run.threadID, let turn = run.turnID {
        _ = try? await connection.call("turn/interrupt", ["threadId": thread, "turnId": turn])
      }
      do {
        try await connection.shutdown()
      } catch {
        activeID = id
        model.runnerMessage = error.localizedDescription
        return
      }
      ownedThreads.removeAll()
      connectedExecutable = nil
      connectionGeneration &+= 1
      approval = nil
      draining = false
    }
    run.status = .cancelled
    run.summary = "Stopped by you. Files already changed are preserved."
    run.updatedAt = .now
    await model.perform(.updateRun(run))
    drain()
  }

  private func fail(_ message: String) async {
    guard var run = currentRun() else { return }
    run.status = .failed
    run.error = message
    run.summary = "Needs attention"
    run.updatedAt = .now
    activeID = nil
    approval = nil
    do {
      try await connection.shutdown()
      ownedThreads.removeAll()
      connectedExecutable = nil
      connectionGeneration &+= 1
    } catch {
      model?.runnerMessage =
        "\(message) The Codex app-server did not confirm shutdown: \(error.localizedDescription)"
    }
    await model?.perform(.updateRun(run))
    if connection.connected {
      model?.runnerMessage =
        "\(message) The Codex app-server did not confirm shutdown; use Close Codex session to retry release."
    } else {
      model?.runnerMessage = message
    }
    // A failure pauses the queue. A deliberate new action or retry may resume it.
  }
  private func currentRun() -> AgentRun? { model?.library.runs.first { $0.id == activeID } }
  private func log(_ message: String) async {
    guard let run = currentRun() else { return }
    await model?.perform(
      .log(Activity(message, projectID: run.projectID, taskID: run.taskID, runID: run.id)))
  }
}

private func runGit(_ arguments: [String], at directory: URL) async throws -> String {
  try await Task.detached {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", directory.path] + arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw BoardError.invalid("Git: " + String(output.suffix(2000)))
    }
    return output
  }.value
}
