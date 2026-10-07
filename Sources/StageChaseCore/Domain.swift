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

/// Board placement is independent from the task's current status. `WorkflowStage` remains as the
/// compatibility vocabulary used by older library payloads and MCP clients.
public enum WorkflowSection: String, Codable, CaseIterable, Identifiable, Sendable {
  case inbox, planning, implementing
  public var id: String { rawValue }
  public var title: String { rawValue.capitalized }
  public var symbol: String {
    switch self {
    case .inbox: "tray"
    case .planning: "sparkles"
    case .implementing: "hammer"
    }
  }
  public var subtitle: String {
    switch self {
    case .inbox: "Ideas start here"
    case .planning: "Shape the work"
    case .implementing: "Move work to done"
    }
  }
  public var compatibilityStage: WorkflowStage {
    switch self {
    case .inbox: .inbox
    case .planning: .next
    case .implementing: .implementation
    }
  }
}

public enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
  case triage, planning, ready, building, waiting, error, quota, review, done
  public var id: String { rawValue }
  public var badgeStyle: TaskStatusBadgeStyle {
    switch self {
    case .triage: TaskStatusBadgeStyle(symbol: "tray", color: .secondary)
    case .planning: TaskStatusBadgeStyle(symbol: "sparkles", color: .purple)
    case .ready: TaskStatusBadgeStyle(symbol: "checkmark.circle.fill", color: .green)
    case .building: TaskStatusBadgeStyle(symbol: "hammer.fill", color: .indigo)
    case .waiting: TaskStatusBadgeStyle(symbol: "pause.circle.fill", color: .orange)
    case .error: TaskStatusBadgeStyle(symbol: "exclamationmark.circle.fill", color: .red)
    case .quota: TaskStatusBadgeStyle(symbol: "gauge.with.dots.needle.67percent", color: .orange)
    case .review: TaskStatusBadgeStyle(symbol: "eye.circle.fill", color: .green)
    case .done: TaskStatusBadgeStyle(symbol: "checkmark.seal.fill", color: .blue)
    }
  }
  public var title: String {
    switch self {
    case .triage: "Triage"
    case .planning: "Planning"
    case .ready: "Ready"
    case .building: "Building"
    case .waiting: "Waiting"
    case .error: "Error"
    case .quota: "Quota"
    case .review: "Review"
    case .done: "Done"
    }
  }
  public var isAttentionState: Bool { [.waiting, .error, .quota, .review].contains(self) }
  public var attentionOrder: Int {
    switch self {
    case .waiting: 0
    case .error: 1
    case .quota: 2
    case .review: 3
    default: 4
    }
  }
  public static func legacyStatus(for stage: WorkflowStage) -> Self {
    switch stage {
    case .inbox: .triage
    case .next: .planning
    case .planned: .ready
    case .implementation: .ready
    case .review: .review
    }
  }
  public var section: WorkflowSection {
    switch self {
    case .triage: .inbox
    case .planning: .planning
    case .ready, .building, .waiting, .error, .quota, .review, .done: .implementing
    }
  }
}

public enum TaskStatusBadgeColor: String, Codable, CaseIterable, Sendable {
  case secondary, purple, blue, indigo, orange, red, green
}

public struct TaskStatusBadgeStyle: Hashable, Sendable {
  public var symbol: String
  public var color: TaskStatusBadgeColor

  public init(symbol: String, color: TaskStatusBadgeColor) {
    self.symbol = symbol
    self.color = color
  }
}

