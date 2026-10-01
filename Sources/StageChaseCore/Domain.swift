import Foundation

public enum WorkflowStage: String, Codable, CaseIterable, Identifiable, Sendable {
  case inbox, next, planned, implementation, review
  public var id: String { rawValue }
  public var title: String { rawValue == "next" ? "Next" : rawValue.capitalized }
  public var symbol: String {
    switch self {
    case .inbox: "tray"
    case .next: "sparkles"
    case .planned: "list.bullet.clipboard"
    case .implementation: "hammer"
    case .review: "checkmark.seal"
    }
  }
  public var subtitle: String {
    switch self {
    case .inbox: "Ideas start here"
    case .next: "Ready for a plan"
    case .planned: "A clear path forward"
    case .implementation: "Make it happen"
    case .review: "Your final say"
    }
  }
}

public enum CodexModelSelection: Codable, Hashable, Sendable {
  case latestLuna
  case model(String)
}

public struct CodexModelConfiguration: Codable, Hashable, Sendable {
  public var selection: CodexModelSelection
  public var effort: String
  public init(selection: CodexModelSelection = .latestLuna, effort: String = "high") {
    self.selection = selection
    self.effort = effort
  }
  public var summary: String {
    let model =
      switch selection {
      case .latestLuna: "Latest Luna"
      case .model(let id): id
      }
    return "\(model) · \(effort.capitalized)"
  }
}

public enum CodexModelScope: String, Codable, Hashable, Sendable {
  case global, project, task
  public var title: String { rawValue.capitalized }
}

public enum CodexApprovalMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case approveForMe
  case askMe
  case autoApproveRequests

  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .approveForMe: "Approve for me"
    case .askMe: "Ask me"
    case .autoApproveRequests: "Auto-approve requests"
    }
  }
  public var approvalPolicy: String {
    switch self {
    case .approveForMe: "never"
    case .askMe, .autoApproveRequests: "on-request"
    }
  }
}

public struct ResolvedCodexConfiguration: Codable, Hashable, Sendable {
  public var selection: CodexModelSelection
  public var modelID: String
  public var effort: String
  public var scope: CodexModelScope
  public init(
    selection: CodexModelSelection, modelID: String, effort: String, scope: CodexModelScope
  ) {
    self.selection = selection
    self.modelID = modelID
    self.effort = effort
    self.scope = scope
  }
  public var summary: String {
    let model = selection == .latestLuna ? "Latest Luna → \(modelID)" : modelID
    return "\(model) · \(effort.capitalized) · \(scope.title)"
  }
}

public struct CodexModelOption: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var displayName: String
  public var hidden: Bool
  public var reasoningEfforts: [String]
  public init(id: String, displayName: String, hidden: Bool = false, reasoningEfforts: [String]) {
    self.id = id
    self.displayName = displayName
    self.hidden = hidden
    self.reasoningEfforts = reasoningEfforts
  }
}

public enum CodexModelResolver {
  public static func effective(
    task: CodexModelConfiguration?, project: CodexModelConfiguration?,
    global: CodexModelConfiguration
  ) -> (configuration: CodexModelConfiguration, scope: CodexModelScope) {
    if let task { return (task, .task) }
    if let project { return (project, .project) }
    return (global, .global)
  }

  public static func resolve(
    _ configuration: CodexModelConfiguration, scope: CodexModelScope,
    catalog: [CodexModelOption]
  ) throws -> ResolvedCodexConfiguration {
    let model = try option(for: configuration.selection, catalog: catalog)
    guard model.reasoningEfforts.contains(configuration.effort) else {
      throw BoardError.invalid(
        "\(model.displayName) does not support ‘\(configuration.effort)’ reasoning. Choose a supported effort."
      )
    }
    return ResolvedCodexConfiguration(
      selection: configuration.selection, modelID: model.id, effort: configuration.effort,
      scope: scope)
  }

