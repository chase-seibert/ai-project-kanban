import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.undoManager) private var undoManager
  @Environment(\.scenePhase) private var scenePhase
  @State private var phonePath: [PhoneDestination] = []
  @State private var settingsInitialTab: AppSettingsTab = .general
  var body: some View {
    @Bindable var model = model
    Group {
      if let error = model.loadError {
        libraryUnavailable(error: error)
      } else if !model.ready {
        ProgressView("Opening your projects…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        #if os(macOS)
          NavigationSplitView {
            ProjectSidebar(settingsInitialTab: $settingsInitialTab)
              .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 400)
          } detail: {
            HStack(spacing: 0) {
              if let workspaceTaskView = model.workspaceTaskView {
                WorkspaceTasksView(preset: workspaceTaskView)
              } else if model.selectedProject != nil {
                BoardView()
              } else {
                WelcomeView()
              }
              if let id = model.selectedTaskID {
                Divider()
                TaskDetail(taskID: id).id(id).frame(width: 340)
              } else if model.showActivity {
                Divider()
                ActivityPanel().frame(width: 370)
              }
            }
            .toolbar {
              if let server = model.syncServer, server.isEnabled {
                ToolbarItem(placement: .navigation) {
                  Button {
                    settingsInitialTab = .connection
                    model.sheet = .settings
                  } label: {
                    Image(systemName: "network")
                      .foregroundStyle(loopbackVerificationColor(server.portRegistrationState))
                  }
                  .buttonStyle(.plain)
                  .help("Open Connection settings to inspect local sync verification")
                  .accessibilityLabel(loopbackVerificationLabel(server.portRegistrationState))
                  .accessibilityIdentifier("local-sync-verification-settings")
                }
              }
              ToolbarItemGroup {
                Button {
                  model.selectedTaskID = nil
                  model.showActivity.toggle()
                } label: {
                  Label("Activity", systemImage: "waveform.path.ecg")
                }.help("Show agent activity")
                Menu {
                  Toggle("Show completed", isOn: $model.showCompleted)
                  if let project = model.selectedProject {
                    Button("Project settings…") { model.sheet = .editProject(project) }
                    Button("Delete project…", role: .destructive) {
                      model.projectPendingDeletion = project
                    }
                  }
                } label: {
                  Image(systemName: "ellipsis.circle")
                }
              }
            }.searchable(text: $model.search, prompt: "Find tasks")
          }
        #else
          NavigationStack(path: $phonePath) {
            ProjectSidebar(
              settingsInitialTab: $settingsInitialTab,
              onOpen: { phonePath.append(.board) },
              onOpenWorkspace: { phonePath.append(.workspaceTasks($0)) }
            )
            .navigationTitle("Projects")
            .toolbar {
              ToolbarItem(placement: .primaryAction) {
                Button("New project", systemImage: "plus") { model.sheet = .newProject }
              }
            }
            .navigationDestination(for: PhoneDestination.self, destination: phoneDestination)
          }
        #endif
      }
    }
    .sheet(item: $model.sheet, onDismiss: { model.sheetDidDismiss() }) { sheet in
      Group {
        switch sheet {
        case .newProject: ProjectEditor(project: Project(name: ""), isNew: true)
        case .editProject(let project): ProjectEditor(project: project, isNew: false)
        case .deletedProjects: DeletedProjectsView()
        case .newTask(let stage): NewTaskEditor(stage: stage)
        #if os(macOS)
          case .makeOutput: MakeOutputSheet()
        #endif
        case .settings:
          NavigationStack {
            AppSettings(initialTab: settingsInitialTab).navigationTitle("Settings")
              .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { model.sheet = nil } }
              }
          }
        }
      }
      .alert(
        "Couldn’t complete that action",
        isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
      ) {
        Button("OK") { model.error = nil }
      } message: {
        Text(model.error ?? "")
      }
    }
    .alert(
      "Couldn’t complete that action",
      isPresented: Binding(
        get: { model.error != nil && model.sheet == nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .confirmationDialog(
      "Delete project?",
      isPresented: Binding(
        get: { model.projectPendingDeletion != nil },
        set: { if !$0 { model.projectPendingDeletion = nil } }),
      titleVisibility: .visible
    ) {
      if let project = model.projectPendingDeletion {
        Button("Delete \(project.name)", role: .destructive) {
          model.projectPendingDeletion = nil
          Task { await model.setProjectDeleted(project, deleted: true) }
        }
      }
      Button("Cancel", role: .cancel) { model.projectPendingDeletion = nil }
    } message: {
      Text(
        "This project and its tasks will be hidden. All data and repository files are kept. Restore it anytime from Deleted Projects."
      )
    }
    .onChange(of: model.selectedProjectID) { _, newProjectID in
      #if os(iOS)
        // Let the project row and confirmation dialog finish updating before
        // changing the NavigationStack path. Deleting the selected project can
        // change both in the same transaction.
        Task { @MainActor in
          await Task.yield()
          guard model.selectedProjectID == newProjectID, !model.isPreview else { return }
          if model.selectedProject == nil {
            phonePath = []
          } else if !phonePath.isEmpty {
            phonePath = [.board]
          }
        }
      #endif
    }
    .confirmationDialog(
      model.pendingMove?.runOnly == true
        ? model.pendingMove?.runKind == .planning
          ? "Plan this task with StageChase?"
          : "Execute this task with StageChase?"
        : "Start Codex \(model.pendingMove?.stage == .next ? "planning" : "implementation")?",
      isPresented: Binding(
        get: { model.pendingMove != nil }, set: { if !$0 { model.pendingMove = nil } }),
      titleVisibility: .visible
    ) {
      if let move = model.pendingMove {
        Button(
          move.retryRunID != nil
            ? "Confirm model and retry"
            : move.runKind == .planning
              ? "Plan with StageChase"
              : move.runOnly ? "Execute Task" : "Start Codex"
        ) {
          Task {
            if move.retryRunID == nil {
              await model.confirmMove(move)
            } else {
              await model.confirmLegacyRetry(move)
            }
          }
        }.disabled(move.loading || move.configuration == nil)
      }
      Button(
        model.pendingMove?.runOnly == true || model.pendingMove?.retryRunID != nil
          ? "Cancel" : "Keep moved task", role: .cancel
      ) {
        model.pendingMove = nil
      }
    } message: {
      if let move = model.pendingMove {
        Text(moveConfirmationMessage(move))
      } else {
        Text("Codex starts only after confirmation.")
      }
    }
    .task(id: scenePhase) {
      model.undoManager = undoManager
      await model.load()
      #if os(macOS)
        if scenePhase == .active {
          model.codexUsageService.start()
        } else {
          model.codexUsageService.stop()
        }
      #endif
      if model.isPreview {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-task"), var task = model.library.tasks.first {
          let completedPreview = !arguments.contains("--preview-active-task")
          if arguments.contains("--preview-long-title") {
            task.title =
              "Make it easier to review a task with a very long title, understand what changed in the latest implementation, and decide what to do next without losing the supporting context"
          }
          task.section = arguments.contains("--preview-inbox-task") ? .inbox : .implementing
          task.planAvailable = arguments.contains("--preview-saved-plan")
          task.status = completedPreview ? .reviewing : .planApproved
          task.completed = completedPreview
          task.completedAt = completedPreview ? .now : nil
          model.library.tasks[0] = task
          model.library.runs = [RunKind.task, .implementation, .planning].enumerated().map {
            index, kind in
            var run = AgentRun(task: task, kind: kind)
            run.source = .codexDesktop
            run.status = .succeeded
            run.summary = index == 2 ? "Latest update is ready for review." : "Earlier run details."
            run.createdAt = .now.addingTimeInterval(TimeInterval(-index * 3600))
            run.updatedAt = run.createdAt
            return run
          }
          if arguments.contains("--preview-attention") {
            task.status = .waiting
            model.library.tasks[0] = task
            model.library.runs[0].status = .needsInput
            model.library.runs[0].summary =
              "Please review the simulator screenshots before continuing."
          }
          phonePath = [.board, .task(task.id)]
        } else if arguments.contains("--preview-board") {
          if arguments.contains("--preview-planning"), var task = model.library.tasks.first {
            task.section = .planning
            task.status = .planApproved
            task.isFavorite = true
            task.modelTag = .high
            model.library.tasks[0] = task
            model.boardFocusedStage = .planning
          } else if arguments.contains("--preview-implementing") {
            model.boardFocusedStage = .implementing
          }
          if arguments.contains("--preview-empty") { model.boardFilter = .favorites }
          phonePath = [.board]
        }
      }
      #if os(iOS)
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
          await model.refreshFromMac()
          try? await Task.sleep(for: .seconds(3))
        }
      #endif
    }
  }

  private func moveConfirmationMessage(_ move: PendingMove) -> String {
    var lines: [String] = []
    if move.loading { lines.append("Loading model settings…") }
    if let summary = move.configuration?.summary { lines.append(summary) }
    if move.runOnly,
      let project = model.library.projects.first(where: { $0.id == move.item.projectID })
    {
      lines.append(project.executionProfile.title)
    }
    if move.runOnly {
      let kind = move.runKind == .planning ? "planning" : "implementation"
      lines.append(
        "StageChase will run a \(kind) session here. Codex Desktop will not open, and the task will stay in \(move.item.section.title)."
      )
    } else if move.retryRunID == nil {
      lines.append(
        "The task is already in \(move.stage.title). Cancel to leave it there without starting Codex."
      )
    }
    if move.error != nil, move.retryRunID == nil {
      lines.append(
        move.runOnly
          ? "The task remains in its current section; Codex did not start."
          : "The move is saved; Codex did not start.")
    }
    if let error = move.error { lines.append(error) }
    lines.append(
      "Usage may be billed. Quota, sign-in or device unlock, service errors, and genuine requests for input may still need your attention. Watch progress or stop the run in Activity."
    )
    return lines.joined(separator: "\n")
  }

  #if os(iOS)
    @ViewBuilder private func phoneDestination(_ destination: PhoneDestination) -> some View {
      switch destination {
      case .board:
        BoardView(onOpenTask: { id in phonePath.append(.task(id)) })
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .principal) {
              Text(phoneProjectTitle).lineLimit(1).accessibilityLabel(
                "Project \(phoneProjectTitle)")
            }
            ToolbarItem(placement: .topBarTrailing) {
              Button("Add task", systemImage: "plus") {
                model.sheet = .newTask(model.boardFocusedStage)
              }
              .buttonStyle(.borderedProminent).tint(.blue)
              .disabled(model.selectedProject == nil)
              .accessibilityIdentifier("phone-add-task")
            }
            ToolbarItem(placement: .topBarTrailing) { phoneBoardMoreMenu }
          }
      case .workspaceTasks(let preset):
        WorkspaceTasksView(preset: preset) { id in phonePath.append(.task(id)) }
          .navigationTitle(preset.title)
          .navigationBarTitleDisplayMode(.inline)
      case .activity:
        ActivityPanel().navigationTitle("Activity")
      case .connection:
        SyncConnectionView().navigationTitle("Connection")
      case .settings:
        AppSettings().navigationTitle("Settings")
      case .task(let id):
        TaskDetail(taskID: id).id(id)
          .navigationTitle("")
          .navigationBarTitleDisplayMode(.inline)
      case .projectGit(let id):
        projectGitDestination(id)
      }
    }

    private var phoneBoardMoreMenu: some View {
      Menu {
        Toggle(
          "Show completed",
          isOn: Binding(get: { model.showCompleted }, set: { model.showCompleted = $0 }))
        Button(
          model.syncClient.isSyncing ? "Refreshing…" : "Refresh from Mac",
          systemImage: "arrow.clockwise"
        ) {
          Task { await model.refreshFromMac(manual: true) }
        }
        .disabled(
          !model.isConnectedPhone || model.syncClient.isSyncing
            || model.syncClient.hasUnsavedEndpoint
        )
        Button("Connection", systemImage: "network") { phonePath.append(.connection) }
        Button("Activity", systemImage: "waveform.path.ecg") { phonePath.append(.activity) }
        Button("Settings", systemImage: "gearshape") { phonePath.append(.settings) }
        if let project = model.selectedProject {
          Divider()
          Button("Project Git", systemImage: "chevron.left.forwardslash.chevron.right") {
            phonePath.append(.projectGit(project.id))
          }
          .disabled(!model.isConnectedPhone)
          Button("Project settings", systemImage: "slider.horizontal.3") {
            model.sheet = .editProject(project)
          }
          Button(role: .destructive) {
            model.projectPendingDeletion = project
          } label: {
            Label("Delete project", systemImage: "trash")
          }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .accessibilityLabel("More project actions")
    }

    @ViewBuilder private func projectGitDestination(_ id: UUID) -> some View {
      if let project = model.library.activeProjects.first(where: { $0.id == id }) {
        ScrollView {
          PhoneGitControls(project: project, taskID: nil).padding(16)
        }
        .navigationTitle("Project Git")
        .navigationBarTitleDisplayMode(.inline)
      } else {
        ContentUnavailableView("Project unavailable", systemImage: "folder.questionmark")
          .navigationTitle("Project Git")
      }
    }
  #endif

  private func libraryUnavailable(error: String) -> some View {
    ContentUnavailableView {
      Label("Your library couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark")
    } description: {
      VStack(alignment: .leading, spacing: 4) {
        Text(error)
        Text("Your existing files have not been replaced.")
      }
    } actions: {
      Button("Try again") {
        Task {
          model.loadError = nil
          await model.load()
        }
      }
    }
  }

  private var phoneProjectTitle: String {
    model.selectedProject?.name ?? "Projects"
  }
}

private enum PhoneDestination: Hashable {
  case board
  case workspaceTasks(WorkspaceTaskPreset)
  case task(UUID)
  case projectGit(UUID)
  case activity
  case connection
  case settings
}

struct ProjectSidebar: View {
  @Environment(AppModel.self) private var model
  @Binding var settingsInitialTab: AppSettingsTab
  var onOpen: (() -> Void)?
  var onOpenWorkspace: ((WorkspaceTaskPreset) -> Void)?
  var body: some View {
    List {
      Section {
        #if os(macOS)
          CodexUsagePanel()
        #else
          CodexUsageSummary(
            snapshot: model.codexUsageSnapshot,
            status: model.codexUsageStatus,
            isStale: model.codexUsageIsStale)
        #endif
      } header: {
        Text("CODEX USAGE")
      }
      Section {
        ForEach(model.library.activeProjects) { project in
          let counts = model.library.sidebarCounts(for: project.id)
          ProjectSidebarProjectRow(
            project: project, counts: counts, isSelected: project.id == model.selectedProjectID
          ) {
            model.select(project.id)
            onOpen?()
          }
          .contextMenu {
            #if os(macOS)
              Button("Project settings…") { model.sheet = .editProject(project) }
            #else
              if model.isConnectedPhone {
                Button("Project settings…") { model.sheet = .editProject(project) }
              }
            #endif
            Button("Delete project…", role: .destructive) {
              model.projectPendingDeletion = project
            }
          }
          #if os(iOS)
            .swipeActions {
              Button(role: .destructive) {
                model.projectPendingDeletion = project
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          #endif
        }
        #if os(macOS)
          if !model.isConnectedPhone {
            Button {
              model.sheet = .newProject
            } label: {
              Label("New project", systemImage: "plus.circle").padding(.vertical, 6)
            }
            .buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityIdentifier(
              "new-project")
          }
        #endif
      } header: {
        Text("YOUR PROJECTS")
      }
      #if os(iOS)
        Section("Workspace") {
          ForEach([
            WorkspaceTaskPreset.favorites,
            .planApproved,
            .building,
            .reviewing,
            .recentlyCompleted,
          ]) { preset in
            Button {
              model.showWorkspaceTasks(preset)
              onOpenWorkspace?(preset)
            } label: {
              Label(preset.title, systemImage: preset.symbol)
            }
            .accessibilityIdentifier("workspace-\(preset.rawValue)-navigation")
          }
        }
      #endif
      Section {
        Button {
          model.sheet = .deletedProjects
        } label: {
          Label("Deleted Projects", systemImage: "trash")
        }
        .accessibilityIdentifier("deleted-projects-navigation")
      }
      #if os(macOS)
        Section("Workspace") {
          ForEach(WorkspaceTaskPreset.allCases) { preset in
            Button {
              model.showWorkspaceTasks(preset)
            } label: {
              Label(preset.title, systemImage: preset.symbol)
                .foregroundStyle(model.workspaceTaskView == preset ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)
            .listRowBackground(
              model.workspaceTaskView == preset
                ? Color.accentColor.opacity(0.1)
                : .clear
            )
            .accessibilityIdentifier("workspace-\(preset.rawValue)-navigation")
          }
          Button {
            model.workspaceTaskView = nil
            model.selectedTaskID = nil
            model.showActivity.toggle()
          } label: {
            Label("Agent activity", systemImage: "waveform.path.ecg")
          }.buttonStyle(.plain)
          Button {
            settingsInitialTab = .general
            model.sheet = .settings
          } label: {
            Label("Settings & backups", systemImage: "gearshape")
          }.buttonStyle(.plain)
        }
      #endif
      if model.isPreview {
        Text("PREVIEW · No real automation").stageFont(.caption).foregroundStyle(.orange)
      }
    }
    #if os(iOS)
      // SwiftUI's UICollectionView-backed List can apply a stale row diff when a
      // project is removed after a swipe action. Recreate the list on membership
      // changes so UIKit starts from the current active-project snapshot.
      .id(model.library.activeProjects.map { $0.id.uuidString }.joined(separator: ","))
      .refreshable {
        await model.refreshFromMac(manual: true, forceFullSnapshot: true)
      }
    #endif
    #if os(macOS)
      .listStyle(.sidebar).navigationTitle("StageChase")
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 5) {
          Label("Your work, in motion", systemImage: "square.stack.3d.up").stageFont(
            .caption, weight: .medium)
          Text("\(model.library.activeProjects.count) projects · stored on this Mac").stageFont(
            .caption2
          )
          .foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
      }
    #else
      .listStyle(.insetGrouped)
    #endif
  }
}

struct DeletedProjectsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var restoringID: UUID?

  var body: some View {
    NavigationStack {
      Group {
        if model.library.deletedProjects.isEmpty {
          ContentUnavailableView(
            "No deleted projects", systemImage: "trash",
            description: Text("Projects you delete will appear here so you can restore them."))
        } else {
          List(model.library.deletedProjects) { project in
            let taskCount = model.library.items(in: project.id, completed: true).count
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(project.name).stageFont(.body, weight: .medium)
                Text("\(taskCount) \(taskCount == 1 ? "task" : "tasks") retained")
                  .stageFont(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Button("Restore") {
                restoringID = project.id
                Task {
                  await model.setProjectDeleted(project, deleted: false)
                  restoringID = nil
                }
              }
              .disabled(restoringID != nil)
              .accessibilityLabel("Restore \(project.name)")
              .accessibilityIdentifier("restore-project-\(project.id.uuidString)")
            }
            .padding(.vertical, 4)
          }
        }
      }
      .navigationTitle("Deleted Projects")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    #if os(macOS)
      .frame(width: 500, height: 400)
    #endif
  }
}

struct WorkspaceTasksView: View {
  @Environment(AppModel.self) private var model
  @State private var editingTaskID: UUID?
  let preset: WorkspaceTaskPreset
  var onOpenTask: ((UUID) -> Void)?
  private let columnLimit = 3

  private var sourceTasks: [WorkItem] {
    switch preset {
    case .highPriorityModel:
      model.library.tasks.filter { !$0.completed && $0.modelTag == .high }
    case .mediumPriorityModel:
      model.library.tasks.filter { !$0.completed && $0.modelTag == .medium }
    case .favorites:
      model.library.tasks.filter { !$0.completed && $0.isFavorite }
    case .planApproved:
      model.library.recentTasks.filter { !$0.completed && $0.status == .planApproved }
    case .building:
      model.library.recentTasks.filter { !$0.completed && $0.status == .building }
    case .inProgress:
      model.library.recentTasks.filter { item in
        !item.completed && [.planning, .building].contains(item.status) && hasActiveRun(item)
      }
    case .reviewing:
      model.library.recentTasks.filter {
        guard !$0.completed else { return false }
        if $0.status == .reviewing { return true }
        guard $0.status == .planning, $0.hasSavedPlan else { return false }
        return !hasActiveRun($0)
      }
    case .recentlyCompleted:
      model.library.recentlyCompletedTasks
    }
  }

  private func hasActiveRun(_ item: WorkItem) -> Bool {
    guard let run = model.library.latestRun(for: item.id) else { return false }
    return [.queued, .running].contains(run.status)
  }

  private struct DayGroup: Identifiable {
    let day: Date
    let entries: [(item: WorkItem, project: Project)]

    var id: Date { day }
  }

  private var recentItems: [(item: WorkItem, project: Project)] {
    sourceTasks.compactMap { item in
      guard let project = model.library.activeProjects.first(where: { $0.id == item.projectID })
      else {
        return nil
      }
      return (item, project)
    }
    .filter { entry in
      model.search.isEmpty
        || entry.item.title.localizedCaseInsensitiveContains(model.search)
        || entry.item.notes.localizedCaseInsensitiveContains(model.search)
        || entry.project.name.localizedCaseInsensitiveContains(model.search)
    }
  }

  private func activityDate(for item: WorkItem) -> Date {
    preset == .recentlyCompleted ? (item.completedAt ?? item.updatedAt) : item.updatedAt
  }

  private var dayGroups: [DayGroup] {
    let calendar = Calendar.autoupdatingCurrent
    let entriesByDay = Dictionary(grouping: recentItems) {
      calendar.startOfDay(for: activityDate(for: $0.item))
    }
    return entriesByDay.keys.sorted(by: >).compactMap { day in
      guard let entries = entriesByDay[day] else { return nil }
      return DayGroup(day: day, entries: entries)
    }
  }

  private func dayTitle(for day: Date) -> String {
    let calendar = Calendar.autoupdatingCurrent
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(date: .complete, time: .omitted)
  }

  private func columns(for entries: [(item: WorkItem, project: Project)])
    -> [[(item: WorkItem, project: Project)]]
  {
    let ordered = entries.sorted {
      let leftDate = activityDate(for: $0.item)
      let rightDate = activityDate(for: $1.item)
      if leftDate != rightDate {
        return leftDate < rightDate
      }
      return $0.item.id.uuidString < $1.item.id.uuidString
    }
    guard !ordered.isEmpty else { return [] }

    let heights = ordered.map(estimatedCardHeight)
    #if os(iOS)
      let numberOfColumns = 1
    #else
      let numberOfColumns = min(columnLimit, ordered.count)
    #endif
    var result: [[(item: WorkItem, project: Project)]] = []
    var start = 0

    for columnIndex in 0..<numberOfColumns {
      let remainingColumns = numberOfColumns - columnIndex
      if remainingColumns == 1 {
        result.append(Array(ordered[start...]))
        break
      }

      let remainingHeight = heights[start...].reduce(0, +)
      let targetHeight = remainingHeight / Double(remainingColumns)
      let lastEnd = ordered.count - (remainingColumns - 1)
      var end = start
      var columnHeight = 0.0

      while end < lastEnd {
        let nextHeight = heights[end]
        if end > start,
          abs(targetHeight - columnHeight) <= abs(targetHeight - (columnHeight + nextHeight))
        {
          break
        }
        columnHeight += nextHeight
        end += 1
      }

      result.append(Array(ordered[start..<end]))
      start = end
    }

    #if os(macOS)
      // Keep three equal-width slots even when this day has only one or two cards.
      while result.count < columnLimit {
        result.append([])
      }
    #endif
    return result
  }

  private func estimatedCardHeight(_ entry: (item: WorkItem, project: Project)) -> Double {
    let titleLines = max(1, (entry.item.title.count + 34) / 35)
    let noteLines =
      entry.item.notes.isEmpty
      ? 0
      : min(3, max(1, (entry.item.notes.count + 45) / 46))
    let hasLiveActivity =
      model.library.latestRun(for: entry.item.id).map {
        $0.status == .running && $0.liveState == .busy
      } ?? false

    // Approximate card content height so sequential cards split into balanced columns.
    return 132 + Double(titleLines - 1) * 19 + Double(noteLines) * 16
      + (entry.item.completed ? 17 : 0) + (hasLiveActivity ? 17 : 0)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(preset.title).stageFont(.largeTitle, weight: .bold)
        Spacer()
        Text("\(recentItems.count)").stageFont(.caption).monospacedDigit()
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 18)

      if recentItems.isEmpty {
        ContentUnavailableView(
          emptyTitle,
          systemImage: preset.symbol,
          description: Text(emptyDescription))
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(dayGroups) { group in
              VStack(alignment: .leading, spacing: 12) {
                let dayColumns = columns(for: group.entries)
                Text(dayTitle(for: group.day))
                  .stageFont(.title2, weight: .semibold)
                  .padding(.leading, 2)

                HStack(alignment: .top, spacing: 14) {
                  ForEach(Array(dayColumns.enumerated()), id: \.offset) { column in
                    LazyVStack(alignment: .leading, spacing: 14) {
                      ForEach(column.element, id: \.item.id) { entry in
                        TaskCard(
                          item: entry.item,
                          editingTaskID: $editingTaskID,
                          onOpenTask: { taskID in
                            if let onOpenTask {
                              onOpenTask(taskID)
                            } else {
                              model.selectedTaskID = taskID
                            }
                            model.showActivity = false
                          },
                          scope: .recentTasks,
                          projectName: entry.project.name)
                      }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                  }
                }
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 4)
          .padding(.bottom, 20)
        }
        .scrollIndicators(.automatic)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var emptyTitle: String {
    switch preset {
    case .highPriorityModel: "No High model tasks"
    case .mediumPriorityModel: "No Medium model tasks"
    case .favorites: "No favorite tasks"
    case .planApproved:
      model.search.isEmpty ? "No approved plans ready to start" : "No matching tasks"
    case .building:
      model.search.isEmpty ? "No tasks being built" : "No matching tasks"
    case .inProgress:
      model.search.isEmpty ? "No active planning or build runs" : "No matching tasks"
    case .reviewing:
      model.search.isEmpty ? "Nothing to review" : "No matching tasks"
    case .recentlyCompleted:
      model.search.isEmpty ? "No recently completed tasks" : "No matching tasks"
    }
  }

  private var emptyDescription: String {
    switch preset {
    case .highPriorityModel: "Tasks tagged High across your projects appear here."
    case .mediumPriorityModel: "Tasks tagged Medium across your projects appear here."
    case .favorites: "Your favorite tasks across projects appear here."
    case .planApproved: "Plans approved for implementation across your projects appear here."
    case .building: "Unfinished tasks with Building status across your projects appear here."
    case .inProgress: "Tasks with an active planning or implementation run appear here."
    case .reviewing: "Plans awaiting approval and finished code changes appear here."
    case .recentlyCompleted: "Completed tasks are grouped by the date they were completed."
    }
  }
}

struct WelcomeView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    ContentUnavailableView {
      Label("Good work starts with a little clarity", systemImage: "square.stack.3d.up")
    } description: {
      Text(
        "Give each project its own space. Capture ideas, shape a plan, and move work forward with Codex."
      )
    } actions: {
      Button("Create your first project") { model.sheet = .newProject }.buttonStyle(
        .borderedProminent)
    }
  }
}

struct AppSettings: View {
  var initialTab: AppSettingsTab = .general
  @State private var selectedTab: AppSettingsTab

  init(initialTab: AppSettingsTab = .general) {
    self.initialTab = initialTab
    _selectedTab = State(initialValue: initialTab)
  }

  var body: some View {
    #if os(macOS)
      TabView(selection: $selectedTab) {
        GeneralSettingsForm().tabItem { Label("General", systemImage: "gearshape") }
          .tag(AppSettingsTab.general)
        SyncConnectionView().tabItem { Label("Connection", systemImage: "network") }
          .tag(AppSettingsTab.connection)
      }
      .frame(minWidth: 640, minHeight: 680)
    #else
      GeneralSettingsForm()
    #endif
  }
}

enum AppSettingsTab: Hashable {
  case general
  case connection
}

#if os(macOS)
  private func loopbackVerificationColor(_ state: LoopbackVerificationState) -> Color {
    switch state.presentationColor {
    case .neutral: .secondary
    case .green: .green
    case .red: .red
    }
  }

  private func loopbackVerificationLabel(_ state: LoopbackVerificationState) -> String {
    switch state {
    case .inactive: "Local sync is off"
    case .checking: "Checking local sync port; open Connection settings for details"
    case .verified: "Local sync port verified; open Connection settings for details"
    case .failed: "Local sync port verification failed; open Connection settings for details"
    }
  }
#endif

private struct GeneralSettingsForm: View {
  @Environment(AppModel.self) private var model
  @AppStorage("textScale") private var textScale = 1.0
  @AppStorage("codexExecutable") private var executable = ""
  @State private var document: LibraryDocument?
  @State private var exporting = false
  @State private var importing = false
  var body: some View {
    Form {
      Section("StageChase") {
        Text("A home for every project.").stageFont(.headline)
        Text(
          model.isConnectedPhone
            ? "This phone is showing a cached copy of the paired Mac library. Changes sync while the Mac app is open on the same Wi-Fi network. Codex still runs only on Mac after confirmation."
            : "Projects and tasks are saved in a versioned SQLite library on this device. Sections and task statuses stay separate from Codex run history."
        ).foregroundStyle(.secondary)
      }
      #if os(macOS)
        Section("Appearance") {
          Slider(value: $textScale, in: 0.85...1.4, step: 0.05) { Text("Text size") }
          Button("Reset text size") { textScale = 1 }
          Text("Keyboard: ⌘+ larger · ⌘− smaller · ⌘0 reset").stageFont(.caption).foregroundStyle(
            .secondary)
        }
        Section("Codex runner") {
          Toggle(
            "Automatically invoke Codex",
            isOn: Binding(
              get: { model.autoInvokeCodex },
              set: { model.setAutoInvokeCodex($0) })
          )
          Text(
            model.autoInvokeCodex
              ? "Confirmed moves into Planning or Implementing can start Codex automatically when project automation is also enabled. Task status stays separate from section."
              : "Section changes never start Codex. Task details can launch a prompt in Codex Desktop."
          ).stageFont(.caption).foregroundStyle(.secondary)
          TextField("Codex executable (automatic if empty)", text: $executable)
          Text(model.runnerMessage).stageFont(.callout).foregroundStyle(.secondary)
          Button("Check Codex connection") { Task { await model.runner?.checkConnection() } }
          Text(
            "Uses a dedicated app-server connection and your existing Codex sign-in. Does not read or display authentication secrets."
          ).stageFont(.caption).foregroundStyle(.secondary)
        }
        Section("Default Codex model") {
          CodexModelFields(
            configuration: Binding(
              get: { model.globalModelConfiguration },
              set: { model.setGlobalModelConfiguration($0) }),
            catalog: model.modelCatalog)
          if let error = model.modelConfigurationError ?? model.modelCatalogError {
            Text(error).stageFont(.caption).foregroundStyle(.orange)
          }
          HStack {
            if model.modelCatalogLoading { ProgressView().controlSize(.small) }
            Spacer()
            Button("Reset to Latest Luna · High") { model.resetGlobalModelConfiguration() }
          }
          Text(
            "Applies to StageChase on this Mac. Project and task settings can override it. Global settings are not included in exported library backups."
          )
          .stageFont(.caption).foregroundStyle(.secondary)
        }
        Section("Plan format prompt") {
          Text(
            "StageChase adds this guidance to future planning runs on this Mac. It does not change saved plans or implementation runs."
          ).stageFont(.callout).foregroundStyle(.secondary)
          TextEditor(
            text: Binding(
              get: { model.planFormatPrompt },
              set: { model.setPlanFormatPrompt($0) })
          )
          .font(.body)
          .frame(minHeight: 220, maxHeight: 340)
          .accessibilityLabel("Plan format prompt")
          if let error = model.planFormatPromptError {
            Text(error).stageFont(.caption).foregroundStyle(.orange)
          }
          HStack {
            Text("Limited to \(AppModel.maximumPlanFormatPromptCharacters) characters.")
              .stageFont(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Reset to default") { model.resetPlanFormatPrompt() }
          }
        }
      #endif
      Section("Backups") {
        Button(
          model.isConnectedPhone ? "Export on-device library…" : "Export library…",
          systemImage: "square.and.arrow.up"
        ) {
          Task {
            if let data = await model.exportData() {
              document = LibraryDocument(data: data)
              exporting = true
            }
          }
        }
        if !model.isConnectedPhone {
          Button("Restore into an empty library…", systemImage: "square.and.arrow.down") {
            importing = true
          }
        }
        Text(
          model.isConnectedPhone
            ? "Your original on-device library stays separate from the Mac copy. Restore is unavailable while paired."
            : "Backups include attached images as separate files. Restore never overwrites existing projects, and older JSON-only backups remain supported."
        ).stageFont(.caption).foregroundStyle(.secondary)
      }
    }.formStyle(.grouped)
      #if os(macOS)
        .frame(width: 600, height: 760)
      #endif
      .fileExporter(
        isPresented: $exporting, document: document, contentType: .stageChaseBackup,
        defaultFilename: "StageChase-backup"
      ) { result in
        if case .failure(let error) = result { model.error = error.localizedDescription }
      }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.stageChaseBackup, .json]) {
        result in
        switch result {
        case .success(let url): Task { await model.restore(url) }
        case .failure(let error): model.error = error.localizedDescription
        }
      }
  }

}

private struct ProjectSidebarProjectRow: View {
  @Environment(AppModel.self) private var model
  let project: Project
  let counts: ProjectSidebarCounts
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 7) {
        Image(systemName: "square.stack.3d.up.fill")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .padding(.top, 3)
        Text(project.name).stageFont(.body, weight: .medium).foregroundStyle(.primary)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 4) {
          SidebarCountBadge(
            value: "\(counts.total)", color: .secondary,
            accessibilityLabel: "\(counts.total) items")
          SidebarCountBadge(
            value: "\(counts.planReview)",
            color: TaskStatus.planApproved.badgeStyle.color.swiftUIColor,
            accessibilityLabel: "\(counts.planReview) ready for plan review")
          SidebarCountBadge(
            value: "\(counts.codeReview)",
            color: TaskStatus.reviewing.badgeStyle.color.swiftUIColor,
            accessibilityLabel: "\(counts.codeReview) ready for code review")
          ProjectSidebarGitStatus(projectID: project.id)
        }
      }
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(project.name), \(counts.total) items, "
        + "\(counts.planReview) ready for plan review, "
        + "\(counts.codeReview) ready for code review, "
        + "\(modelGitAccessibilityDescription)"
    )
    .listRowBackground(isSelected ? Color.accentColor.opacity(0.1) : .clear)
  }

  private var modelGitAccessibilityDescription: String {
    #if os(macOS)
      if let status = model.gitStatuses[project.id] {
        return status.hasChanges ? "\(status.changedFileCount) Git changes" : "Git clean"
      }
    #else
      let key = "\(project.id.uuidString):project"
      if let status = model.phoneGitStatuses[key] {
        return status.hasChanges ? "\(status.changedFileCount) Git changes" : "Git clean"
      }
    #endif
    return "Git status dash"
  }
}