public enum TaskPriority: Int, Codable, CaseIterable, Identifiable, Sendable {
  case high = 1
  case medium = 2
  case low = 3
  public var id: Int { rawValue }
  public var title: String {
    switch self {
    case .high: "High"
    case .medium: "Medium"
    case .low: "Low"
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

/// Permission posture for Codex runs started by the Mac runner.
/// Missing values in older project payloads decode to the restricted default.
public enum CodexExecutionProfile: String, Codable, CaseIterable, Identifiable, Sendable {
  case workspaceAccessNoPrompts
  case fullAccessNoPrompts

  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .workspaceAccessNoPrompts: "Workspace access, no prompts"
    case .fullAccessNoPrompts: "Full access, no prompts"
    }
  }
  public var sandbox: String {
    switch self {
    case .workspaceAccessNoPrompts: "workspace-write"
    case .fullAccessNoPrompts: "danger-full-access"
    }
  }
  public func sandboxPolicy(writableRoot: String) -> [String: Any] {
    switch self {
    case .workspaceAccessNoPrompts:
      ["type": "workspaceWrite", "writableRoots": [writableRoot], "networkAccess": false]
    case .fullAccessNoPrompts:
      ["type": "dangerFullAccess"]
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
  public var usesWorktrees = false
  public var modelOverride: CodexModelConfiguration?
  public var executionProfile: CodexExecutionProfile = .workspaceAccessNoPrompts
  /// Legacy inert metadata retained for library and replica compatibility.
  public var deployedCommitHash: String?
  public var deployedAt: Date?
  public var favoriteMakeTargets: [String] = []
  public var createdAt = Date()
  /// Soft deletion retains this project and all of its related records and files.
  public var deletedAt: Date?
  public var deletionRevision = 0
  public var isDeleted: Bool { deletedAt != nil }

  private enum CodingKeys: String, CodingKey {
    case id, name, directory, automationEnabled, usesWorktrees, modelOverride, executionProfile
    case deployedCommitHash, deployedAt, favoriteMakeTargets, createdAt, deletedAt, deletionRevision
  }

  public init(name: String, directory: String = "") {
    self.name = name
    self.directory = directory
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try values.decode(String.self, forKey: .name)
    directory = try values.decodeIfPresent(String.self, forKey: .directory) ?? ""
    automationEnabled = try values.decodeIfPresent(Bool.self, forKey: .automationEnabled) ?? false
    usesWorktrees = try values.decodeIfPresent(Bool.self, forKey: .usesWorktrees) ?? false
    modelOverride = try values.decodeIfPresent(CodexModelConfiguration.self, forKey: .modelOverride)
    executionProfile =
      try values.decodeIfPresent(CodexExecutionProfile.self, forKey: .executionProfile)
      ?? .workspaceAccessNoPrompts
    deployedCommitHash = try values.decodeIfPresent(String.self, forKey: .deployedCommitHash)
    deployedAt = try values.decodeIfPresent(Date.self, forKey: .deployedAt)
    favoriteMakeTargets =
      try values.decodeIfPresent([String].self, forKey: .favoriteMakeTargets) ?? []
    createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
    deletionRevision = try values.decodeIfPresent(Int.self, forKey: .deletionRevision) ?? 0
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(name, forKey: .name)
    try values.encode(directory, forKey: .directory)
    try values.encode(automationEnabled, forKey: .automationEnabled)
    try values.encode(usesWorktrees, forKey: .usesWorktrees)
    try values.encodeIfPresent(modelOverride, forKey: .modelOverride)
    try values.encode(executionProfile, forKey: .executionProfile)
    try values.encodeIfPresent(deployedCommitHash, forKey: .deployedCommitHash)
    try values.encodeIfPresent(deployedAt, forKey: .deployedAt)
    try values.encode(favoriteMakeTargets, forKey: .favoriteMakeTargets)
    try values.encode(createdAt, forKey: .createdAt)
    try values.encodeIfPresent(deletedAt, forKey: .deletedAt)
    try values.encode(deletionRevision, forKey: .deletionRevision)
  }
}

public struct WorkItem: Codable, Hashable, Identifiable, Sendable {
  public var id = UUID()
  /// Library-wide human-facing ID. Nil only for phone tasks awaiting Mac acceptance.
  public var shortID: Int?
  public var projectID: UUID
  public var title: String
  public var notes = ""
  public var stage: WorkflowStage = .inbox
  public var section: WorkflowSection = .inbox
  public var status: TaskStatus = .triage
  public var rank = 0
  public var completed = false
  public var priority: TaskPriority?
  public var revision = 0
  public var planPath: String?
  public var latestCodexUpdate: String?
  public var latestCodexUpdateAt: Date?
  public var modelOverride: CodexModelConfiguration?
  public var createdAt = Date()
  public var updatedAt = Date()
  public var completedAt: Date?
  public var attachments: [TaskAttachment] = []
  public init(projectID: UUID, title: String, stage: WorkflowStage = .inbox) {
    self.projectID = projectID
    self.title = title
    self.stage = stage
    section = Self.legacySection(for: stage)
    status = TaskStatus.legacyStatus(for: stage)
  }

  private enum CodingKeys: String, CodingKey {
    case id, shortID, projectID, title, notes, stage, section, status, rank, completed, priority,
      revision
    case planPath, latestCodexUpdate, latestCodexUpdateAt, modelOverride, createdAt, updatedAt
    case completedAt, attachments
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    shortID = try values.decodeIfPresent(Int.self, forKey: .shortID)
    projectID = try values.decode(UUID.self, forKey: .projectID)
    title = try values.decode(String.self, forKey: .title)
    notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
    stage = try values.decodeIfPresent(WorkflowStage.self, forKey: .stage) ?? .inbox
    completed = try values.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    section =
      try values.decodeIfPresent(WorkflowSection.self, forKey: .section)
      ?? (completed ? .implementing : Self.legacySection(for: stage))
    status =
      try values.decodeIfPresent(TaskStatus.self, forKey: .status)
      ?? (completed ? .done : TaskStatus.legacyStatus(for: stage))
    rank = try values.decodeIfPresent(Int.self, forKey: .rank) ?? 0
    priority = try values.decodeIfPresent(TaskPriority.self, forKey: .priority)
    revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    planPath = try values.decodeIfPresent(String.self, forKey: .planPath)
    latestCodexUpdate = try values.decodeIfPresent(String.self, forKey: .latestCodexUpdate)
    latestCodexUpdateAt = try values.decodeIfPresent(Date.self, forKey: .latestCodexUpdateAt)
    modelOverride = try values.decodeIfPresent(CodexModelConfiguration.self, forKey: .modelOverride)
    createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
    attachments = try values.decodeIfPresent([TaskAttachment].self, forKey: .attachments) ?? []
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encodeIfPresent(shortID, forKey: .shortID)
    try values.encode(projectID, forKey: .projectID)
    try values.encode(title, forKey: .title)
    try values.encode(notes, forKey: .notes)
    try values.encode(stage, forKey: .stage)
    try values.encode(section, forKey: .section)
    try values.encode(status, forKey: .status)
    try values.encode(rank, forKey: .rank)
    try values.encode(completed, forKey: .completed)
    try values.encodeIfPresent(priority, forKey: .priority)
    try values.encode(revision, forKey: .revision)
    try values.encodeIfPresent(planPath, forKey: .planPath)
    try values.encodeIfPresent(latestCodexUpdate, forKey: .latestCodexUpdate)
    try values.encodeIfPresent(latestCodexUpdateAt, forKey: .latestCodexUpdateAt)
    try values.encodeIfPresent(modelOverride, forKey: .modelOverride)
    try values.encode(createdAt, forKey: .createdAt)
    try values.encode(updatedAt, forKey: .updatedAt)
    try values.encodeIfPresent(completedAt, forKey: .completedAt)
    try values.encode(attachments, forKey: .attachments)
  }

  static func legacySection(for stage: WorkflowStage) -> WorkflowSection {
    switch stage {
    case .inbox: .inbox
    case .next, .planned: .planning
    case .implementation, .review: .implementing
    }
  }

  public static func canonicalPlanPath(for id: UUID, title: String) -> String {
    let foldedTitle =
      title
      .folding(
        options: [.diacriticInsensitive, .widthInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .lowercased()
    var slug = ""
    var previousWasSeparator = false
    for character in foldedTitle {
      if character.isLetter || character.isNumber {
        slug.append(character)
        previousWasSeparator = false
      } else if !previousWasSeparator, !slug.isEmpty {
        slug.append("-")
        previousWasSeparator = true
      }
      if slug.count >= 64 { break }
    }
    while slug.last == "-" { slug.removeLast() }
    if slug.isEmpty { slug = "task" }
    return "to-do/\(slug)-\(id.uuidString.lowercased()).md"
  }
}

public enum RunStatus: String, Codable, CaseIterable, Sendable {
  case queued, readyForHandoff, running, needsInput, succeeded, failed, interrupted, cancelled,
    stale, superseded
  public var title: String {
    switch self {
    case .needsInput: "Needs your input"
    case .readyForHandoff: "Ready for Codex Desktop"
    case .succeeded: "Finished"
    default: rawValue.capitalized
    }
  }
  public var isActive: Bool { [.queued, .running, .needsInput].contains(self) }
}

public enum RunKind: String, Codable, Sendable { case planning, implementation, task }
public enum RunSource: String, Codable, Sendable { case stageChase, codexDesktop }
public enum LiveTurnState: String, Codable, Sendable { case unknown, busy, waiting, idle, stale }

public struct AgentRun: Codable, Hashable, Identifiable, Sendable {
  public var id = UUID()
  public var taskID: UUID
  public var projectID: UUID
  public var kind: RunKind
  public var source: RunSource?
  public var status: RunStatus = .queued
  public var threadID: String?
  public var turnID: String?
  /// Live state is set only after resuming the exact thread; nil on older records means unknown.
  public var liveState: LiveTurnState?
  public var workDirectory: String?
  public var usesWorktrees: Bool?
  public var summary = "Waiting for the Mac runner"
  public var latestMessage: String?
  public var error: String?
  public var steps: [ProgressStep] = []
  public var modelConfiguration: ResolvedCodexConfiguration?
  /// Snapshot of the project's permission profile when this run was queued.
  /// Optional for decoding older runs; retries resolve the project's safe/current profile once.
  public var executionProfile: CodexExecutionProfile?
  public var handoffContext: String?
  public var createdAt = Date()
  public var updatedAt = Date()
  public init(
    task: WorkItem, kind: RunKind, modelConfiguration: ResolvedCodexConfiguration? = nil,
    usesWorktrees: Bool? = nil, executionProfile: CodexExecutionProfile? = nil
  ) {
    taskID = task.id
    projectID = task.projectID
    self.kind = kind
    self.modelConfiguration = modelConfiguration
    self.usesWorktrees = usesWorktrees
    self.executionProfile = executionProfile
  }
}

/// Transient task inspector state; never persisted or included in sync snapshots.
public struct TaskRunDisclosureState: Equatable, Sendable {
  public private(set) var taskID: UUID?
  public private(set) var latestID: UUID?
  public private(set) var expandedIDs: Set<UUID> = []
  public init() {}

  public static func ordered(_ runs: [AgentRun]) -> [AgentRun] {
    runs.sorted {
      $0.createdAt == $1.createdAt
        ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
    }
  }

  public mutating func select(taskID: UUID, runs: [AgentRun]) {
    let ordered = Self.ordered(runs.filter { $0.taskID == taskID })
    let next = ordered.first?.id
    if self.taskID != taskID {
      expandedIDs = Set(next.map { [$0] } ?? [])
    } else if next != latestID {
      if let latestID { expandedIDs.remove(latestID) }
      if let next { expandedIDs.insert(next) }
    }
    expandedIDs.formIntersection(Set(ordered.map(\.id)))
    self.taskID = taskID
    latestID = next
  }

  public mutating func setExpanded(_ expanded: Bool, for runID: UUID) {
    if expanded { expandedIDs.insert(runID) } else { expandedIDs.remove(runID) }
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

public enum TaskChangeKind: String, Codable, Hashable, Sendable {
  case stageChanged
  case completionChanged

  public var badgeTitle: String {
    switch self {
    case .stageChanged: "Column changed"
    case .completionChanged: "Status changed"
    }
  }
}

public struct Activity: Codable, Hashable, Identifiable, Sendable {
  public var id = UUID()
  public var projectID: UUID?
  public var taskID: UUID?
  public var runID: UUID?
  public var message: String
  public var date = Date()
  public var taskChange: TaskChangeKind?
  public init(
    _ message: String, projectID: UUID? = nil, taskID: UUID? = nil, runID: UUID? = nil,
    taskChange: TaskChangeKind? = nil
  ) {
    self.message = message
    self.projectID = projectID
    self.taskID = taskID
    self.runID = runID
    self.taskChange = taskChange
  }
}

public struct Library: Codable, Equatable, Sendable {
  public var formatVersion = 1
  public var projects: [Project] = []
  public var tasks: [WorkItem] = []
  /// Highest number ever issued, retained after deletion so IDs are never reused.
  public var taskShortIDHighWaterMark = 0
  public var runs: [AgentRun] = []
  public var activity: [Activity] = []
  public init() {}
  private enum CodingKeys: String, CodingKey {
    case formatVersion, projects, tasks, taskShortIDHighWaterMark, runs, activity
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
    projects = try values.decodeIfPresent([Project].self, forKey: .projects) ?? []
    tasks = try values.decodeIfPresent([WorkItem].self, forKey: .tasks) ?? []
    taskShortIDHighWaterMark =
      try values.decodeIfPresent(Int.self, forKey: .taskShortIDHighWaterMark) ?? 0
    runs = try values.decodeIfPresent([AgentRun].self, forKey: .runs) ?? []
    activity = try values.decodeIfPresent([Activity].self, forKey: .activity) ?? []
    reconcileTaskShortIDs()
  }
  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(formatVersion, forKey: .formatVersion)
    try values.encode(projects, forKey: .projects)
    try values.encode(tasks, forKey: .tasks)
    try values.encode(taskShortIDHighWaterMark, forKey: .taskShortIDHighWaterMark)
    try values.encode(runs, forKey: .runs)
    try values.encode(activity, forKey: .activity)
  }
  /// Deterministically repairs missing, invalid, or duplicate numbers after import or legacy load.
  public mutating func reconcileTaskShortIDs() {
    let order = tasks.indices.sorted {
      tasks[$0].createdAt == tasks[$1].createdAt
        ? tasks[$0].id.uuidString < tasks[$1].id.uuidString
        : tasks[$0].createdAt < tasks[$1].createdAt
    }
    var seen = Set<Int>()
    for index in order {
      guard let value = tasks[index].shortID, value > 0, seen.insert(value).inserted else {
        tasks[index].shortID = nil
        continue
      }
    }
    taskShortIDHighWaterMark = max(taskShortIDHighWaterMark, seen.max() ?? 0)
    for index in order where tasks[index].shortID == nil {
      guard taskShortIDHighWaterMark < Int.max else { break }
      taskShortIDHighWaterMark += 1
      tasks[index].shortID = taskShortIDHighWaterMark
    }
  }
  /// Assigns the next Mac-authoritative number to a newly accepted task.
  public mutating func assignNextTaskShortID(to taskID: UUID) throws {
    guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { throw BoardError.missing }
    guard taskShortIDHighWaterMark < Int.max else {
      throw BoardError.invalid("No more task IDs can be assigned in this library.")
    }
    taskShortIDHighWaterMark += 1
    tasks[index].shortID = taskShortIDHighWaterMark
  }
  public func items(in project: UUID, stage: WorkflowStage? = nil, completed: Bool = false)
    -> [WorkItem]
  {
    tasks.filter {
      $0.projectID == project && (stage == nil || $0.stage == stage) && (completed || !$0.completed)
    }
    .sorted {
      let leftPriority = $0.priority?.rawValue ?? Int.max
      let rightPriority = $1.priority?.rawValue ?? Int.max
      if leftPriority != rightPriority { return leftPriority < rightPriority }
      return $0.rank == $1.rank ? $0.createdAt < $1.createdAt : $0.rank < $1.rank
    }
  }
  public func items(in project: UUID, section: WorkflowSection, completed: Bool = false)
    -> [WorkItem]
  {
    tasks.filter {
      $0.projectID == project && $0.section == section && (completed || !$0.completed)
    }
    .sorted {
      if section == .planning || section == .implementing {
        if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
        return $0.id.uuidString < $1.id.uuidString
      }
      if $0.status.attentionOrder != $1.status.attentionOrder {
        return $0.status.attentionOrder < $1.status.attentionOrder
      }
      let leftPriority = $0.priority?.rawValue ?? Int.max
      let rightPriority = $1.priority?.rawValue ?? Int.max
      if leftPriority != rightPriority { return leftPriority < rightPriority }
      return $0.rank == $1.rank ? $0.createdAt < $1.createdAt : $0.rank < $1.rank
    }
  }
  public var activeProjects: [Project] { projects.filter { !$0.isDeleted } }
  public var deletedProjects: [Project] { projects.filter(\.isDeleted) }

  /// All tasks in active projects, ordered by most recent update first.
  /// Equal timestamps use the task ID so the sidebar order stays stable.
  public var recentTasks: [WorkItem] {
    let projectIDs = Set(activeProjects.map(\.id))
    return tasks.filter { projectIDs.contains($0.projectID) }.sorted {
      if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
      return $0.id.uuidString < $1.id.uuidString
    }
  }
  public func latestRun(for task: UUID) -> AgentRun? {
    runs.filter { $0.taskID == task }.max { $0.createdAt < $1.createdAt }
  }
  public func latestCompletedTask(in project: UUID) -> WorkItem? {
    tasks.filter { $0.projectID == project && $0.completed }.max {
      let leftDate = $0.completedAt ?? $0.updatedAt
      let rightDate = $1.completedAt ?? $1.updatedAt
      if leftDate != rightDate { return leftDate < rightDate }
      return $0.id.uuidString < $1.id.uuidString
    }
  }
  public func validate() throws {
    guard projects.allSatisfy({ $0.deletionRevision >= 0 }) else {
      throw BoardError.invalid("Project deletion revisions must be nonnegative.")
    }
    guard formatVersion == 1 else {
      throw BoardError.invalid("This library needs a newer StageChase version.")
    }
    guard Set(projects.map(\.id)).count == projects.count,
      Set(tasks.map(\.id)).count == tasks.count,
      Set(runs.map(\.id)).count == runs.count
    else { throw BoardError.invalid("Duplicate identities in the library.") }
    let shortIDs = tasks.compactMap(\.shortID)
    guard taskShortIDHighWaterMark >= 0,
      tasks.allSatisfy({ $0.shortID.map { $0 > 0 } ?? true }),
      Set(shortIDs).count == shortIDs.count,
      (shortIDs.max() ?? 0) <= taskShortIDHighWaterMark
    else {
      throw BoardError.invalid(
        "Task IDs must be positive, unique, and within the library sequence.")
    }
    let projectIDs = Set(projects.map(\.id))
    let taskIDs = Set(tasks.map(\.id))
    let attachments = tasks.flatMap(\.attachments)
    guard tasks.allSatisfy({ projectIDs.contains($0.projectID) }),
      runs.allSatisfy({ projectIDs.contains($0.projectID) && taskIDs.contains($0.taskID) }),
      tasks.allSatisfy({ $0.attachments.count <= TaskAttachmentFiles.maximumCount }),
      Set(attachments.map(\.id)).count == attachments.count,
      attachments.allSatisfy({
        !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && TaskAttachmentFiles.allowedTypes.contains($0.mediaType)
          && $0.byteCount > 0 && $0.byteCount <= TaskAttachmentFiles.maximumBytes
          && $0.sha256.count == 64 && $0.sha256.allSatisfy(\.isHexDigit)
      })
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
    case .busy: "Wait for the active Codex run to finish before editing or deleting this task."
    case .invalid(let message): message
    }
  }
}

public enum Mutation: Sendable {
  case createProject(Project)
  case editProject(Project)
  case setProjectDeleted(UUID, Bool, expectedRevision: Int)
  case createTask(WorkItem, configuration: ResolvedCodexConfiguration? = nil)
  case runTaskNow(
    UUID, expectedRevision: Int, kind: RunKind, configuration: ResolvedCodexConfiguration)
  case createManualRun(AgentRun)
  case beginExternalRun(AgentRun)
  case editTask(WorkItem, expectedRevision: Int)
  case setTaskAttachments(UUID, [TaskAttachment], expectedRevision: Int)
  case saveNotes(UUID, String, expectedRevision: Int)
  case move(
    UUID, WorkflowStage, expectedRevision: Int, configuration: ResolvedCodexConfiguration? = nil)
  case complete(UUID, Bool, expectedRevision: Int)
  case reportTaskUpdate(UUID, String, expectedRevision: Int)
  case reportExternalRun(UUID, String, RunStatus, expectedTaskRevision: Int)
  case deleteTask(UUID, expectedRevision: Int)
  case restoreTask(UUID, WorkItem?, expectedRevision: Int?)
  case reorder(UUID, before: UUID, expectedRevision: Int)
  case retry(UUID, configuration: ResolvedCodexConfiguration? = nil)
  /// Revision-rebased edit from a paired device; preserves the existing run snapshot.
  case syncEditTask(WorkItem, expectedRevision: Int)
  case closeRun(UUID)
  case updateRun(AgentRun)
  case finishRun(UUID, planPath: String?)
  case log(Activity)
}

public enum BoardReducer {
  /// A confirmed user command is the only way to enqueue work. Reading state never triggers Codex.
  public static func apply(_ command: Mutation, to original: Library) throws -> Library {
    var state = original
    func ensureActiveProject(_ id: UUID) throws {
      guard let project = state.projects.first(where: { $0.id == id }) else {
        throw BoardError.missing
      }
      guard !project.isDeleted else {
        throw BoardError.invalid("Restore this project from Deleted Projects before changing it.")
      }
    }
    func taskIndex(_ id: UUID, _ revision: Int? = nil) throws -> Int {
      guard let index = state.tasks.firstIndex(where: { $0.id == id }) else {
        throw BoardError.missing
      }
      try ensureActiveProject(state.tasks[index].projectID)
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
      guard project.automationEnabled, [.planning, .implementing].contains(item.section),
        let configuration,
        !state.runs.contains(where: { $0.taskID == item.id && $0.status.isActive })
      else {
        return
      }
      guard !project.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw BoardError.invalid("Choose a project folder before enabling Codex.")
      }
      if item.section == .planning, item.planPath == nil {
        item.planPath = WorkItem.canonicalPlanPath(for: item.id, title: item.title)
      }
      let run = AgentRun(
        task: item, kind: item.section == .planning ? .planning : .implementation,
        modelConfiguration: configuration, usesWorktrees: project.usesWorktrees,
        executionProfile: project.executionProfile)
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
    case .setProjectDeleted(let id, let deleted, let revision):
      guard let index = state.projects.firstIndex(where: { $0.id == id }) else {
        throw BoardError.missing
      }
      guard state.projects[index].deletionRevision == revision else { throw BoardError.conflict }
      guard state.projects[index].isDeleted != deleted else { break }
      guard revision < Int.max else { throw BoardError.invalid("Project revision limit reached.") }
      guard !deleted || !state.runs.contains(where: { $0.projectID == id && $0.status.isActive })
      else {
        throw BoardError.invalid(
          "Wait for this project's active runs to finish before deleting it.")
      }
      state.projects[index].deletedAt = deleted ? .now : nil
      state.projects[index].deletionRevision += 1
      state.activity.append(
        Activity(
          "\(deleted ? "Deleted" : "Restored") project “\(state.projects[index].name)”.",
          projectID: id))
    case .editProject(var project):
      try ensureActiveProject(project.id)
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
      // A stale settings draft cannot restore a deleted project or rewind its lifecycle.
      project.deletedAt = state.projects[index].deletedAt
      project.deletionRevision = state.projects[index].deletionRevision
      state.projects[index] = project
    case .createTask(var item, let configuration):
      try ensureActiveProject(item.projectID)
      item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !item.title.isEmpty else { throw BoardError.invalid("Give this task a title.") }
      guard state.projects.contains(where: { $0.id == item.projectID }),
        !state.tasks.contains(where: { $0.id == item.id })
      else { throw BoardError.missing }
      item.rank =
        (state.tasks.filter { $0.projectID == item.projectID && $0.section == item.section }.map(
          \.rank
        )
        .max() ?? -1) + 1
      try enqueue(&item, configuration: configuration)
      state.tasks.append(item)
      state.activity.append(
        Activity(
          "Added “\(item.title)” to \(item.stage.title).", projectID: item.projectID,
          taskID: item.id))
    case .runTaskNow(let id, let revision, let kind, let configuration):
      let index = try taskIndex(id, revision)
      try ensureIdle(id)
      var item = state.tasks[index]
      guard !item.completed else {
        throw BoardError.invalid("Reopen this task before starting a Codex run.")
      }
      guard let project = state.projects.first(where: { $0.id == item.projectID }) else {
        throw BoardError.missing
      }
      guard
        kind == .planning
          || (kind == .implementation && [.planning, .implementing].contains(item.section))
      else {
        throw BoardError.invalid(
          "Implementation runs require the task to be in Planning or Implementing.")
      }
      guard !project.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw BoardError.invalid("Choose a project folder before starting a Codex run.")
      }
      if kind == .planning, item.planPath == nil {
        item.planPath = WorkItem.canonicalPlanPath(for: item.id, title: item.title)
        item.revision += 1
        item.updatedAt = .now
      }
      let run = AgentRun(
        task: item, kind: kind,
        modelConfiguration: configuration, usesWorktrees: project.usesWorktrees,
        executionProfile: project.executionProfile)
      state.tasks[index] = item
      state.runs.append(run)
      state.activity.append(
        Activity(
          "Codex run queued from task details · \(configuration.summary)",
          projectID: item.projectID, taskID: item.id, runID: run.id))
    case .createManualRun(let run):
      try ensureActiveProject(run.projectID)
      guard run.kind == .task, run.status == .readyForHandoff,
        state.tasks.contains(where: { $0.id == run.taskID && $0.projectID == run.projectID }),
        !state.runs.contains(where: { $0.id == run.id })
      else { throw BoardError.invalid("The Codex Desktop handoff is invalid.") }
      state.runs.append(run)
      state.activity.append(
        Activity(
          "Prepared a Codex Desktop handoff.", projectID: run.projectID, taskID: run.taskID,
          runID: run.id))
    case .beginExternalRun(let run):
      try ensureActiveProject(run.projectID)
      guard run.source == .codexDesktop, run.status == .running,
        state.tasks.contains(where: { $0.id == run.taskID && $0.projectID == run.projectID }),
        !state.runs.contains(where: { $0.id == run.id })
      else { throw BoardError.invalid("The external Codex Desktop tracking record is invalid.") }
      let activeRuns = state.runs.indices.filter {
        state.runs[$0].taskID == run.taskID && state.runs[$0].status.isActive
      }
      guard activeRuns.allSatisfy({ state.runs[$0].source != .codexDesktop }) else {
        throw BoardError.invalid("This task already has an active Codex Desktop session.")
      }
      for index in activeRuns {
        state.runs[index].status = .superseded
        state.runs[index].summary = "Tracking replaced by a newer Codex Desktop execution."
        state.runs[index].updatedAt = .now
        state.activity.append(
          Activity(
            "Tracking superseded by a new Codex Desktop execution.", projectID: run.projectID,
            taskID: run.taskID, runID: state.runs[index].id))
      }
      state.runs.append(run)
      state.activity.append(
        Activity(
          "Work tracked in Codex Desktop.", projectID: run.projectID, taskID: run.taskID,
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
    case .syncEditTask(var item, let expectedRevision):
      let index = try taskIndex(item.id, expectedRevision)
      guard item.projectID == state.tasks[index].projectID, item.stage == state.tasks[index].stage
      else { throw BoardError.invalid("Use Move to change a task’s stage.") }
      item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !item.title.isEmpty else { throw BoardError.invalid("Give this task a title.") }
      item.revision += 1
      item.updatedAt = .now
      state.tasks[index] = item
    case .setTaskAttachments(let id, let attachments, let expectedRevision):
      let index = try taskIndex(id, expectedRevision)
      guard attachments.count <= TaskAttachmentFiles.maximumCount,
        Set(attachments.map(\.id)).count == attachments.count,
        attachments.allSatisfy({
          TaskAttachmentFiles.allowedTypes.contains($0.mediaType) && $0.byteCount > 0
            && $0.byteCount <= TaskAttachmentFiles.maximumBytes
        })
      else { throw BoardError.invalid("The task attachment list is invalid or too large.") }
      state.tasks[index].attachments = attachments
      state.tasks[index].revision += 1
      state.tasks[index].updatedAt = .now
    case .saveNotes(let id, let notes, let expectedRevision):
      let index = try taskIndex(id, expectedRevision)
      try ensureIdle(id)
      state.tasks[index].notes = notes
      state.tasks[index].revision += 1
      state.tasks[index].updatedAt = .now
    case .move(let id, let stage, let revision, let configuration):
      let index = try taskIndex(id, revision)
      var item = state.tasks[index]
      if item.stage == stage {
        let old = item
        try enqueue(&item, configuration: configuration)
        if item != old {
          item.revision += 1
          item.updatedAt = .now
          state.tasks[index] = item
        }
        return state
      }
      item.stage = stage
      item.section = WorkItem.legacySection(for: stage)
      if !item.completed { item.status = TaskStatus.legacyStatus(for: stage) }
      item.rank =
        (state.tasks.filter { $0.projectID == item.projectID && $0.section == item.section }
          .map(\.rank).max() ?? -1) + 1
      item.revision += 1
      item.updatedAt = .now
      try enqueue(&item, configuration: configuration)
      state.tasks[index] = item
      state.activity.append(
        Activity(
          "Moved “\(state.tasks[index].title)” to \(stage.title).",
          projectID: state.tasks[index].projectID, taskID: id, taskChange: .stageChanged))
    case .complete(let id, let complete, let revision):
      let index = try taskIndex(id, revision)
      let wasCompleted = state.tasks[index].completed
      state.tasks[index].completed = complete
      if complete {
        if !wasCompleted { state.tasks[index].completedAt = .now }
        state.tasks[index].status = .done
        state.tasks[index].section = .implementing
        state.tasks[index].stage = .review
      } else {
        state.tasks[index].completedAt = nil
        if state.tasks[index].status == .done { state.tasks[index].status = .review }
      }
      state.tasks[index].revision += 1
      state.tasks[index].updatedAt = .now
      state.activity.append(
        Activity(
          complete ? "Task marked complete by you." : "Task reopened.",
          projectID: state.tasks[index].projectID, taskID: id, taskChange: .completionChanged))
    case .reportTaskUpdate(let id, let message, let revision):
      let index = try taskIndex(id, revision)
      let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, trimmed.count <= 2_000 else {
        throw BoardError.invalid("The latest Codex update must contain 1 to 2,000 characters.")
      }
      state.tasks[index].latestCodexUpdate = trimmed
      state.tasks[index].latestCodexUpdateAt = .now
      state.tasks[index].revision += 1
      state.tasks[index].updatedAt = .now
      state.activity.append(
        Activity(
          "Codex update · \(trimmed)", projectID: state.tasks[index].projectID,
          taskID: id))
    case .reportExternalRun(let runID, let message, let status, let taskRevision):
      guard let runIndex = state.runs.firstIndex(where: { $0.id == runID }),
        state.runs[runIndex].source == .codexDesktop
      else { throw BoardError.missing }
      guard [.running, .needsInput].contains(state.runs[runIndex].status) else {
        throw BoardError.invalid(
          "This external Codex session is no longer active. Begin a new tracking record.")
      }
      guard [.running, .needsInput, .succeeded, .failed, .interrupted, .cancelled].contains(status)
      else { throw BoardError.invalid("That status is not valid for an external Codex session.") }
      let run = state.runs[runIndex]
      let index = try taskIndex(run.taskID, taskRevision)
      let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, trimmed.count <= 2_000 else {
        throw BoardError.invalid("The latest Codex update must contain 1 to 2,000 characters.")
      }
      state.tasks[index].latestCodexUpdate = trimmed
      state.tasks[index].latestCodexUpdateAt = .now
      state.tasks[index].revision += 1
      state.tasks[index].updatedAt = .now
      state.runs[runIndex].status = status
      if status == .needsInput {
        state.runs[runIndex].liveState = .waiting
      } else if [.succeeded, .failed, .interrupted, .cancelled].contains(status) {
        state.runs[runIndex].liveState = .idle
      }
      if !state.tasks[index].completed {
        state.tasks[index].status = Self.taskStatus(for: status, message: trimmed)
      }
      state.runs[runIndex].summary = trimmed
      state.runs[runIndex].latestMessage = trimmed
      state.runs[runIndex].updatedAt = .now
      state.activity.append(
        Activity(
          "Codex Desktop · \(trimmed)", projectID: run.projectID, taskID: run.taskID, runID: runID))
    case .deleteTask(let id, let revision):
      _ = try taskIndex(id, revision)
      try ensureIdle(id)
      state.tasks.removeAll { $0.id == id }
      state.runs.removeAll { $0.taskID == id }
    case .restoreTask(let id, var desired, let expectedRevision):
      try ensureIdle(id)
      let existing = state.tasks.first(where: { $0.id == id })
      guard existing?.revision == expectedRevision else { throw BoardError.conflict }
      if let existing { try ensureActiveProject(existing.projectID) }
      if desired == nil && state.runs.contains(where: { $0.taskID == id }) {
        throw BoardError.invalid("A task with agent history cannot be removed by undo.")
      }
      if var desiredValue = desired {
        try ensureActiveProject(desiredValue.projectID)
        guard desiredValue.id == id,
          state.projects.contains(where: { $0.id == desiredValue.projectID })
        else { throw BoardError.missing }
        desiredValue.revision = (existing?.revision ?? desiredValue.revision) + 1
        desiredValue.updatedAt = .now
        desired = desiredValue
      }
      state.tasks.removeAll { $0.id == id }
      if let desired { state.tasks.append(desired) }
      let taskChange: TaskChangeKind?
      if let existing, let desired {
        if existing.stage != desired.stage {
          taskChange = .stageChanged
        } else if existing.completed != desired.completed {
          taskChange = .completionChanged
        } else {
          taskChange = nil
        }
      } else {
        taskChange = nil
      }
      state.activity.append(
        Activity(
          "Undid or redid a manual task change. No automation was started.",
          projectID: desired?.projectID ?? existing?.projectID, taskID: id,
          taskChange: taskChange))
    case .reorder(let id, let before, let revision):
      let sourceIndex = try taskIndex(id, revision)
      var source = state.tasks[sourceIndex]
      let target = state.tasks[try taskIndex(before)]
      guard source.projectID == target.projectID, source.section == target.section
      else {
        throw BoardError.invalid("Reorder tasks within the same project section.")
      }
      if id == before { return state }
      source.priority = target.priority
      var ordered = state.items(in: source.projectID, section: source.section, completed: true)
        .filter { $0.priority == target.priority && $0.id != id }
      let index = ordered.firstIndex { $0.id == before } ?? ordered.endIndex
      ordered.insert(source, at: index)
      for (rank, item) in ordered.enumerated() {
        let i = try taskIndex(item.id)
        if state.tasks[i].rank != rank || state.tasks[i].priority != target.priority {
          state.tasks[i].rank = rank
          state.tasks[i].priority = target.priority
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
      guard let project = state.projects.first(where: { $0.id == task.projectID }) else {
        throw BoardError.missing
      }
      // Old run records acquire a safe profile exactly once, then keep that snapshot on retries.
      state.runs[index].executionProfile = run.executionProfile ?? project.executionProfile
      if run.kind == .planning, task.planPath == nil {
        task.planPath = WorkItem.canonicalPlanPath(for: task.id, title: task.title)
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
      if run.status.isActive { try ensureActiveProject(run.projectID) }
      guard let index = state.runs.firstIndex(where: { $0.id == run.id }) else {
        throw BoardError.missing
      }
      guard state.runs[index].status != .superseded else { break }
      state.runs[index] = run
      if let taskIndex = state.tasks.firstIndex(where: { $0.id == run.taskID }) {
        let task = state.tasks[taskIndex]
        let status =
          run.status == .succeeded && run.kind == .planning
          ? TaskStatus.ready : Self.taskStatus(for: run.status, message: run.error ?? run.summary)
        if !task.completed && task.status != status {
          state.tasks[taskIndex].status = status
          state.tasks[taskIndex].updatedAt = .now
          state.tasks[taskIndex].revision += 1
        }
      }
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
      if !state.tasks[taskIndex].completed {
        state.tasks[taskIndex].status = run.kind == .planning ? .ready : .review
        state.tasks[taskIndex].revision += 1
        state.tasks[taskIndex].updatedAt = .now
      }
      state.runs[index].updatedAt = .now
      state.runs[index].summary =
        run.kind == .planning
        ? "Plan saved. Ready for your go-ahead."
        : run.kind == .implementation
          ? "Implementation finished. Review the changes."
          : "Codex Desktop task finished. Review the changes."
      state.activity.append(
        Activity(
          state.runs[index].summary, projectID: run.projectID, taskID: run.taskID, runID: run.id))
    case .log(let activity): state.activity.append(activity)
    }
    try state.validate()
    return state
  }

  private static func taskStatus(for status: RunStatus, message: String) -> TaskStatus {
    switch status {
    case .queued, .running: .building
    case .needsInput, .interrupted: .waiting
    case .failed:
      message.localizedCaseInsensitiveContains("quota") ? .quota : .error
    case .succeeded: .review
    case .readyForHandoff: .ready
    case .cancelled, .stale, .superseded: .ready
    }
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
      if value.completed {
        item.section = .implementing
        item.status = .done
      }
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
      Project(name: "Project Chase"), Project(name: "StageChase"), Project(name: "Weekend ideas"),
    ]
    library.projects = projects
    for (title, notes) in [
      (
        "Add a voice record dictation button when I'm adding a task",
        "Capture a task by voice while adding it to the board."
      ),
      (
        "Delete tasks using the delete key",
        "Make keyboard deletion available for selected tasks."
      ),
      (
        "Move a task with no plan right to implementation to one shot it",
        "Allow a task without a saved plan to move directly into implementation."
      ),
      (
        "Edit a task text inline in the column view itself",
        "Edit task text without leaving the board column."
      ),
      (
        "Need an app icon, same for desktop and mobile",
        "Use one recognizable app icon across Apple platforms."
      ),
    ] {
      var item = WorkItem(projectID: projects[0].id, title: title)
      item.notes = notes
      library.tasks.append(item)
    }
    var currentTask = WorkItem(
      projectID: projects[0].id,
      title: "Improve phone board navigation and task space",
      stage: .implementation
    )
    currentTask.section = .implementing
    currentTask.status = .building
    library.tasks.append(currentTask)
    library.tasks.append(
      WorkItem(projectID: projects[1].id, title: "Explore a better highlight workflow"))
    library.activity = [
      Activity("Project Chase preview fixture — separate from your saved projects.")
    ]
    return library
  }
}