  public static func option(
    for selection: CodexModelSelection, catalog: [CodexModelOption]
  ) throws -> CodexModelOption {
    let visible = catalog.filter { !$0.hidden }
    let model: CodexModelOption
    switch selection {
    case .model(let id):
      guard let match = visible.first(where: { $0.id == id }) else {
        throw BoardError.invalid(
          "The selected Codex model ‘\(id)’ is unavailable. Refresh the model list or choose another model."
        )
      }
      model = match
    case .latestLuna:
      let candidates = visible.compactMap { option -> (CodexModelOption, [Int])? in
        guard let version = stableLunaVersion(option.id) else { return nil }
        return (option, version)
      }.sorted { versionLess($0.1, $1.1) }
      guard let newestVersion = candidates.last?.1 else {
        throw BoardError.invalid(
          "No stable Luna model is available in the connected Codex catalog. Choose an explicit model or refresh the list."
        )
      }
      let newest = candidates.filter {
        !versionLess($0.1, newestVersion) && !versionLess(newestVersion, $0.1)
      }
      guard newest.count == 1, let latest = newest.first?.0 else {
        throw BoardError.invalid(
          "The Codex catalog has multiple Luna models at the newest version. Choose an explicit model."
        )
      }
      model = latest
    }
    return model
  }

  private static func stableLunaVersion(_ id: String) -> [Int]? {
    guard id.hasPrefix("gpt-"), id.hasSuffix("-luna") else { return nil }
    let version = id.dropFirst(4).dropLast(5)
    let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
    guard !pieces.isEmpty, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
      return nil
    }
    let numbers = pieces.compactMap { Int($0) }
    return numbers.count == pieces.count ? numbers : nil
  }

  private static func versionLess(_ lhs: [Int], _ rhs: [Int]) -> Bool {
    for index in 0..<max(lhs.count, rhs.count) {
      let left = index < lhs.count ? lhs[index] : 0
      let right = index < rhs.count ? rhs[index] : 0
      if left != right { return left < right }
    }
    return false
  }
}

public struct Project: Codable, Hashable, Identifiable, Sendable {
  public var id = UUID()
  public var name: String
  public var directory = ""
  public var automationEnabled = false
  public var modelOverride: CodexModelConfiguration?
  public var createdAt = Date()
  public init(name: String, directory: String = "") {
    self.name = name
    self.directory = directory
  }
}

public struct WorkItem: Codable, Hashable, Identifiable, Sendable {
  public var id = UUID()
  public var projectID: UUID
  public var title: String
  public var notes = ""
  public var stage: WorkflowStage = .inbox
  public var rank = 0
  public var completed = false
  public var revision = 0
  public var planPath: String?
  public var modelOverride: CodexModelConfiguration?
  public var createdAt = Date()
  public var updatedAt = Date()
  public init(projectID: UUID, title: String, stage: WorkflowStage = .inbox) {
    self.projectID = projectID
    self.title = title
    self.stage = stage
  }

  public static func canonicalPlanPath(for id: UUID) -> String {
    "to-do/\(id.uuidString.lowercased()).md"
  }
}

public enum RunStatus: String, Codable, CaseIterable, Sendable {
  case queued, readyForHandoff, running, needsInput, succeeded, failed, interrupted, cancelled
  public var title: String {
    switch self {
    case .needsInput: "Needs your approval"
    case .readyForHandoff: "Ready for Codex Desktop"
    case .succeeded: "Finished"
    default: rawValue.capitalized
    }
  }
  public var isActive: Bool { [.queued, .running, .needsInput].contains(self) }
}

public enum RunKind: String, Codable, Sendable { case planning, implementation, task }

public struct AgentRun: Codable, Hashable, Identifiable, Sendable {
  public var id = UUID()
  public var taskID: UUID
  public var projectID: UUID
  public var kind: RunKind
  public var status: RunStatus = .queued
  public var threadID: String?
  public var turnID: String?
  public var workDirectory: String?
  public var summary = "Waiting for the Mac runner"
  public var error: String?
  public var steps: [ProgressStep] = []
  public var modelConfiguration: ResolvedCodexConfiguration?
  public var handoffContext: String?
  public var createdAt = Date()
  public var updatedAt = Date()
  public init(task: WorkItem, kind: RunKind, modelConfiguration: ResolvedCodexConfiguration? = nil)
  {
    taskID = task.id
    projectID = task.projectID
    self.kind = kind
    self.modelConfiguration = modelConfiguration
  }
}

public struct ProgressStep: Codable, Hashable, Sendable {
  public var text: String
  public var status: String
  public init(text: String, status: String) {
    self.text = text
    self.status = status
  }
}

