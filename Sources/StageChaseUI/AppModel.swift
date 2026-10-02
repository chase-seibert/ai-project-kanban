import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#endif

@MainActor @Observable final class AppModel {
  #if os(macOS)
    static let defaultPlanFormatPrompt = """
      Write a concise, concrete plan grounded in this repository. Use these sections in this order:

      ## User requirements
      Start with the requested behavior as “As a user, I want …, so that …” statements. Capture the problem and scope here, preserve the user's intent, and identify assumptions rather than inventing requirements.

      ## Architecture and data model
      Explain substantive component, data-flow, persistence, schema/migration, and compatibility changes needed. State clearly when no material architecture or data-model change is required.

      ## Basic test cases
      Give observable scenarios and expected results that show whether the feature works, including important failure or boundary cases.

      ## High-level implementation details
      Outline the main code areas and sequence of work. Include concrete implementation steps, material risks, verification, and unresolved decisions without prescribing trivial edits or writing code.
      """
    static let planFormatPromptPreferenceKey = "codexPlanFormatPrompt"
    static let maximumPlanFormatPromptCharacters = 12_000
  #endif
  var library = Library()
  var selectedProjectID: UUID?
  var selectedTaskID: UUID?
  var boardSelectedTaskID: UUID?
  private var taskChangeReadStateRevision = 0
  var boardFocusedStage: WorkflowSection = .inbox
  var taskPendingDeletionID: UUID?
  var launchTaskOnSelectionID: UUID?
  var saveTaskEditRequestedID: UUID?
  var error: String?
  var phoneCodexActionMessage: String?
  var phoneGitStatuses: [String: SyncGitStatus] = [:]
  var phoneGitErrors: [String: String] = [:]
  var phoneGitMessages: [UUID: String] = [:]
  var phoneGitBusyProjects: Set<UUID> = []
  var loadError: String?
  var ready = false
  var sheet: AppSheet?
  var search = ""
  var showCompleted = false
  var showActivity = false
  var pendingMove: PendingMove?
  private var moveAfterSheet: PendingMove?
  var runnerMessage = "Task runs open in Codex Desktop when automatic invocation is off."
  var autoInvokeCodex = true
  var globalModelConfiguration = CodexModelConfiguration()
  var modelConfigurationError: String?
  #if os(macOS)
    var planFormatPrompt = AppModel.defaultPlanFormatPrompt
    var planFormatPromptError: String?
    var resolvedPlanFormatPrompt: String {
      planFormatPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? Self.defaultPlanFormatPrompt : planFormatPrompt
    }
  #endif
  var approvalMode = CodexApprovalMode.approveForMe
  var approvalModeError: String?
  var modelCatalog: [CodexModelOption] = []
  var modelCatalogError: String?
  var modelCatalogLoading = false
  @ObservationIgnored private var modelCatalogRequestID = UUID()
  let isPreview: Bool
  @ObservationIgnored private let preferences: UserDefaults
  private var repository: LibraryRepository?
  #if os(iOS)
    let syncClient = SyncClient()
    private var replicaRepository: LibraryRepository?
  #endif
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
    autoInvokeCodex =
      self.preferences.object(forKey: Self.autoInvokeCodexPreferenceKey) as? Bool
      ?? true
    #if os(macOS)
      if let saved = self.preferences.string(forKey: Self.planFormatPromptPreferenceKey) {
        planFormatPrompt = String(saved.prefix(Self.maximumPlanFormatPromptCharacters))
        if saved.count > Self.maximumPlanFormatPromptCharacters {
          planFormatPromptError =
            "The saved plan prompt exceeded the character limit and was shortened. Review it in Settings."
        }
      }
    #endif
    if let saved = self.preferences.data(forKey: "codexModelConfiguration") {
      do {
        globalModelConfiguration = try JSONDecoder().decode(
          CodexModelConfiguration.self, from: saved)
      } catch {
        modelConfigurationError =
          "Saved model settings could not be read. Reset or replace them before queuing Codex work."
      }
    }
    if let saved = self.preferences.string(forKey: "codexApprovalMode") {
      if let mode = CodexApprovalMode(rawValue: saved) {
        approvalMode = mode
      } else {
        approvalModeError =
          "Saved approval mode is invalid. Choose an approval mode before starting Codex work."
      }
    }
  }
  static let autoInvokeCodexPreferenceKey = "autoInvokeCodex"
  #if os(macOS)
    static let mcpServerEnabledPreferenceKey = "mcpServerEnabled"
    var runner: CodexRunner?
    var syncServer: SyncServer?
    var mcpServer: MCPServer?
    var gitStatuses: [UUID: GitRepositoryStatus] = [:]
    var gitTaskStatuses: [UUID: GitRepositoryStatus] = [:]
    var gitStatusErrors: [UUID: String] = [:]
    var gitTaskStatusErrors: [UUID: String] = [:]
    var gitBusyProjectIDs: Set<UUID> = []
    var gitActionMessages: [UUID: String] = [:]
    private let gitService = GitService()
  #endif

  #if os(iOS)
    var isConnectedPhone: Bool { syncClient.isPaired }
  #else
    var isConnectedPhone: Bool { false }
  #endif

  var selectedProject: Project? { library.projects.first { $0.id == selectedProjectID } }
  var activeRuns: [AgentRun] { library.runs.filter { $0.status.isActive } }
  #if os(macOS)
    private let planFileStore = PlanFileStore()
  #endif
  private(set) var planFeedbackDrafts: [UUID: String] = [:]
  private(set) var planFeedbackMessages: [UUID: PlanFeedbackMessage] = [:]
  private(set) var planFeedbackInFlight: Set<UUID> = []
  private(set) var taskRefreshInFlight: Set<UUID> = []
  private(set) var taskRefreshMessages: [UUID: String] = [:]
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
        if !isPreview, let repository {
          if mcpServer == nil {
            let server = MCPServer(repository: repository)
            server.onLibraryChanged = { [weak self] library in self?.library = library }
            server.onDesktopSessionLink = { [weak self] runID, threadID in
              guard let self, let runner = self.runner else {
                throw BoardError.invalid("Codex Desktop session linking is unavailable.")
              }
              try await runner.linkDesktopSession(runID: runID, threadID: threadID)
            }
            mcpServer = server
          }
          if preferences.object(forKey: Self.mcpServerEnabledPreferenceKey) as? Bool ?? true {
            preferences.set(true, forKey: Self.mcpServerEnabledPreferenceKey)
            mcpServer?.start()
          }
          if syncServer == nil {
            let server = SyncServer(repository: repository)
            configureSyncServer(server)
            syncServer = server
          }
          let savedPreference = preferences.object(forKey: "localSyncEnabled") as? Bool
          let previouslyPaired = savedPreference == nil && SyncServer.hasSavedPhonePairing()
          if preferences.bool(forKey: "localSyncEnabled") || previouslyPaired {
            preferences.set(true, forKey: "localSyncEnabled")
            await syncServer?.start()
          }
        }
      #else
        if let credential = syncClient.credential {
          let replicaURL = try replicaURL(for: credential.libraryID)
          replicaRepository = try LibraryRepository(url: replicaURL, recoverActiveRuns: false)
          library = try await replicaRepository!.load()
          if library.projects.isEmpty {
            await refreshFromMac()
          } else {
            await applyPendingOverlay()
            await refreshFromMac()
          }
        }
      #endif
      if selectedProjectID == nil {
        selectedProjectID = library.projects.first?.id
      }
      initializeTaskChangeReadMarkersIfNeeded()
    } catch { loadError = error.localizedDescription }
  }

  @discardableResult func perform(_ command: Mutation) async -> Bool {
    #if os(iOS)
      if syncClient.isPaired { return await performRemote(command) }
    #endif
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

  #if os(macOS)
    func startLocalSync() async {
      guard !isPreview else {
        error = "Synchronization is disabled in preview mode."
        return
      }
      guard let repository else {
        error = "Load the Mac library before enabling local sync."
        return
      }
      if syncServer == nil {
        let server = SyncServer(repository: repository)
        configureSyncServer(server)
        syncServer = server
      }
      preferences.set(true, forKey: "localSyncEnabled")
      await syncServer?.start()
    }

    func stopLocalSync() {
      preferences.set(false, forKey: "localSyncEnabled")
      syncServer?.stop()
    }

    private func configureSyncServer(_ server: SyncServer) {
      server.onLibraryChanged = { [weak self] library in self?.library = library }
      server.onPhoneModelCatalogRequest = { [weak self] in
        guard let self else { throw BoardError.invalid("The StageChase model is unavailable.") }
        try await self.refreshModelCatalog()
        return (self.globalModelConfiguration, self.modelCatalog)
      }
      server.onPhoneCodexAction = { [weak self] taskID, expectedRevision, action in
        guard let self else { throw BoardError.invalid("The StageChase model is unavailable.") }
        return try await self.handlePhoneCodexAction(
          taskID: taskID, expectedRevision: expectedRevision, action: action)
      }
    }

    private func handlePhoneCodexAction(
      taskID: UUID, expectedRevision: Int, action: SyncPhoneCodexAction
    ) async throws -> String {
      guard let item = library.tasks.first(where: { $0.id == taskID }),
        item.revision == expectedRevision,
        let project = library.projects.first(where: { $0.id == item.projectID }),
        !project.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw BoardError.invalid("The task or its project folder changed. Refresh and try again.")
      }
      guard !isPreview, runner != nil else {
        throw BoardError.invalid("The StageChase Codex runner is unavailable.")
      }

      let kind: RunKind
      let actionName: String
      switch action {
      case .plan:
        guard !item.completed,
          !library.runs.contains(where: { $0.taskID == taskID && $0.status.isActive })
        else { throw BoardError.invalid("Finish the active run before requesting a new plan.") }
        kind = .planning
        actionName = "Planning"
      case .run:
        guard [.planning, .implementing].contains(item.section), !item.completed,
          !library.runs.contains(where: { $0.taskID == taskID && $0.status.isActive })
        else {
          throw BoardError.invalid(
            "Move the task into Planning or Implementing and finish any active run before requesting Codex."
          )
        }
        kind = .implementation
        actionName = "Run"
      }

      // The authenticated, revision-checked phone command is the user's explicit
      // confirmation. Resolve the Mac-local model choice, then queue and start it here.
      try await refreshModelCatalog()
      guard let current = library.tasks.first(where: { $0.id == taskID }),
        current.revision == expectedRevision,
        let currentProject = library.projects.first(where: { $0.id == current.projectID }),
        !current.completed,
        !library.runs.contains(where: { $0.taskID == taskID && $0.status.isActive }),
        !currentProject.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw BoardError.invalid(
          "The task changed while loading Codex settings. Refresh and try again.")
      }
      let configuration = try resolvedConfiguration(for: current)
      let queued = await perform(
        .runTaskNow(
          current.id, expectedRevision: current.revision, kind: kind,
          configuration: configuration))
      guard queued, let run = library.latestRun(for: current.id), run.status == .queued
      else {
        throw BoardError.invalid(error ?? "The Mac could not queue this Codex run.")
      }
      kickRunner(runID: run.id)
      return "\(actionName) started on the Mac (\(configuration.summary))."
    }

    func startMCPServer() {
      guard !isPreview, let repository else {
        error = "Load the Mac library before enabling the Codex task server."
        return
      }
      if mcpServer == nil {
        let server = MCPServer(repository: repository)
        server.onLibraryChanged = { [weak self] library in self?.library = library }
        server.onDesktopSessionLink = { [weak self] runID, threadID in
          guard let self, let runner = self.runner else {
            throw BoardError.invalid("Codex Desktop session linking is unavailable.")
          }
          try await runner.linkDesktopSession(runID: runID, threadID: threadID)
        }
        mcpServer = server
      }
      preferences.set(true, forKey: Self.mcpServerEnabledPreferenceKey)
      mcpServer?.start()
    }

    func stopMCPServer() {
      preferences.set(false, forKey: Self.mcpServerEnabledPreferenceKey)
      mcpServer?.stop()
    }
  #endif

  #if os(iOS)
    private func phoneGitKey(projectID: UUID, taskID: UUID?) -> String {
      "\(projectID.uuidString):\(taskID?.uuidString ?? "project")"
    }

    func refreshPhoneGitStatus(projectID: UUID, taskID: UUID? = nil) async {
      let key = phoneGitKey(projectID: projectID, taskID: taskID)
      do {
        guard
          case .gitStatus(let status) = try await syncClient.requestDirect(
            .gitStatus(
              requestID: UUID(), projectID: projectID, taskID: taskID,
              expectedRevision: taskID.flatMap { id in
                library.tasks.first { $0.id == id }?.revision
              }))
        else { throw BoardError.invalid("The Mac returned an invalid Git status response.") }
        phoneGitStatuses[key] = status
        phoneGitErrors[key] = nil
      } catch { phoneGitErrors[key] = error.localizedDescription }
    }

    func performPhoneGitAction(_ request: SyncDirectRequest, projectID: UUID) async {
      guard !phoneGitBusyProjects.contains(projectID) else { return }
      phoneGitBusyProjects.insert(projectID)
      phoneGitMessages[projectID] = nil
      defer { phoneGitBusyProjects.remove(projectID) }
      do {
        guard case .accepted(let message) = try await syncClient.requestDirect(request) else {
          throw BoardError.invalid("The Mac returned an invalid Git action response.")
        }
        phoneGitMessages[projectID] = message
        let taskID: UUID?
        switch request {
        case .commitTask(_, _, let id, _): taskID = id
        default: taskID = nil
        }
        await refreshPhoneGitStatus(projectID: projectID, taskID: taskID)
        if taskID != nil { await refreshPhoneGitStatus(projectID: projectID) }
        await refreshFromMac(manual: true)
      } catch { phoneGitMessages[projectID] = error.localizedDescription }
    }

    func commitPhoneTask(taskID: UUID) async {
      guard let item = library.tasks.first(where: { $0.id == taskID }) else { return }
      await performPhoneGitAction(
        .commitTask(
          requestID: UUID(), projectID: item.projectID, taskID: taskID,
          expectedRevision: item.revision), projectID: item.projectID)
    }

    func commitPhoneProject(projectID: UUID) async {
      await performPhoneGitAction(
        .commitProject(requestID: UUID(), projectID: projectID), projectID: projectID)
    }

    func recordPhoneDeployedRevision(projectID: UUID) async {
      await performPhoneGitAction(
        .recordDeployedRevision(requestID: UUID(), projectID: projectID), projectID: projectID)
    }

    func pairPhone() async {
      do {
        let libraryID = try await syncClient.pair()
        replicaRepository = try LibraryRepository(
          url: replicaURL(for: libraryID), recoverActiveRuns: false)
        await refreshFromMac(manual: true)
      } catch {
        syncClient.error = error.localizedDescription
        syncClient.status = "Pairing failed"
        syncClient.lastResultMessage = "Pairing failed: \(error.localizedDescription)"
        syncClient.recordDiagnostic("Pairing failed · \(error.localizedDescription)")
      }
    }

    func unpairPhone() async {
      do {
        try syncClient.unpair()
        if let repository {
          library = try await repository.load()
          select(library.projects.first?.id)
        }
        replicaRepository = nil
      } catch { syncClient.error = error.localizedDescription }
    }

    func readPlanFromMac(_ item: WorkItem) async throws -> String {
      guard syncClient.isPaired else {
        throw BoardError.invalid("Pair this phone with StageChase on the Mac to open saved plans.")
      }
      guard
        case .plan(let markdown) = try await syncClient.requestDirect(
          .readPlan(taskID: item.id, expectedRevision: item.revision))
      else { throw BoardError.invalid("The Mac returned an invalid plan response.") }
      return markdown
    }

    func requestCodexFromMac(_ item: WorkItem, action: SyncPhoneCodexAction) async {
      guard syncClient.isPaired else {
        phoneCodexActionMessage = "Pair this phone with StageChase on the Mac first."
        return
      }
      phoneCodexActionMessage = "Sending request to the Mac…"
      do {
        guard
          case .accepted(let message) = try await syncClient.requestDirect(
            .invokeCodex(
              requestID: UUID(), taskID: item.id, expectedRevision: item.revision, action: action))
        else { throw BoardError.invalid("The Mac returned an invalid Codex response.") }
        phoneCodexActionMessage = message
      } catch {
        phoneCodexActionMessage = error.localizedDescription
      }
    }

    func refreshFromMac(manual: Bool = false, forceFullSnapshot: Bool = false) async {
      guard manual || syncClient.automaticSyncEnabled else { return }
      guard let credential = syncClient.credential else { return }
      guard let replicaRepository else {
        syncClient.status = "Replica unavailable"
        syncClient.lastResultMessage = "The local Mac replica is not open."
        return
      }
      guard !syncClient.hasUnsavedEndpoint else {
        syncClient.status = "Save the Mac address first"
        syncClient.lastResultMessage = "Save the edited address before connecting."
        return
      }
      guard !syncClient.isSyncing else { return }
      syncClient.isSyncing = true
      defer { syncClient.isSyncing = false }
      let startedAt = Date()
      let pendingCount = syncClient.outbox.count
      syncClient.lastAttemptAt = startedAt
      syncClient.status = "Connecting to Mac…"
      syncClient.error = nil
      syncClient.recordDiagnostic("Sync started · \(pendingCount) pending change(s).")
      var acceptedCount = 0
      var receivedSnapshot = false
      do {
        if forceFullSnapshot {
          syncClient.status = "Receiving full snapshot from Mac…"
          guard let snapshot = try await syncClient.snapshot(cursor: 0, force: true) else {
            throw BoardError.invalid("The Mac did not return a full library snapshot.")
          }
          try await apply(
            snapshot, to: replicaRepository, expectedLibraryID: credential.libraryID)
          receivedSnapshot = true
          selectedTaskID = nil
          search = ""
          let discardedCount = try syncClient.discardOutbox()
          syncClient.lastSuccessfulSync = .now
          syncClient.status = "Full refresh complete"
          syncClient.error = nil
          syncClient.lastResultMessage =
            "Full snapshot received from Mac. Discarded \(discardedCount) pending local change(s); no pending local changes remain."
          syncClient.recordDiagnostic(syncClient.lastResultMessage)
          return
        }
        while true {
          while let envelope = syncClient.outbox.first {
            syncClient.status = "Sending pending change…"
            switch try await syncClient.send(envelope) {
            case .applied(_, let snapshot):
              try await apply(
                snapshot, to: replicaRepository, expectedLibraryID: credential.libraryID)
              try syncClient.acknowledge(envelope.operationID)
              acceptedCount += 1
            case .superseded(_, let snapshot):
              try await apply(
                snapshot, to: replicaRepository, expectedLibraryID: credential.libraryID)
              try syncClient.acknowledge(envelope.operationID)
              acceptedCount += 1
            case .conflict(let snapshot):
              try await apply(
                snapshot, to: replicaRepository, expectedLibraryID: credential.libraryID)
              try syncClient.acknowledge(envelope.operationID)
              acceptedCount += 1
              syncClient.recordDiagnostic(
                "Resolved a conflicting phone edit with the latest Mac record.")
            case .rejected(let message):
              guard let snapshot = try await syncClient.snapshot(cursor: 0, force: true) else {
                throw BoardError.invalid(
                  "The Mac did not return its latest record after rejecting a queued change.")
              }
              try await apply(
                snapshot, to: replicaRepository, expectedLibraryID: credential.libraryID)
              try syncClient.acknowledge(envelope.operationID)
              acceptedCount += 1
              syncClient.recordDiagnostic(
                "Resolved a rejected phone edit using the latest Mac record: \(message)")
            }
          }
          syncClient.status = "Refreshing project list…"
          let cursor = try await replicaRepository.syncStateSnapshot().sequence
          if let snapshot = try await syncClient.snapshot(cursor: cursor) {
            try await apply(
              snapshot, to: replicaRepository, expectedLibraryID: credential.libraryID)
            receivedSnapshot = true
          }
          if syncClient.outbox.isEmpty { break }
        }
        syncClient.lastSuccessfulSync = .now
        syncClient.status = "Reachable · last check succeeded"
        let pendingText =
          syncClient.outbox.isEmpty
          ? "No pending changes remain."
          : "\(syncClient.outbox.count) newer change(s) remain queued."
        let snapshotText =
          receivedSnapshot ? "Updated project data arrived. " : "No new project data. "
        syncClient.lastResultMessage =
          "Mac responded in \(Int(Date().timeIntervalSince(startedAt) * 1_000)) ms. \(acceptedCount) queued change(s) resolved. \(snapshotText)\(pendingText)"
        syncClient.error = nil
        syncClient.recordDiagnostic(syncClient.lastResultMessage)
      } catch {
        syncClient.status =
          forceFullSnapshot
          ? receivedSnapshot
            ? "Full refresh incomplete · \(syncClient.outbox.count) pending"
            : "Full refresh failed · \(syncClient.outbox.count) pending"
          : "Unreachable · \(syncClient.outbox.count) pending"
        syncClient.error = error.localizedDescription
        syncClient.lastResultMessage =
          forceFullSnapshot
          ? receivedSnapshot
            ? "The full Mac snapshot was applied, but the phone could not clear its outbox. \(syncClient.outbox.count) change(s) remain saved."
            : "No full snapshot was received. The replica was kept; \(syncClient.outbox.count) pending change(s) remain saved on this phone."
          : "No successful exchange. \(syncClient.outbox.count) pending change(s) remain saved on this phone."
        syncClient.recordDiagnostic("Sync failed · \(error.localizedDescription)")
      }
    }

    private func apply(
      _ snapshot: SyncSnapshot, to repository: LibraryRepository, expectedLibraryID: UUID
    ) async throws {
      guard snapshot.libraryID == expectedLibraryID else {
        throw BoardError.invalid("The Mac identity changed. Pending edits are preserved.")
      }
      let replica = try snapshot.replica()
      try await repository.replaceReplica(
        replica, libraryID: snapshot.libraryID, sequence: snapshot.sequence)
      library = replica
      if let selectedProjectID, !replica.projects.contains(where: { $0.id == selectedProjectID }) {
        select(replica.projects.first?.id)
      }
    }

    private func applyPendingOverlay() async {
      for envelope in syncClient.outbox {
        guard envelope.libraryID == syncClient.credential?.libraryID else { continue }
        do {
          let mutation = try SyncCommandValidator.mutation(for: envelope, in: library)
          library = try BoardReducer.apply(mutation, to: library)
        } catch {
          // This is only an optimistic overlay. The authoritative sync request below
          // decides which version wins and acknowledges the queued command.
          return
        }
      }
    }

    private func replicaURL(for libraryID: UUID) throws -> URL {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("StageChase", isDirectory: true)
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
      return support.appendingPathComponent("Replica-\(libraryID.uuidString).sqlite")
    }

    private func performRemote(_ command: Mutation) async -> Bool {
      guard ready else { return false }
      do {
        let wireCommand: SyncCommand
        let revision: Int?
        switch command {
        case .createTask(let item, let configuration):
          guard configuration == nil else {
            throw BoardError.invalid("Confirm automated work on the Mac.")
          }
          wireCommand = .createTask(
            id: item.id, projectID: item.projectID, title: item.title, notes: item.notes,
            stage: item.stage)
          revision = nil
        case .editTask(let item, let expectedRevision),
          .syncEditTask(let item, let expectedRevision):
          wireCommand = .editTask(id: item.id, title: item.title, notes: item.notes)
          revision = expectedRevision
        case .saveNotes(let id, let notes, let expectedRevision):
          guard let item = library.tasks.first(where: { $0.id == id }) else {
            throw BoardError.missing
          }
          wireCommand = .editTask(id: id, title: item.title, notes: notes)
          revision = expectedRevision
        case .move(let id, let stage, let expectedRevision, let configuration):
          guard configuration == nil else {
            throw BoardError.invalid("Confirm automated work on the Mac.")
          }
          wireCommand = .moveTask(id: id, stage: stage)
          revision = expectedRevision
        case .reorder(let id, let before, let expectedRevision):
          guard let item = library.tasks.first(where: { $0.id == id }) else {
            throw BoardError.missing
          }
          wireCommand = .reorderTask(
            id: id, beforeID: before,
            orderDigest: SyncCommandValidator.orderDigest(
              projectID: item.projectID, stage: item.stage, in: library))
          revision = expectedRevision
        case .complete(let id, let completed, let expectedRevision):
          wireCommand = .completeTask(id: id, completed: completed)
          revision = expectedRevision
        case .deleteTask(let id, let expectedRevision):
          wireCommand = .deleteTask(id: id)
          revision = expectedRevision
        case .editProject(let project):
          guard let existing = library.projects.first(where: { $0.id == project.id }),
            project.name == existing.name, project.directory == existing.directory,
            project.automationEnabled == existing.automationEnabled,
            project.usesWorktrees == existing.usesWorktrees,
            project.deployedCommitHash == existing.deployedCommitHash,
            project.deployedAt == existing.deployedAt
          else {
            throw BoardError.invalid(
              "On iPhone, only project Codex settings can be changed on the Mac.")
          }
          wireCommand = .updateProjectCodexSettings(
            id: project.id, expectedProfile: existing.executionProfile,
            expectedModelOverride: existing.modelOverride, profile: project.executionProfile,
            modelOverride: project.modelOverride)
          revision = nil
        default:
          throw BoardError.invalid("This action is available on the Mac only while connected.")
        }
        let envelope = try syncClient.enqueue(wireCommand, expectedRevision: revision)
        let overlay = try SyncCommandValidator.mutation(for: envelope, in: library)
        library = try BoardReducer.apply(overlay, to: library)
        await refreshFromMac()
        return true
      } catch {
        self.error = error.localizedDescription
        return false
      }
    }
  #endif

  private func registerHistory(_ command: Mutation, before: Library) {
    let id: UUID
    let name: String
    switch command {
    case .createTask(let item, _):
      id = item.id
      name = "Add Task"
    case .editTask(let item, _), .syncEditTask(let item, _):
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
    if let project { markProjectChangesRead(project) }
  }

  func unreadTaskChangeKind(for taskID: UUID) -> TaskChangeKind? {
    _ = taskChangeReadStateRevision
    guard let latest = latestTaskChange(for: taskID),
      latest.date > readDate(forKey: taskChangeReadKey(taskID))
    else { return nil }
    return latest.taskChange
  }

  func unreadProjectChangeCount(_ projectID: UUID) -> Int {
    _ = taskChangeReadStateRevision
    let readAt = readDate(forKey: projectChangeReadKey(projectID))
    return library.tasks.filter { task in
      task.projectID == projectID
        && (latestTaskChange(for: task.id)?.date ?? .distantPast) > readAt
    }.count
  }

  func markTaskChangesRead(_ taskID: UUID) {
    let date = latestTaskChange(for: taskID)?.date ?? .now
    preferences.set(date, forKey: taskChangeReadKey(taskID))
    taskChangeReadStateRevision &+= 1
  }

  func markProjectChangesRead(_ projectID: UUID) {
    let date =
      library.activity.filter { $0.projectID == projectID && $0.taskChange != nil }
      .map(\.date).max() ?? .now
    preferences.set(date, forKey: projectChangeReadKey(projectID))
    taskChangeReadStateRevision &+= 1
  }

  private func latestTaskChange(for taskID: UUID) -> Activity? {
    library.activity.filter { $0.taskID == taskID && $0.taskChange != nil }
      .max { $0.date < $1.date }
  }

  private func readDate(forKey key: String) -> Date {
    preferences.object(forKey: key) as? Date ?? .distantPast
  }

  private func taskChangeReadKey(_ id: UUID) -> String {
    "taskChangeReadAt.\(id.uuidString.lowercased())"
  }

  private func projectChangeReadKey(_ id: UUID) -> String {
    "projectChangeReadAt.\(id.uuidString.lowercased())"
  }

  private func initializeTaskChangeReadMarkersIfNeeded() {
    let key = "taskChangeReadMarkersInitialized"
    guard !preferences.bool(forKey: key) else { return }
    for project in library.projects { markProjectChangesRead(project.id) }
    for task in library.tasks { markTaskChangesRead(task.id) }
    preferences.set(true, forKey: key)
  }

  #if os(macOS)
    func planFeedbackDraft(for taskID: UUID) -> String {
      planFeedbackDrafts[taskID] ?? ""
    }

    func setPlanFeedbackDraft(_ text: String, for taskID: UUID) {
      planFeedbackDrafts[taskID] = text
      planFeedbackMessages.removeValue(forKey: taskID)
    }

    func appendPlanFeedback(taskID: UUID, expectedRevision: Int, text: String) async -> Bool {
      guard !isPreview else {
        planFeedbackMessages[taskID] = PlanFeedbackMessage(
          text: "Appending to project files is disabled in preview mode.", isError: true)
        return false
      }
      guard planFeedbackInFlight.insert(taskID).inserted else { return false }
      defer { planFeedbackInFlight.remove(taskID) }
      guard let item = library.tasks.first(where: { $0.id == taskID }),
        let planPath = item.planPath,
        item.revision == expectedRevision,
        library.latestRun(for: taskID)?.status.isActive != true,
        let project = library.projects.first(where: { $0.id == item.projectID })
      else {
        planFeedbackMessages[taskID] = PlanFeedbackMessage(
          text: "This task or plan changed. Review the task details, then try again.", isError: true
        )
        return false
      }
      do {
        try await planFileStore.appendFeedback(
          text, projectDirectory: project.directory, relativePath: planPath)
        if planFeedbackDrafts[taskID] == text { planFeedbackDrafts.removeValue(forKey: taskID) }
        planFeedbackMessages[taskID] = PlanFeedbackMessage(
          text: "Feedback appended to plan.", isError: false)
        return true
      } catch {
        planFeedbackMessages[taskID] = PlanFeedbackMessage(
          text: error.localizedDescription, isError: true)
        return false
      }
    }
  #endif

  func items(_ stage: WorkflowStage) -> [WorkItem] {
    guard let selectedProjectID else { return [] }
    return library.items(in: selectedProjectID, stage: stage, completed: showCompleted).filter {
      search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
        || $0.notes.localizedCaseInsensitiveContains(search)
    }
  }

  func items(_ section: WorkflowSection) -> [WorkItem] {
    guard let selectedProjectID else { return [] }
    return library.items(in: selectedProjectID, section: section, completed: showCompleted).filter {
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

  #if os(macOS)
    func refreshGitStatus(projectID: UUID) async {
      guard let project = library.projects.first(where: { $0.id == projectID }),
        !project.directory.isEmpty
      else {
        gitStatuses[projectID] = nil
        gitStatusErrors[projectID] = "Choose a project folder to see Git status."
        return
      }
      do {
        gitStatuses[projectID] = try await gitService.status(
          in: URL(fileURLWithPath: project.directory))
        gitStatusErrors[projectID] = nil
      } catch {
        gitStatuses[projectID] = nil
        gitStatusErrors[projectID] = error.localizedDescription
      }
    }

    func refreshTaskGitStatus(taskID: UUID) async {
      guard let folder = taskGitFolder(taskID: taskID) else {
        gitTaskStatuses[taskID] = nil
        gitTaskStatusErrors[taskID] = "Choose a project folder to see Git status."
        return
      }
      do {
        gitTaskStatuses[taskID] = try await gitService.status(in: folder)
        gitTaskStatusErrors[taskID] = nil
      } catch {
        gitTaskStatuses[taskID] = nil
        gitTaskStatusErrors[taskID] = error.localizedDescription
      }
    }

    func commitTaskChanges(taskID: UUID) async {
      guard let item = library.tasks.first(where: { $0.id == taskID }),
        let project = library.projects.first(where: { $0.id == item.projectID })
      else { return }
      guard !gitBusyProjectIDs.contains(project.id) else { return }
      gitBusyProjectIDs.insert(project.id)
      gitActionMessages[project.id] = nil
      defer { gitBusyProjectIDs.remove(project.id) }
      do {
        let result = try await gitService.commitAll(
          in: taskGitFolder(taskID: taskID) ?? URL(fileURLWithPath: project.directory),
          taskTitle: item.title)
        await refreshTaskGitStatus(taskID: taskID)
        await refreshGitStatus(projectID: project.id)
        gitStatusErrors[project.id] = nil
        gitActionMessages[project.id] =
          "Committed \(result.hash.prefix(12)) · \(GitService.commitMessage(item.title))"
      } catch {
        gitActionMessages[project.id] = error.localizedDescription
        await refreshTaskGitStatus(taskID: taskID)
        await refreshGitStatus(projectID: project.id)
      }
    }

    func commitProjectChanges(projectID: UUID) async {
      guard let project = library.projects.first(where: { $0.id == projectID }) else { return }
      guard !gitBusyProjectIDs.contains(projectID) else { return }
      gitBusyProjectIDs.insert(projectID)
      gitActionMessages[projectID] = nil
      defer { gitBusyProjectIDs.remove(projectID) }
      do {
        guard !project.directory.isEmpty else { throw GitServiceError.missingFolder }
        guard let latestTask = library.latestCompletedTask(in: projectID) else {
          throw GitServiceError.command(
            "Mark a task complete in this project before committing project changes.")
        }
        let result = try await gitService.commitAll(
          in: URL(fileURLWithPath: project.directory), taskTitle: latestTask.title)
        await refreshGitStatus(projectID: projectID)
        gitActionMessages[projectID] =
          "Committed \(result.hash.prefix(12)) · \(GitService.commitMessage(latestTask.title))"
      } catch {
        gitActionMessages[projectID] = error.localizedDescription
        await refreshGitStatus(projectID: projectID)
      }
    }

    func recordDeployedRevision(projectID: UUID) async {
      guard !gitBusyProjectIDs.contains(projectID),
        var project = library.projects.first(where: { $0.id == projectID })
      else { return }
      gitBusyProjectIDs.insert(projectID)
      gitActionMessages[projectID] = nil
      defer { gitBusyProjectIDs.remove(projectID) }
      do {
        let status = try await gitService.status(in: URL(fileURLWithPath: project.directory))
        guard let head = status.head else {
          throw GitServiceError.command("This repository has no commit to record as deployed.")
        }
        gitStatuses[projectID] = status
        gitStatusErrors[projectID] = nil
        project.deployedCommitHash = head
        project.deployedAt = Date()
        guard await perform(.editProject(project)) else {
          throw BoardError.invalid(error ?? "Could not save the deployed revision.")
        }
        gitActionMessages[projectID] = "Recorded deployed revision \(head.prefix(12))."
      } catch {
        gitActionMessages[projectID] = error.localizedDescription
        await refreshGitStatus(projectID: projectID)
      }
    }

    func taskUsesSeparateGitWorktree(taskID: UUID) -> Bool {
      guard let item = library.tasks.first(where: { $0.id == taskID }),
        let project = library.projects.first(where: { $0.id == item.projectID }),
        let path = library.latestRun(for: taskID)?.workDirectory
      else { return false }
      return URL(fileURLWithPath: path).standardizedFileURL.path
        != URL(fileURLWithPath: project.directory).standardizedFileURL.path
    }

    private func taskGitFolder(taskID: UUID) -> URL? {
      guard let item = library.tasks.first(where: { $0.id == taskID }),
        let project = library.projects.first(where: { $0.id == item.projectID })
      else { return nil }
      if let workDirectory = library.latestRun(for: taskID)?.workDirectory {
        return URL(fileURLWithPath: workDirectory)
      }
      guard !project.directory.isEmpty else { return nil }
      return URL(fileURLWithPath: project.directory)
    }
  #endif

  func addTask(
    _ title: String, stage: WorkflowStage, modelOverride: CodexModelConfiguration? = nil
  ) async -> Bool {
    guard let selectedProjectID else { return false }
    var item = WorkItem(projectID: selectedProjectID, title: title, stage: stage)
    item.modelOverride = modelOverride
    if !isConnectedPhone, autoInvokeCodex, selectedProject?.automationEnabled == true,
      [.next, .implementation].contains(stage)
    {
      let move = PendingMove(
        item: item, stage: stage, isNew: true, configuration: nil, loading: true)
      if sheet != nil { moveAfterSheet = move } else { pendingMove = move }
      if sheet == nil { preparePendingMove(move.id) }
      return true
    }
    return await perform(.createTask(item))
  }

  func addTask(
    _ title: String, section: WorkflowSection, modelOverride: CodexModelConfiguration? = nil
  ) async -> Bool {
    guard let selectedProjectID else { return false }
    let stage = section.compatibilityStage
    var item = WorkItem(projectID: selectedProjectID, title: title, stage: stage)
    item.section = section
    item.status = section == .inbox ? .triage : (section == .planning ? .planning : .ready)
    item.modelOverride = modelOverride
    if !isConnectedPhone, autoInvokeCodex, selectedProject?.automationEnabled == true,
      [.planning, .implementing].contains(section)
    {
      let move = PendingMove(
        item: item, stage: stage, isNew: true, configuration: nil, loading: true)
      if sheet != nil { moveAfterSheet = move } else { pendingMove = move }
      if sheet == nil { preparePendingMove(move.id) }
      return true
    }
    return await perform(.createTask(item))
  }

  func setPriority(_ priority: TaskPriority?, for id: UUID) async {
    guard let item = library.tasks.first(where: { $0.id == id }), item.priority != priority else {
      return
    }
    var updated = item
    updated.priority = priority
    _ = await perform(.editTask(updated, expectedRevision: item.revision))
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
    let shouldPrepareRun =
      !isConnectedPhone && autoInvokeCodex && automation
      && [.next, .implementation].contains(stage)
    Task {
      guard await perform(.move(item.id, stage, expectedRevision: item.revision)) else { return }
      guard shouldPrepareRun,
        !library.runs.contains(where: { $0.taskID == item.id && $0.status.isActive }),
        let moved = library.tasks.first(where: { $0.id == item.id })
      else { return }
      let pending = PendingMove(
        item: moved, stage: stage, isNew: false, configuration: nil, loading: true)
      pendingMove = pending
      preparePendingMove(pending.id)
    }
  }

  func requestMove(_ item: WorkItem, to section: WorkflowSection) {
    guard item.section != section else { return }
    let stage = section.compatibilityStage
    let automation = library.projects.first { $0.id == item.projectID }?.automationEnabled == true
    let shouldPrepareRun =
      !isConnectedPhone && autoInvokeCodex && automation
      && [.planning, .implementing].contains(section)
    Task {
      guard await perform(.move(item.id, stage, expectedRevision: item.revision)) else { return }
      guard shouldPrepareRun,
        !library.runs.contains(where: { $0.taskID == item.id && $0.status.isActive }),
        let moved = library.tasks.first(where: { $0.id == item.id })
      else { return }
      let pending = PendingMove(
        item: moved, stage: stage, isNew: false, configuration: nil, loading: true)
      pendingMove = pending
      preparePendingMove(pending.id)
    }
  }

  func requestRunnerRun(_ item: WorkItem) {
    requestRunnerRun(
      item, kind: item.section == .planning ? .planning : .implementation)
  }

  func requestRunnerRun(_ item: WorkItem, kind: RunKind) {
    #if os(macOS)
      guard !isConnectedPhone, !isPreview else { return }
      guard runner != nil else {
        error = "The StageChase Codex runner is unavailable."
        return
      }
      guard
        kind == .planning || (kind == .implementation && item.section == .implementing),
        !item.completed,
        !library.runs.contains(where: { $0.taskID == item.id && $0.status.isActive }),
        let current = library.tasks.first(where: { $0.id == item.id }),
        let project = library.projects.first(where: { $0.id == item.projectID }),
        !project.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return }
      let pending = PendingMove(
        item: current, stage: current.stage, isNew: false, runKind: kind,
        configuration: nil, loading: true)
      pendingMove = pending
      preparePendingMove(pending.id)
    #else
      return
    #endif
  }

  func confirmMove(_ move: PendingMove) async {
    guard move.runOnly || autoInvokeCodex, !move.loading,
      let reviewed = move.configuration
    else { return }
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
    if move.runOnly {
      if await perform(
        .runTaskNow(
          move.item.id, expectedRevision: move.item.revision,
          kind: move.runKind ?? (move.item.section == .planning ? .planning : .implementation),
          configuration: reviewed)),
        let run = library.latestRun(for: move.item.id), run.status == .queued
      {
        kickRunner(runID: run.id)
      }
    } else {
      let success = await perform(
        move.isNew
          ? .createTask(move.item, configuration: reviewed)
          : .move(
            move.item.id, move.stage, expectedRevision: move.item.revision,
            configuration: reviewed))
      if success { kickRunner() }
    }
  }

  func setGlobalModelConfiguration(_ configuration: CodexModelConfiguration) {
    globalModelConfiguration = configuration
    do {
      preferences.set(try JSONEncoder().encode(configuration), forKey: "codexModelConfiguration")
      modelConfigurationError = nil
    } catch { modelConfigurationError = error.localizedDescription }
  }

  func setAutoInvokeCodex(_ enabled: Bool) {
    autoInvokeCodex = enabled
    preferences.set(enabled, forKey: Self.autoInvokeCodexPreferenceKey)
    if enabled { kickRunner() }
  }

  func resetGlobalModelConfiguration() {
    preferences.removeObject(forKey: "codexModelConfiguration")
    globalModelConfiguration = CodexModelConfiguration()
    modelConfigurationError = nil
  }

  #if os(macOS)
    func setPlanFormatPrompt(_ prompt: String) {
      planFormatPrompt = String(prompt.prefix(Self.maximumPlanFormatPromptCharacters))
      preferences.set(planFormatPrompt, forKey: Self.planFormatPromptPreferenceKey)
      planFormatPromptError =
        prompt.count > Self.maximumPlanFormatPromptCharacters
        ? "The plan prompt is limited to \(Self.maximumPlanFormatPromptCharacters) characters. Extra text was not saved."
        : nil
    }

    func resetPlanFormatPrompt() {
      preferences.removeObject(forKey: Self.planFormatPromptPreferenceKey)
      planFormatPrompt = Self.defaultPlanFormatPrompt
      planFormatPromptError = nil
    }
  #endif

  func setApprovalMode(_ mode: CodexApprovalMode) {
    approvalMode = mode
    preferences.set(mode.rawValue, forKey: "codexApprovalMode")
    approvalModeError = nil
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
        guard syncClient.isPaired,
          case .modelCatalog(let globalConfiguration, let options) =
            try await syncClient
            .requestDirect(.modelCatalog)
        else {
          throw BoardError.invalid("Pair this phone with StageChase on the Mac to load models.")
        }
        globalModelConfiguration = globalConfiguration
        catalog = options
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
    guard run.kind != .task else {
      error = "Use Copy prompt or Launch Codex from task details to start a manual handoff."
      return
    }
    guard autoInvokeCodex else {
      error = "Automatic invocation is off. Use Copy prompt or Launch Codex from task details."
      return
    }
    guard library.projects.first(where: { $0.id == run.projectID })?.automationEnabled == true
    else {
      error =
        "Automatic runs are disabled for this project. Use Copy prompt or Launch Codex from task details."
      return
    }
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
  func kickRunner(runID: UUID? = nil) {
    #if os(macOS)
      if let runID {
        runner?.startExplicitly(runID)
      } else {
        runner?.resumeQueueAndDrain()
      }
    #endif
  }
  #if os(macOS)
    var runStatusRefreshInFlight: Set<UUID> = []

    func refreshTask(_ taskID: UUID, preservingEdits: Bool = false) async {
      guard taskRefreshInFlight.insert(taskID).inserted else { return }
      defer { taskRefreshInFlight.remove(taskID) }
      taskRefreshMessages[taskID] = nil
      guard !isPreview, let repository else {
        taskRefreshMessages[taskID] = "Task refresh is unavailable in preview mode."
        return
      }
      do {
        let refreshed = try await repository.refresh()
        guard let task = refreshed.tasks.first(where: { $0.id == taskID }) else {
          library = refreshed
          taskRefreshMessages[taskID] = "This task no longer exists in the StageChase library."
          return
        }
        library = refreshed
        let project = refreshed.projects.first { $0.id == task.projectID }
        let planResult: String
        if task.planPath == nil {
          planResult = "No saved plan is attached."
        } else if let project, PlanHandoffPrompt.hasReadablePlan(for: task, project: project) {
          planResult = "Saved plan is available."
        } else {
          planResult = "The attached plan is unavailable or outside the project folder."
        }
        var sessionResult = "No linked Codex session is attached."
        if let run = refreshed.latestRun(for: taskID), run.kind == .task,
          run.threadID != nil
        {
          sessionResult =
            await refreshCodexStatus(run.id)
            ? "Linked Codex status and latest activity refreshed."
            : "Task and plan refreshed; linked Codex status could not be read. The saved run state was preserved."
        }
        let editResult =
          preservingEdits
          ? " Your unsaved edits are preserved; the saved task changed, so saving may require resolving a revision conflict."
          : ""
        taskRefreshMessages[taskID] =
          "Task refreshed (revision \(task.revision)). \(planResult) \(sessionResult)\(editResult)"
      } catch {
        taskRefreshMessages[taskID] = "Task refresh failed: \(error.localizedDescription)"
      }
    }

    func rerunInCodex(_ runID: UUID) async {
      guard var run = library.runs.first(where: { $0.id == runID }), run.kind == .task,
        let context = run.handoffContext
      else { return }
      run.status = .readyForHandoff
      run.error = nil
      run.threadID = nil
      run.turnID = nil
      run.summary = "Preparing a fresh Codex Desktop session for this context."
      guard await perform(.updateRun(run)), let runner else { return }
      do {
        try await runner.prepareDesktopHandoff(runID: runID)
        guard let refreshed = library.runs.first(where: { $0.id == runID }),
          let threadID = refreshed.threadID
        else { throw BoardError.invalid("StageChase could not save the Codex Desktop session.") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context, forType: .string)
        var readyRun = refreshed
        readyRun.summary = "Context copied. Rerun it in Codex Desktop, then refresh status here."
        if await perform(.updateRun(readyRun)) { openCodexSession(threadID) }
      } catch {
        guard var failedRun = library.runs.first(where: { $0.id == runID }) else { return }
        failedRun.status = .failed
        failedRun.error = error.localizedDescription
        failedRun.summary = "Codex Desktop rerun could not be prepared."
        _ = await perform(.updateRun(failedRun))
      }
    }

    @discardableResult func refreshCodexStatus(_ runID: UUID) async -> Bool {
      guard runStatusRefreshInFlight.insert(runID).inserted else { return false }
      defer { runStatusRefreshInFlight.remove(runID) }
      do {
        guard let runner else { throw BoardError.invalid("The Mac Codex runner is unavailable.") }
        try await runner.refreshDesktopStatus(runID: runID)
        return true
      } catch {
        self.error = error.localizedDescription
        return false
      }
    }

    func closeCodexSession(_ id: UUID) async {
      await runner?.closeSession(runID: id)
    }
    func closeCodexSessionReason(_ id: UUID) -> String? {
      runner?.closeAvailability(runID: id) ?? "The Mac Codex runner is unavailable."
    }
    func openCodexSession(_ threadID: String) {
      guard let url = URL(string: "codex://threads/\(threadID)"), NSWorkspace.shared.open(url)
      else {
        runnerMessage =
          "Codex could not open this session. Use Copy session ID, then find it in the desktop app."
        return
      }
    }
  #endif
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
  case newTask(WorkflowSection)
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
  var runKind: RunKind?
  var configuration: ResolvedCodexConfiguration?
  var loading: Bool
  var retryRunID: UUID?
  var error: String?
  init(
    item: WorkItem, stage: WorkflowStage, isNew: Bool,
    runKind: RunKind? = nil, configuration: ResolvedCodexConfiguration?, loading: Bool,
    retryRunID: UUID? = nil, error: String? = nil
  ) {
    self.item = item
    self.stage = stage
    self.isNew = isNew
    self.runKind = runKind
    self.configuration = configuration
    self.loading = loading
    self.retryRunID = retryRunID
    self.error = error
  }
  var runOnly: Bool { runKind != nil }
}

struct PlanFeedbackMessage {
  var text: String
  var isError: Bool
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
