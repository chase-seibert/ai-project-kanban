import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class AppModel {
  var library = Library()
  var selectedProjectID: UUID?
  var selectedTaskID: UUID?
  var error: String?
  var loadError: String?
  var ready = false
  var sheet: AppSheet?
  var search = ""
  var showCompleted = false
  var showActivity = false
  var pendingMove: PendingMove?
  private var moveAfterSheet: PendingMove?
  var runnerMessage = "Codex starts only after a confirmed stage change."
  var globalModelConfiguration = CodexModelConfiguration()
  var modelConfigurationError: String?
  var modelCatalog: [CodexModelOption] = []
  var modelCatalogError: String?
  var modelCatalogLoading = false
  @ObservationIgnored private var modelCatalogRequestID = UUID()
  let isPreview: Bool
  @ObservationIgnored private let preferences: UserDefaults
  private var repository: LibraryRepository?
  weak var undoManager: UndoManager?
  private var historyBusy = false
  init(
    repository: LibraryRepository? = nil,
    preferences: UserDefaults = .standard,
    preview: Bool = ProcessInfo.processInfo.arguments.contains("--preview-library")
  ) {
    self.repository = repository
    self.isPreview = preview
    self.preferences =
      preview
      ? UserDefaults(suiteName: "StageChase.Preview.\(UUID().uuidString)")!
      : preferences
    if let saved = self.preferences.data(forKey: "codexModelConfiguration") {
      do {
        globalModelConfiguration = try JSONDecoder().decode(
          CodexModelConfiguration.self, from: saved)
      } catch {
        modelConfigurationError =
          "Saved model settings could not be read. Reset or replace them before queuing Codex work."
      }
    }
  }
  #if os(macOS)
    var runner: CodexRunner?
  #endif

  var selectedProject: Project? { library.projects.first { $0.id == selectedProjectID } }
  var activeRuns: [AgentRun] { library.runs.filter { $0.status.isActive } }
  var projectRuns: [AgentRun] {
    library.runs.filter { selectedProjectID == nil || $0.projectID == selectedProjectID }.sorted {
      $0.createdAt > $1.createdAt
    }
  }
  func load() async {
    guard !ready else { return }
    do {
      if let repository {
        library = try await repository.load()
      } else if isPreview {
        repository = try LibraryRepository(inMemory: true)
        library = try await repository!.importLibrary(JSONEncoder().encode(Library.preview))
      } else {
        let base = try FileManager.default.url(
          for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("StageChase", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        repository = try LibraryRepository(
          url: base.appendingPathComponent("Library-v2.sqlite"),
          legacyURL: base.appendingPathComponent("store.json"))
        library = try await repository!.load()
      }
      let saved = preferences.string(forKey: "selectedProject").flatMap(
        UUID.init(uuidString:))
      selectedProjectID =
        library.projects.contains { $0.id == saved } ? saved : library.projects.first?.id
      ready = true
      #if os(macOS)
        runner = CodexRunner(model: self)
      #endif
    } catch { loadError = error.localizedDescription }
  }

  @discardableResult func perform(_ command: Mutation) async -> Bool {
    guard let repository, ready else { return false }
    let before = library
    do {
      library = try await repository.apply(command)
      registerHistory(command, before: before)
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  private func registerHistory(_ command: Mutation, before: Library) {
    let id: UUID
    let name: String
    switch command {
    case .createTask(let item, _):
      id = item.id
      name = "Add Task"
    case .editTask(let item, _):
      id = item.id
      name = "Edit Task"
    case .move(let value, _, _, _):
      id = value
      name = "Move Task"
    case .complete(let value, _, _):
      id = value
      name = "Complete Task"
    case .deleteTask(let value, _):
      id = value
      name = "Delete Task"
    default: return
    }
    // Undo covers local edits only, never a side-effectful Codex transition or its history.
    guard !library.runs.contains(where: { $0.taskID == id && $0.status.isActive }),
      !(before.runs.contains(where: { $0.taskID == id })
        && library.tasks.first(where: { $0.id == id }) == nil)
    else { return }
    let desired = before.tasks.first { $0.id == id }
    let expected = library.tasks.first { $0.id == id }?.revision
    undoManager?.registerUndo(withTarget: self) { target in
      target.restoreForHistory(id, desired: desired, expected: expected, name: name)
    }
    undoManager?.setActionName(name)
  }

  private func restoreForHistory(_ id: UUID, desired: WorkItem?, expected: Int?, name: String) {
    guard !historyBusy else {
      error = "Wait for the previous undo to finish."
      return
    }
    let inverse = library.tasks.first { $0.id == id }
    let nextRevision = desired.map { (expected ?? $0.revision) + 1 }
    // Register the inverse synchronously while NSUndoManager is still undoing/redoing.
    undoManager?.registerUndo(withTarget: self) { target in
      target.restoreForHistory(id, desired: inverse, expected: nextRevision, name: name)
    }
    undoManager?.setActionName(name)
    historyBusy = true
    Task {
      if !(await perform(.restoreTask(id, desired, expectedRevision: expected))) {
        undoManager?.removeAllActions(withTarget: self)
      }
      historyBusy = false
    }
  }

  func select(_ project: UUID?) {
    selectedProjectID = project
    selectedTaskID = nil
    search = ""
    preferences.set(project?.uuidString, forKey: "selectedProject")
  }

  func items(_ stage: WorkflowStage) -> [WorkItem] {
    guard let selectedProjectID else { return [] }
    return library.items(in: selectedProjectID, stage: stage, completed: showCompleted).filter {
      search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
        || $0.notes.localizedCaseInsensitiveContains(search)
    }
  }

  func saveProject(_ project: Project, isNew: Bool) async -> Bool {
    if await perform(isNew ? .createProject(project) : .editProject(project)) {
      select(project.id)
      return true
    }
    return false
  }

  func addTask(
    _ title: String, stage: WorkflowStage, modelOverride: CodexModelConfiguration? = nil
  ) async -> Bool {
    guard let selectedProjectID else { return false }
    var item = WorkItem(projectID: selectedProjectID, title: title, stage: stage)
    item.modelOverride = modelOverride
    if selectedProject?.automationEnabled == true && [.next, .implementation].contains(stage) {
      if stage == .implementation {
        error =
          "Capture this task in Planned first, attach its Markdown plan in task details, then move it to Implementation."
        return false
      }
      let move = PendingMove(
        item: item, stage: stage, isNew: true, configuration: nil, loading: true)
      if sheet != nil { moveAfterSheet = move } else { pendingMove = move }
      if sheet == nil { preparePendingMove(move.id) }
      return true
    }
    return await perform(.createTask(item))
  }

  func sheetDidDismiss() {
    if let moveAfterSheet {
      pendingMove = moveAfterSheet
      preparePendingMove(moveAfterSheet.id)
      self.moveAfterSheet = nil
    }
  }

  func requestMove(_ item: WorkItem, to stage: WorkflowStage) {
    guard item.stage != stage else { return }
    let automation = library.projects.first { $0.id == item.projectID }?.automationEnabled == true
    if automation && [.next, .implementation].contains(stage) {
      let move = PendingMove(
        item: item, stage: stage, isNew: false, configuration: nil, loading: true)
      pendingMove = move
      preparePendingMove(move.id)
    } else {
      Task { await perform(.move(item.id, stage, expectedRevision: item.revision)) }
    }
  }

  func confirmMove(_ move: PendingMove) async {
    guard !move.loading, let reviewed = move.configuration else { return }
    do {
      try await refreshModelCatalog()
      let current = try resolvedConfiguration(for: move.item)
      guard current == reviewed else {
        updatePending(move.id) {
          $0.configuration = current
          $0.loading = false
          $0.error = "Model settings changed. Review the updated choice and confirm again."
        }
        return
      }
    } catch {
      updatePending(move.id) {
        $0.loading = false
        $0.error = error.localizedDescription
      }
      return
    }
    pendingMove = nil
    let success = await perform(
      move.isNew
        ? .createTask(move.item, configuration: reviewed)
        : .move(
          move.item.id, move.stage, expectedRevision: move.item.revision, configuration: reviewed))
    if success { kickRunner() }
  }

  func setGlobalModelConfiguration(_ configuration: CodexModelConfiguration) {
    globalModelConfiguration = configuration
    do {
      preferences.set(try JSONEncoder().encode(configuration), forKey: "codexModelConfiguration")
      modelConfigurationError = nil
    } catch { modelConfigurationError = error.localizedDescription }
  }

  func resetGlobalModelConfiguration() {
    preferences.removeObject(forKey: "codexModelConfiguration")
    globalModelConfiguration = CodexModelConfiguration()
    modelConfigurationError = nil
  }

  func refreshModelCatalog() async throws {
    guard !isPreview else {
      throw BoardError.invalid("Model discovery is unavailable in preview mode.")
    }
    let requestID = UUID()
    modelCatalogRequestID = requestID
    modelCatalogLoading = true
    do {
      let catalog: [CodexModelOption]
      #if os(macOS)
        guard let runner else { throw BoardError.invalid("The Mac Codex runner is unavailable.") }
        catalog = try await runner.refreshModelCatalog()
      #else
        throw BoardError.invalid("Model discovery is available on Mac only.")
      #endif
      guard !Task.isCancelled, modelCatalogRequestID == requestID else {
        throw BoardError.invalid("A newer Codex model refresh replaced this result. Try again.")
      }
      modelCatalog = catalog
      modelCatalogError = catalog.isEmpty ? "Codex returned no available models." : nil
      modelCatalogLoading = false
    } catch {
      if modelCatalogRequestID == requestID {
        modelCatalogError = error.localizedDescription
        modelCatalogLoading = false
      }
      throw error
    }
  }

  func resolvedConfiguration(for item: WorkItem) throws -> ResolvedCodexConfiguration {
    guard modelConfigurationError == nil else {
      throw BoardError.invalid(modelConfigurationError!)
    }
    guard let project = library.projects.first(where: { $0.id == item.projectID }) else {
      throw BoardError.missing
    }
    let effective = CodexModelResolver.effective(
      task: item.modelOverride, project: project.modelOverride, global: globalModelConfiguration)
    return try CodexModelResolver.resolve(
      effective.configuration, scope: effective.scope, catalog: modelCatalog)
  }

  func inheritedConfiguration(for item: WorkItem) -> CodexModelConfiguration {
    guard let project = library.projects.first(where: { $0.id == item.projectID }) else {
      return globalModelConfiguration
    }
    return CodexModelResolver.effective(
      task: nil, project: project.modelOverride, global: globalModelConfiguration
    ).configuration
  }

  func retry(_ id: UUID) async {
    guard let run = library.runs.first(where: { $0.id == id }) else { return }
    if run.modelConfiguration != nil {
      if await perform(.retry(id)) { kickRunner() }
      return
    }
    do {
      try await refreshModelCatalog()
      guard let task = library.tasks.first(where: { $0.id == run.taskID }) else {
        throw BoardError.missing
      }
      let configuration = try resolvedConfiguration(for: task)
      let retry = PendingMove(
        item: task, stage: run.kind == .planning ? .next : .implementation, isNew: false,
        configuration: configuration, loading: false, retryRunID: run.id,
        error: "This older run has no saved model. Confirming will save this choice for its retry.")
      pendingMove = retry
    } catch { self.error = error.localizedDescription }
  }

  func confirmLegacyRetry(_ move: PendingMove) async {
    guard let runID = move.retryRunID, let configuration = move.configuration else { return }
    do {
      try await refreshModelCatalog()
      guard let task = library.tasks.first(where: { $0.id == move.item.id }) else {
        throw BoardError.missing
      }
      let current = try resolvedConfiguration(for: task)
      guard current == configuration else {
        updatePending(move.id) {
          $0.configuration = current
          $0.error = "Model settings changed. Review the updated choice and confirm again."
        }
        return
      }
    } catch {
      updatePending(move.id) { $0.error = error.localizedDescription }
      return
    }
    pendingMove = nil
    if await perform(.retry(runID, configuration: configuration)) { kickRunner() }
  }

  private func preparePendingMove(_ id: UUID) {
    Task {
      do {
        try await refreshModelCatalog()
        guard let move = pendingMove, move.id == id else { return }
        let configuration = try resolvedConfiguration(for: move.item)
        updatePending(id) {
          $0.configuration = configuration
          $0.loading = false
          $0.error = nil
        }
      } catch {
        updatePending(id) {
          $0.loading = false
          $0.error = error.localizedDescription
        }
      }
    }
  }

  private func updatePending(_ id: UUID, _ update: (inout PendingMove) -> Void) {
    guard var move = pendingMove, move.id == id else { return }
    update(&move)
    pendingMove = move
  }
  func kickRunner() {
    #if os(macOS)
      runner?.drain()
    #endif
  }
  func stop(_ id: UUID) async {
    #if os(macOS)
      await runner?.stop(id)
    #else
      guard var run = library.runs.first(where: { $0.id == id }), run.status == .queued else {
        return
      }
      run.status = .cancelled
      run.summary = "Cancelled before a runner started."
      await perform(.updateRun(run))
    #endif
  }
  func exportData() async -> Data? {
    do { return try await repository?.export() } catch {
      self.error = error.localizedDescription
      return nil
    }
  }
  func restore(_ url: URL) async {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      guard let repository else { return }
      library = try await repository.importLibrary(Data(contentsOf: url))
      select(library.projects.first?.id)
    } catch { self.error = error.localizedDescription }
  }
}

enum AppSheet: Identifiable {
  case newProject
  case editProject(Project)
  case newTask(WorkflowStage)
  case task(UUID)
  case settings
  var id: String {
    switch self {
    case .newProject: "new-project"
    case .editProject(let project): "edit-\(project.id)"
    case .newTask(let stage): "new-task-\(stage.id)"
    case .task(let id): id.uuidString
    case .settings: "settings"
    }
  }
}
struct PendingMove: Identifiable {
  let id = UUID()
  var item: WorkItem
  var stage: WorkflowStage
  var isNew: Bool
  var configuration: ResolvedCodexConfiguration?
  var loading: Bool
  var retryRunID: UUID?
  var error: String?
  init(
    item: WorkItem, stage: WorkflowStage, isNew: Bool,
    configuration: ResolvedCodexConfiguration?, loading: Bool,
    retryRunID: UUID? = nil, error: String? = nil
  ) {
    self.item = item
    self.stage = stage
    self.isNew = isNew
    self.configuration = configuration
    self.loading = loading
    self.retryRunID = retryRunID
    self.error = error
  }
}

struct LibraryDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