public struct Activity: Codable, Hashable, Identifiable, Sendable {
  public var id = UUID()
  public var projectID: UUID?
  public var taskID: UUID?
  public var runID: UUID?
  public var message: String
  public var date = Date()
  public init(_ message: String, projectID: UUID? = nil, taskID: UUID? = nil, runID: UUID? = nil) {
    self.message = message
    self.projectID = projectID
    self.taskID = taskID
    self.runID = runID
  }
}

public struct Library: Codable, Equatable, Sendable {
  public var formatVersion = 1
  public var projects: [Project] = []
  public var tasks: [WorkItem] = []
  public var runs: [AgentRun] = []
  public var activity: [Activity] = []
  public init() {}
  public func items(in project: UUID, stage: WorkflowStage? = nil, completed: Bool = false)
    -> [WorkItem]
  {
    tasks.filter {
      $0.projectID == project && (stage == nil || $0.stage == stage) && (completed || !$0.completed)
    }
    .sorted { $0.rank == $1.rank ? $0.createdAt < $1.createdAt : $0.rank < $1.rank }
  }
  public func latestRun(for task: UUID) -> AgentRun? {
    runs.filter { $0.taskID == task }.max { $0.createdAt < $1.createdAt }
  }
  public func validate() throws {
    guard formatVersion == 1 else {
      throw BoardError.invalid("This library needs a newer StageChase version.")
    }
    guard Set(projects.map(\.id)).count == projects.count,
      Set(tasks.map(\.id)).count == tasks.count,
      Set(runs.map(\.id)).count == runs.count
    else { throw BoardError.invalid("Duplicate identities in the library.") }
    let projectIDs = Set(projects.map(\.id))
    let taskIDs = Set(tasks.map(\.id))
    guard tasks.allSatisfy({ projectIDs.contains($0.projectID) }),
      runs.allSatisfy({ projectIDs.contains($0.projectID) && taskIDs.contains($0.taskID) })
    else {
      throw BoardError.invalid("The library contains orphaned tasks or runs.")
    }
  }
}

public enum BoardError: LocalizedError, Sendable {
  case missing, conflict, busy
  case invalid(String)
  public var errorDescription: String? {
    switch self {
    case .missing: "This item no longer exists."
    case .conflict:
      "This task changed while you were editing. Close and reopen it to use the latest version."
    case .busy: "Stop the active Codex run before changing this task."
    case .invalid(let message): message
    }
  }
}

public enum Mutation: Sendable {
  case createProject(Project)
  case editProject(Project)
  case createTask(WorkItem, configuration: ResolvedCodexConfiguration? = nil)
  case createManualRun(AgentRun)
  case editTask(WorkItem, expectedRevision: Int)
  case move(
    UUID, WorkflowStage, expectedRevision: Int, configuration: ResolvedCodexConfiguration? = nil)
  case complete(UUID, Bool, expectedRevision: Int)
  case deleteTask(UUID, expectedRevision: Int)
  case restoreTask(UUID, WorkItem?, expectedRevision: Int?)
  case reorder(UUID, before: UUID, expectedRevision: Int)
  case retry(UUID, configuration: ResolvedCodexConfiguration? = nil)
  case closeRun(UUID)
  case updateRun(AgentRun)
  case finishRun(UUID, planPath: String?)
  case log(Activity)
}