private struct SidebarCountBadge: View {
  let value: String
  let color: Color
  let accessibilityLabel: String

  var body: some View {
    CompactCountBadge(value: value, color: color, accessibilityLabel: accessibilityLabel)
  }
}

private struct ProjectSidebarGitStatus: View {
  @Environment(AppModel.self) private var model
  let projectID: UUID

  var body: some View {
    Group {
      #if os(macOS)
        if let status = model.gitStatuses[projectID] {
          macGitBadge(status)
        } else {
          macGitBadge(nil)
        }
      #else
        let key = "\(projectID.uuidString):project"
        if let status = model.phoneGitStatuses[key] {
          badge(status)
        } else {
          badge(nil)
        }
      #endif
    }
    .task(id: projectID) {
      #if os(macOS)
        await model.refreshGitStatus(projectID: projectID)
      #else
        await model.refreshPhoneGitStatus(projectID: projectID)
      #endif
    }
  }

  @ViewBuilder
  private func badge(_ status: SyncGitStatus?) -> some View {
    if let status {
      CompactCountBadge(
        value: "\(status.changedFileCount)",
        color: status.hasChanges ? Color.orange : .secondary,
        accessibilityLabel: status.hasChanges
          ? "\(status.changedFileCount) Git changes" : "Git clean",
        symbol: status.hasChanges ? "circle.fill" : nil
      )
    } else {
      CompactCountBadge(value: "-", color: .secondary, accessibilityLabel: "Git status dash")
    }
  }

  #if os(macOS)
    @ViewBuilder
    private func macGitBadge(_ status: GitRepositoryStatus?) -> some View {
      if let status {
        CompactCountBadge(
          value: "\(status.changedFileCount)",
          color: status.hasChanges ? Color.orange : .secondary,
          accessibilityLabel: status.hasChanges
            ? "\(status.changedFileCount) Git changes" : "Git clean",
          symbol: status.hasChanges ? "circle.fill" : nil
        )
      } else {
        CompactCountBadge(value: "-", color: .secondary, accessibilityLabel: "Git status dash")
      }
    }
  #endif
}