public enum BoardReducer {
  /// A confirmed user command is the only way to enqueue work. Reading state never triggers Codex.
  public static func apply(_ command: Mutation, to original: Library) throws -> Library {
    var state = original
    func taskIndex(_ id: UUID, _ revision: Int? = nil) throws -> Int {
      guard let index = state.tasks.firstIndex(where: { $0.id == id }) else {
        throw BoardError.missing
      }
      if let revision, state.tasks[index].revision != revision { throw BoardError.conflict }
      return index
    }
    func ensureIdle(_ id: UUID) throws {
      guard !state.runs.contains(where: { $0.taskID == id && $0.status.isActive }) else {
        throw BoardError.busy
      }
    }
    func enqueue(_ item: inout WorkItem, configuration: ResolvedCodexConfiguration?) throws {
      guard let project = state.projects.first(where: { $0.id == item.projectID }) else {
        throw BoardError.missing
      }
      guard project.automationEnabled, [.next, .implementation].contains(item.stage),
        let configuration,
        !state.runs.contains(where: { $0.taskID == item.id && $0.status.isActive })
      else {
        return
      }
      guard !project.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw BoardError.invalid("Choose a project folder before enabling Codex.")
      }
      if item.stage == .next, item.planPath == nil {
        item.planPath = WorkItem.canonicalPlanPath(for: item.id)
      }
      let run = AgentRun(
        task: item, kind: item.stage == .next ? .planning : .implementation,
        modelConfiguration: configuration)
      state.runs.append(run)
      state.activity.append(
        Activity(
          "Codex queued · \(configuration.summary)", projectID: item.projectID,
          taskID: item.id, runID: run.id))
    }
    switch command {
    case .createProject(var project):
      project.name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !project.name.isEmpty else { throw BoardError.invalid("Give this project a name.") }
      guard !state.projects.contains(where: { $0.id == project.id }) else {
        throw BoardError.invalid("Project already exists.")
      }
      state.projects.append(project)
      state.activity.append(Activity("Created project “\(project.name)”.", projectID: project.id))
    case .editProject(let project):
      guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw BoardError.invalid("Give this project a name.")
      }
      guard let index = state.projects.firstIndex(where: { $0.id == project.id }) else {
        throw BoardError.missing
      }
      if (project.directory != state.projects[index].directory
        || project.automationEnabled != state.projects[index].automationEnabled)
        && state.runs.contains(where: { $0.projectID == project.id && $0.status.isActive })
      {
        throw BoardError.busy
      }
      state.projects[index] = project
    case .createTask(var item, let configuration):
      item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !item.title.isEmpty else { throw BoardError.invalid("Give this task a title.") }
      guard state.projects.contains(where: { $0.id == item.projectID }),
        !state.tasks.contains(where: { $0.id == item.id })
      else { throw BoardError.missing }
      item.rank =
        (state.tasks.filter { $0.projectID == item.projectID && $0.stage == item.stage }.map(\.rank)
          .max() ?? -1) + 1
      try enqueue(&item, configuration: configuration)
      state.tasks.append(item)
      state.activity.append(
        Activity(
          "Added “\(item.title)” to \(item.stage.title).", projectID: item.projectID,
          taskID: item.id))
    case .createManualRun(let run):
      guard run.kind == .task, run.status == .readyForHandoff,
        state.tasks.contains(where: { $0.id == run.taskID && $0.projectID == run.projectID }),
        !state.runs.contains(where: { $0.id == run.id })
      else { throw BoardError.invalid("The Codex Desktop handoff is invalid.") }
      state.runs.append(run)
      state.activity.append(
        Activity(
          "Prepared a Codex Desktop handoff.", projectID: run.projectID, taskID: run.taskID,
          runID: run.id))
    case .editTask(var item, let expectedRevision):
      let index = try taskIndex(item.id, expectedRevision)
      try ensureIdle(item.id)
      guard item.projectID == state.tasks[index].projectID, item.stage == state.tasks[index].stage
      else { throw BoardError.invalid("Use Move to change a task’s stage.") }
      item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !item.title.isEmpty else { throw BoardError.invalid("Give this task a title.") }
      item.revision += 1
      item.updatedAt = .now
      state.tasks[index] = item
    case .move(let id, let stage, let revision, let configuration):
      let index = try taskIndex(id, revision)
      if state.tasks[index].stage == stage { return state }
      var item = state.tasks[index]
      item.stage = stage
      item.rank =
        (state.tasks.filter { $0.projectID == item.projectID && $0.stage == stage }
          .map(\.rank).max() ?? -1) + 1
      item.revision += 1
      item.updatedAt = .now
      try enqueue(&item, configuration: configuration)
      state.tasks[index] = item
      state.activity.append(
        Activity(
          "Moved “\(state.tasks[index].title)” to \(stage.title).",
          projectID: state.tasks[index].projectID, taskID: id))
    case .complete(let id, let complete, let revision):
      let index = try taskIndex(id, revision)
      try ensureIdle(id)
      state.tasks[index].completed = complete
      state.tasks[index].revision += 1
      state.activity.append(
        Activity(
          complete ? "Task marked complete by you." : "Task reopened.",
          projectID: state.tasks[index].projectID, taskID: id))
    case .deleteTask(let id, let revision):
      _ = try taskIndex(id, revision)
      try ensureIdle(id)
      state.tasks.removeAll { $0.id == id }
      state.runs.removeAll { $0.taskID == id }
    case .restoreTask(let id, var desired, let expectedRevision):
      try ensureIdle(id)
      let existing = state.tasks.first(where: { $0.id == id })
      guard existing?.revision == expectedRevision else { throw BoardError.conflict }
      if desired == nil && state.runs.contains(where: { $0.taskID == id }) {
        throw BoardError.invalid("A task with agent history cannot be removed by undo.")
      }
      if var desiredValue = desired {
        guard desiredValue.id == id,
          state.projects.contains(where: { $0.id == desiredValue.projectID })
        else { throw BoardError.missing }
        desiredValue.revision = (existing?.revision ?? desiredValue.revision) + 1
        desiredValue.updatedAt = .now
        desired = desiredValue
      }
      state.tasks.removeAll { $0.id == id }
      if let desired { state.tasks.append(desired) }
      state.activity.append(
        Activity(
          "Undid or redid a manual task change. No automation was started.",
          projectID: desired?.projectID ?? existing?.projectID, taskID: id))
    case .reorder(let id, let before, let revision):
      let source = state.tasks[try taskIndex(id, revision)]
      let target = state.tasks[try taskIndex(before)]
      try ensureIdle(id)
      guard source.projectID == target.projectID, source.stage == target.stage else {
        throw BoardError.invalid("Reorder tasks within the same column.")
      }
      if id == before { return state }
      var ordered = state.items(in: source.projectID, stage: source.stage, completed: true).filter {
        $0.id != id
      }
      let index = ordered.firstIndex { $0.id == before } ?? ordered.endIndex
      ordered.insert(source, at: index)
      for (rank, item) in ordered.enumerated() {
        let i = try taskIndex(item.id)
        if state.tasks[i].rank != rank {
          state.tasks[i].rank = rank
          state.tasks[i].revision += 1
          state.tasks[i].updatedAt = .now
        }
      }
    case .retry(let runID, let configuration):
      guard let index = state.runs.firstIndex(where: { $0.id == runID }) else {
        throw BoardError.missing
      }
      let run = state.runs[index]
      guard run.kind != .task else {
        throw BoardError.invalid("Manual Codex Desktop handoffs must be rerun from the task.")
      }
      guard [.failed, .interrupted, .cancelled].contains(run.status) else {
        throw BoardError.invalid("Only stopped runs can be retried.")
      }
      let taskIndex = try taskIndex(run.taskID)
      var task = state.tasks[taskIndex]
      guard state.projects.contains(where: { $0.id == task.projectID }) else {
        throw BoardError.missing
      }
      if run.kind == .planning, task.planPath == nil {
        task.planPath = WorkItem.canonicalPlanPath(for: task.id)
        task.revision += 1
        task.updatedAt = .now
        state.tasks[taskIndex] = task
      }
      if state.runs[index].modelConfiguration == nil {
        guard let configuration else {
          throw BoardError.invalid(
            "This older run has no saved model choice. Review and confirm a model before retrying.")
        }
        state.runs[index].modelConfiguration = configuration
      }
      state.runs[index].status = .queued
      state.runs[index].error = nil
      state.runs[index].summary = "Retry queued; existing session will be resumed"
      state.runs[index].updatedAt = .now
    case .closeRun(let runID):
      guard let index = state.runs.firstIndex(where: { $0.id == runID }) else {
        throw BoardError.missing
      }
      let run = state.runs[index]
      let message = "Session released from StageChase. Continue in Codex."
      if run.status.isActive {
        state.runs[index].status = .interrupted
        state.runs[index].summary = message
        state.runs[index].error = nil
      }
      state.runs[index].updatedAt = .now
      if !state.activity.contains(where: { $0.runID == runID && $0.message == message }) {
        state.activity.append(
          Activity(message, projectID: run.projectID, taskID: run.taskID, runID: runID))
      }
    case .updateRun(let run):
      guard let index = state.runs.firstIndex(where: { $0.id == run.id }) else {
        throw BoardError.missing
      }
      state.runs[index] = run
    case .finishRun(let runID, let planPath):
      guard let index = state.runs.firstIndex(where: { $0.id == runID }) else {
        throw BoardError.missing
      }
      let run = state.runs[index]
      let taskIndex = try taskIndex(run.taskID)
      guard run.status == .running else {
        throw BoardError.invalid("Only an active run can finish.")
      }
      if run.kind == .planning {
        guard let planPath, !planPath.isEmpty else {
          throw BoardError.invalid("Codex finished without a saved plan.")
        }
        if let reservedPath = state.tasks[taskIndex].planPath {
          guard reservedPath == planPath else {
            throw BoardError.conflict
          }
        } else {
          // Older persisted runs did not reserve their destination when queued.
          state.tasks[taskIndex].planPath = planPath
          state.tasks[taskIndex].revision += 1
          state.tasks[taskIndex].updatedAt = .now
        }
      }
      state.runs[index].status = .succeeded
      state.runs[index].updatedAt = .now
      state.runs[index].summary =
      run.kind == .planning
        ? "Plan saved. Ready for your go-ahead."
        : run.kind == .implementation ? "Implementation finished. Review the changes."
        : "Codex Desktop task finished. Review the changes."
      state.activity.append(
        Activity(
          state.runs[index].summary, projectID: run.projectID, taskID: run.taskID, runID: run.id))
    case .log(let activity): state.activity.append(activity)
    }
    try state.validate()
    return state
  }
}

public enum LegacyImport {
  /// Deliberately decodes only the known prototype fields. It never modifies the original JSON file.
  public static func decode(_ data: Data) throws -> Library {
    struct OldProject: Decodable {
      var id: UUID
      var name: String
      var projectDirectory: String
    }
    struct OldPlan: Decodable { var relativePath: String }
    struct OldTask: Decodable {
      var id: UUID
      var boardID: UUID
      var title: String
      var description: String
      var stage: WorkflowStage
      var position: Int
      var completed: Bool
      var revision: Int
      var plan: OldPlan?
    }
    struct OldLibrary: Decodable {
      var boards: [OldProject]
      var tasks: [OldTask]
    }
    let old = try JSONDecoder().decode(OldLibrary.self, from: data)
    var library = Library()
    library.projects = old.boards.map { value in
      var project = Project(name: value.name, directory: value.projectDirectory)
      project.id = value.id
      return project
    }
    library.tasks = old.tasks.map { value in
      var item = WorkItem(projectID: value.boardID, title: value.title, stage: value.stage)
      item.id = value.id
      item.notes = value.description
      item.rank = value.position
      item.completed = value.completed
      item.revision = value.revision
      item.planPath = value.plan?.relativePath
      return item
    }
    library.activity = [
      Activity(
        "Imported the original board. Original JSON, including historical activity, was preserved. Automation remains off until you enable it."
      )
    ]
    try library.validate()
    return library
  }
}

extension Library {
  public static var preview: Library {
    var library = Library()
    let projects = [
      Project(name: "StageChase"), Project(name: "Sideline Save"), Project(name: "Weekend ideas"),
    ]
    library.projects = projects
    for (title, notes, stage) in [
      (
        "An inbox for the next good idea", "Capture it now. Figure out the details later.",
        WorkflowStage.inbox
      ),
      ("Keyboard-first navigation", "A few thoughtful shortcuts go a long way.", .inbox),
      ("Make progress visible", "Show the plan, the work, and the moments that need you.", .next),
      (
        "A home for every project", "Keep the context. Switch projects without losing your place.",
        .planned
      ),
      (
        "A board that breathes", "Top-aligned lanes, quick capture, and natural drag and drop.",
        .implementation
      ),
      ("Give the details a final look", "Nothing is complete until you say so.", .review),
    ] {
      var item = WorkItem(projectID: projects[0].id, title: title, stage: stage)
      item.notes = notes
      library.tasks.append(item)
    }
    library.tasks.append(
      WorkItem(projectID: projects[1].id, title: "Explore a better highlight workflow"))
    library.activity = [Activity("Preview library — separate from your saved projects.")]
    return library
  }
}
