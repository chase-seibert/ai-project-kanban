import SwiftUI
import UniformTypeIdentifiers

extension WorkflowSection {
  var color: Color {
    switch self {
    case .inbox: .secondary
    case .planning: .purple
    case .implementing: .orange
    }
  }
}
enum Palette {
  static var canvas: Color {
    #if os(macOS)
      Color(nsColor: .windowBackgroundColor)
    #else
      Color(uiColor: .systemGroupedBackground)
    #endif
  }
  static var card: Color {
    #if os(macOS)
      Color(nsColor: .controlBackgroundColor)
    #else
      Color(uiColor: .secondarySystemGroupedBackground)
    #endif
  }
}

private struct EditingTitleFramePreferenceKey: PreferenceKey {
  static let defaultValue: CGRect = .null

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    let next = nextValue()
    if !next.isNull { value = next }
  }
}

struct BoardView: View {
  @Environment(AppModel.self) private var model
  var onOpenTask: ((UUID) -> Void)?
  @State private var focusedStage: WorkflowSection? = .inbox
  @State private var editingTaskID: UUID?
  @State private var editingTitleFrame: CGRect = .null
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      #if os(macOS)
        BoardHeader()
      #else
        TaskQuickFilterBar()
          .padding(.horizontal, 20)
          .padding(.top, 8)
          .padding(.bottom, 8)
      #endif
      #if os(macOS)
        GeometryReader { geometry in
          HStack(alignment: .top, spacing: 14) {
            ForEach(WorkflowSection.allCases) { section in
              BoardLane(section: section, editingTaskID: $editingTaskID, onOpenTask: onOpenTask)
                .frame(
                  maxWidth: .infinity, maxHeight: .infinity, alignment: .top
                ).id(section)
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
          .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
      #else
        GeometryReader { geometry in
          TabView(
            selection: Binding(
              get: { focusedStage ?? .inbox },
              set: {
                focusedStage = $0
                model.boardFocusedStage = $0
              })
          ) {
            ForEach(WorkflowSection.allCases) { section in
              BoardLane(section: section, editingTaskID: $editingTaskID, onOpenTask: onOpenTask)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 4)
                .background(Palette.canvas)
                .tabItem { Label(section.title, systemImage: section.symbol) }
                .tag(section)
                .accessibilityIdentifier("board-section-\(section.rawValue)")
            }
          }
          .onChange(of: model.boardFocusedStage) { _, value in focusedStage = value }
          .toolbarBackground(.visible, for: .tabBar)
          .background(Palette.canvas.ignoresSafeArea())
        }
      #endif
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Palette.canvas)
    .onAppear { focusedStage = model.boardFocusedStage }
    #if os(macOS)
      .coordinateSpace(name: "taskBoard")
      .onPreferenceChange(EditingTitleFramePreferenceKey.self) { editingTitleFrame = $0 }
      .simultaneousGesture(
        SpatialTapGesture(coordinateSpace: .named("taskBoard")).onEnded { value in
          guard editingTaskID != nil, !editingTitleFrame.contains(value.location) else { return }
          editingTaskID = nil
        }
      )
    #endif
    #if os(macOS)
      .background(BoardKeyboardMonitor(model: model))
      .confirmationDialog(
        "Delete this task and its run history?",
        isPresented: Binding(
          get: { model.taskPendingDeletionID != nil },
          set: { if !$0 { model.taskPendingDeletionID = nil } }),
        titleVisibility: .visible
      ) {
        Button("Delete task", role: .destructive) {
          guard let taskID = model.taskPendingDeletionID,
            let item = model.library.tasks.first(where: { $0.id == taskID })
          else { return }
          Task {
            if await model.perform(.deleteTask(item.id, expectedRevision: item.revision)) {
              model.selectedTaskID = nil
              model.boardSelectedTaskID = nil
            }
            model.taskPendingDeletionID = nil
          }
        }.keyboardShortcut(.defaultAction)
      }
    #endif
  }
}

struct BoardHeader: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      #if os(macOS)
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 5) {
            Text(model.selectedProject?.name ?? "Your projects").stageFont(
              .largeTitle, weight: .bold)
          }
          Spacer()
          Text("\(model.library.items(in: model.selectedProjectID ?? UUID()).count) open")
            .stageFont(.subheadline).foregroundStyle(.secondary)
          Button("Add task", systemImage: "plus") {
            model.sheet = .newTask(model.boardFocusedStage)
          }
          .buttonStyle(.borderedProminent).tint(.blue)
          .disabled(model.selectedProject == nil)
          .help("Add task in the focused section (⌘T)")
          .accessibilityIdentifier("project-add-task")
        }
        if let project = model.selectedProject {
          ProjectHeaderControls(project: project)
        }
        TaskQuickFilterBar()
      #endif
      #if os(iOS)
        HStack(spacing: 8) {
          Image(
            systemName: automaticInvocationEnabled ? "sparkles" : "pause.circle"
          )
          .foregroundStyle(automaticInvocationEnabled ? .purple : .secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text(automationTitle).stageFont(.subheadline, weight: .medium)
            #if os(iOS)
              Text(currentPhoneSubtitle).stageFont(.caption).foregroundStyle(.secondary)
            #else
              Text(boardSubtitle).stageFont(.caption).foregroundStyle(.secondary)
            #endif
          }
          Spacer(minLength: 6)
          #if os(iOS)
            Button {
              Task { await model.refreshFromMac(manual: true) }
            } label: {
              if model.syncClient.isSyncing {
                ProgressView().controlSize(.small)
              } else {
                Label("Refresh", systemImage: "arrow.clockwise")
              }
            }
            .buttonStyle(.bordered)
            .disabled(
              !model.isConnectedPhone || model.syncClient.isSyncing
                || model.syncClient.hasUnsavedEndpoint
            )
            .accessibilityIdentifier("board-refresh-from-mac")
          #endif
          if !model.isConnectedPhone {
            Button {
              if let project = model.selectedProject { model.sheet = .editProject(project) }
            } label: {
              Image(systemName: "slider.horizontal.3")
            }.buttonStyle(.borderless).help("Project settings")
          }
        }.padding(12).background(Palette.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        #if os(iOS)
          if model.isConnectedPhone {
            Text(model.syncClient.lastResultMessage).stageFont(.caption).foregroundStyle(.secondary)
            if let error = model.syncClient.error {
              Text(error).stageFont(.caption).foregroundStyle(.orange)
            }
          }
        #endif
        #if os(iOS)
          if model.isConnectedPhone, let project = model.selectedProject {
            PhoneGitControls(project: project, taskID: nil)
          }
        #endif
      #endif
    }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
  }
  var automationTitle: String {
    #if os(iOS)
      "Local board · Codex runs on your Mac"
    #else
      if !model.activeRuns.isEmpty {
        "\(model.activeRuns.count) agent run\(model.activeRuns.count == 1 ? "" : "s") active"
      } else {
        automaticInvocationEnabled
          ? "Codex is ready when you are" : "Manual board · Codex is off"
      }
    #endif
  }
  private var boardSubtitle: String {
    if model.autoInvokeCodex && model.selectedProject?.automationEnabled == true {
      "Confirmed moves into Planning or Implementing can invoke Codex. Status stays visible on each task."
    } else {
      "Move tasks between sections. Launch a task or plan in Codex Desktop from task details."
    }
  }
  private var automaticInvocationEnabled: Bool {
    model.autoInvokeCodex && model.selectedProject?.automationEnabled == true
  }
  private var currentPhoneSubtitle: String {
    #if os(iOS)
      model.isConnectedPhone
        ? "Mac library · \(model.syncClient.status)"
        : "On-device library · Mac sync not connected"
    #else
      ""
    #endif
  }
}

struct TaskQuickFilterBar: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(TaskBoardFilter.allCases) { filter in
          Button {
            model.boardFilter = filter
          } label: {
            Group {
              if let symbol = filter.symbol {
                Label(filter.title, systemImage: symbol)
              } else {
                Text(filter.title)
              }
            }
            #if os(iOS)
              .font(.subheadline.weight(model.boardFilter == filter ? .semibold : .regular))
              .padding(.horizontal, 14)
              .frame(minHeight: 44)
              .foregroundStyle(model.boardFilter == filter ? Color.accentColor : .secondary)
              .background(
                model.boardFilter == filter ? Color.accentColor.opacity(0.12) : Palette.card,
                in: Capsule())
            #endif
          }
          #if os(macOS)
            .buttonStyle(.bordered)
            .tint(model.boardFilter == filter ? .accentColor : .secondary)
          #else
            .buttonStyle(.plain)
          #endif
          .accessibilityAddTraits(model.boardFilter == filter ? .isSelected : [])
          .accessibilityIdentifier("board-filter-\(filter.rawValue)")
        }
      }
    }
    .font(.caption)
    .scrollIndicators(.hidden)
    .accessibilityLabel("Filter tasks")
  }
}

struct TaskModelTagMenu: View {
  @Environment(AppModel.self) private var model
  let item: WorkItem
  var body: some View {
    Menu {
      Button("None") { Task { await model.setModelTag(nil, for: item.id) } }
      ForEach(TaskModelTag.allCases) { tag in
        Button(tag.title) { Task { await model.setModelTag(tag, for: item.id) } }
      }
    } label: {
      Label(item.modelTag?.title ?? "Model tag", systemImage: "bolt")
        .stageFont(.caption, weight: .medium)
    }
    .accessibilityLabel("Model tag: \(item.modelTag?.title ?? "None")")
    .accessibilityIdentifier("task-model-tag-\(item.id.uuidString)")
  }
}

struct BoardLane: View {
  @Environment(AppModel.self) private var model
  let section: WorkflowSection
  @Binding var editingTaskID: UUID?
  var onOpenTask: ((UUID) -> Void)?
  @State private var draft = ""
  @State private var adding = false
  @State private var targeted = false
  @State private var saving = false
  @State private var captureError: String?
  @FocusState private var captureFocused: Bool
  private var visibleItems: [WorkItem] { model.items(section) }
  private var openItems: [WorkItem] { visibleItems.filter { !$0.completed } }
  private var planReviewCount: Int { openItems.filter { $0.status == .planApproved }.count }
  private var codeReviewCount: Int { openItems.filter { $0.status == .reviewing }.count }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: section.symbol).foregroundStyle(section.color)
        Text(section.title).stageFont(.headline)
        Text("\(visibleItems.count)").stageFont(.caption).monospacedDigit().foregroundStyle(
          .secondary
        )
        .padding(.horizontal, 7).padding(.vertical, 3).background(.quaternary, in: Capsule())
        if planReviewCount > 0 {
          CompactCountBadge(
            value: "\(planReviewCount)",
            color: TaskStatus.planApproved.badgeStyle.color.swiftUIColor,
            accessibilityLabel: "\(planReviewCount) plan review items in \(section.title)",
            symbol: TaskStatus.planApproved.badgeStyle.symbol)
        }
        if codeReviewCount > 0 {
          CompactCountBadge(
            value: "\(codeReviewCount)",
            color: TaskStatus.reviewing.badgeStyle.color.swiftUIColor,
            accessibilityLabel: "\(codeReviewCount) code review items in \(section.title)",
            symbol: TaskStatus.reviewing.badgeStyle.symbol)
        }
        Spacer(minLength: 0)
        #if os(macOS)
          Button {
            adding = true
            captureFocused = true
          } label: {
            Image(systemName: "plus")
          }
          .buttonStyle(.borderless).help("Add to \(section.title)").accessibilityLabel(
            "Add task to \(section.title)")
        #endif
      }
      #if os(macOS)
        Text(section.subtitle).stageFont(.caption).foregroundStyle(.secondary)
        Rectangle().fill(section.color.opacity(0.5)).frame(height: 2)
      #endif
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(visibleItems) { item in
            TaskCard(item: item, editingTaskID: $editingTaskID, onOpenTask: onOpenTask)
          }
          if visibleItems.isEmpty && !adding {
            VStack(spacing: 8) {
              Image(systemName: section.symbol).stageFont(.title2).foregroundStyle(
                section.color.opacity(0.65))
              #if os(macOS)
                Text(model.search.isEmpty ? "Room for what’s next" : "No matching tasks").stageFont(
                  .subheadline)
                Text(
                  model.search.isEmpty
                    ? "Use Add task to add a task to this section." : "Try another search."
                )
                .stageFont(.caption).foregroundStyle(.secondary)
              #else
                Text(hasActiveFilter ? "No matching tasks" : "Room for what’s next").font(.headline)
                Text(hasActiveFilter ? "Try clearing your filters." : section.subtitle)
                  .font(.subheadline).foregroundStyle(.secondary)
              #endif
              #if os(iOS)
                Button(hasActiveFilter ? "Clear filters" : "Add task") {
                  if hasActiveFilter {
                    model.boardFilter = .all
                    model.search = ""
                  } else {
                    model.sheet = .newTask(section)
                  }
                }
                .buttonStyle(.bordered).frame(minHeight: 44)
                .accessibilityIdentifier("board-empty-action")
              #endif
            }.frame(maxWidth: .infinity).padding(.vertical, 30)
          }
          #if os(macOS)
            if adding {
              VStack(alignment: .leading, spacing: 10) {
                TextField("What needs doing?", text: $draft, axis: .vertical)
                  .textFieldStyle(.plain).lineLimit(2...5).focused($captureFocused)
                  .onSubmit { save() }
                  .onChange(of: draft) { _, _ in captureError = nil }
                if let captureError {
                  Text(captureError).stageFont(.caption).foregroundStyle(.orange)
                }
                HStack {
                  Button("Cancel") {
                    adding = false
                    draft = ""
                  }.buttonStyle(.borderless)
                  Spacer()
                  Button(addButtonTitle) { save() }.buttonStyle(.borderedProminent).controlSize(
                    .small
                  )
                  .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
              }.padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(section.color.opacity(0.5)))
            } else {
              Button {
                adding = true
                captureFocused = true
              } label: {
                Label("Add task", systemImage: "plus").stageFont(.subheadline)
                  .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(
                    .horizontal, 6)
              }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(
                "Quick add to \(section.title)")
            }
          #endif
        }.padding(.bottom, 12)
      }
      #if os(iOS)
        .refreshable { await model.refreshFromMac(manual: true) }
        .contentMargins(.bottom, 88, for: .scrollContent)
      #endif
      .scrollIndicators(.hidden)
    }
    #if os(iOS)
      .padding(.horizontal, 16)
    #else
      .padding(14)
    #endif
    .frame(maxHeight: .infinity, alignment: .top)
    #if os(iOS)
      .background(Palette.canvas)
      .overlay {
        if targeted { RoundedRectangle(cornerRadius: 16).stroke(section.color, lineWidth: 2) }
      }
    #else
      .background(
        targeted ? section.color.opacity(0.12) : Palette.card.opacity(0.34),
        in: RoundedRectangle(cornerRadius: 16)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16).strokeBorder(
          targeted ? section.color : .primary.opacity(0.055), lineWidth: targeted ? 2 : 1)
      )
    #endif
    .dropDestination(for: String.self) { values, _ in
      guard let value = values.first, value.hasPrefix("stagechase-task:"),
        let id = UUID(uuidString: String(value.dropFirst("stagechase-task:".count))),
        let item = model.library.tasks.first(where: {
          $0.id == id && $0.projectID == model.selectedProjectID
        })
      else { return false }
      model.requestMove(item, to: section)
      return true
    } isTargeted: {
      targeted = $0
    }
  }
  private var hasActiveFilter: Bool { !model.search.isEmpty || model.boardFilter != .all }

  private var checklistTitles: [String]? {
    let lines = draft.split(whereSeparator: \.isNewline).map {
      String($0).trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    guard !lines.isEmpty else { return nil }
    let titles = lines.compactMap { Self.checklistTitle(from: $0) }
    return titles.count == lines.count ? titles : nil
  }
  private var addButtonTitle: String {
    guard let count = checklistTitles?.count, count > 1 else { return "Add task" }
    return "Add \(count) tasks"
  }
  private static func checklistTitle(from line: String) -> String? {
    let patterns = [
      #"^[-*+]\s+\[\s\]\s*(.+)$"#,
      #"^☐\s*(.+)$"#,
      #"^□\s*(.+)$"#,
    ]
    for pattern in patterns {
      guard let expression = try? NSRegularExpression(pattern: pattern),
        let match = expression.firstMatch(
          in: line, range: NSRange(line.startIndex..., in: line)),
        let titleRange = Range(match.range(at: 1), in: line)
      else { continue }
      let title = line[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
      if !title.isEmpty { return title }
    }
    return nil
  }
  private func save() {
    guard !saving, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let titles = checklistTitles ?? [draft]
    let requiresConfirmation =
      model.autoInvokeCodex
      && model.selectedProject?.automationEnabled == true
      && section != .inbox
    guard !(titles.count > 1 && requiresConfirmation) else {
      captureError =
        "Add this checklist in Inbox first. Moving tasks into \(section.title) will ask before starting Codex."
      return
    }
    saving = true
    captureError = nil
    Task {
      var savedCount = 0
      for title in titles {
        guard await model.addTask(title, section: section) else { break }
        savedCount += 1
      }
      if savedCount == titles.count {
        draft = ""
        captureFocused = true
      } else if titles.count > 1 && savedCount > 0 {
        draft = titles.dropFirst(savedCount).map { "- [ ] \($0)" }.joined(separator: "\n")
        captureError =
          model.error ?? "Some tasks could not be added. The remaining items are still here."
      }
      saving = false
    }
  }
}

enum TaskCardScope: Equatable {
  case board
  case recentTasks
}

struct TaskCard: View {
  @Environment(AppModel.self) private var model
  let item: WorkItem
  @Binding var editingTaskID: UUID?
  var onOpenTask: ((UUID) -> Void)?
  var scope = TaskCardScope.board
  var projectName: String?
  @State private var titleDraft = ""
  @State private var savingTitle = false
  @State private var titleSaveMessage: String?
  @FocusState private var titleFieldFocused: Bool

  private var isEditingTitle: Bool { editingTaskID == item.id }
  private var latestRun: AgentRun? { model.library.latestRun(for: item.id) }
  private var showsLiveActivity: Bool {
    guard let run = latestRun else { return false }
    return run.status == .running && run.liveState == .busy
  }

  var body: some View {
    Group {
      if isEditingTitle {
        cardContents
      } else {
        interactiveContents.contextMenu { taskContextMenu }
      }
    }
    .onChange(of: editingTaskID) { oldValue, newValue in
      if oldValue == item.id, newValue != item.id {
        resolveTitleEditing()
      } else if newValue == item.id {
        titleFieldFocused = true
      }
    }
    .onChange(of: titleFieldFocused) { _, isFocused in
      #if os(macOS)
        if !isFocused { resolveTitleEditing() }
      #endif
    }
  }

  @ViewBuilder private var interactiveContents: some View {
    if scope == .board {
      displayContents
        .draggable("stagechase-task:\(item.id.uuidString)")
        .dropDestination(for: String.self) { values, _ in
          guard let value = values.first, value.hasPrefix("stagechase-task:"),
            let id = UUID(uuidString: String(value.dropFirst("stagechase-task:".count))),
            let source = model.library.tasks.first(where: {
              $0.id == id && $0.projectID == item.projectID
            })
          else { return false }
          if source.section == item.section {
            Task {
              await model.perform(
                .reorder(id, before: item.id, expectedRevision: source.revision))
            }
          } else {
            model.requestMove(source, to: item.section)
          }
          return true
        }
    } else {
      displayContents
    }
  }

  @ViewBuilder private var displayContents: some View {
    #if os(iOS)
      phoneCardContents
    #else
      cardContents
    #endif
  }

  #if os(iOS)
    private var phoneCardContents: some View {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            if let projectName {
              Text(projectName).font(.caption).foregroundStyle(.secondary)
            }
            Text(item.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
              .strikethrough(item.completed)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary).padding(.top, 4).accessibilityHidden(true)
        }
        .frame(minHeight: 44, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
          TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { result in
            switch result {
            case .first: beginTitleEditing()
            case .second: openDetails()
            }
          }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.title)
        .accessibilityHint("Opens task details")
        .accessibilityAction { openDetails() }
        .accessibilityAction(named: "Edit title") { beginTitleEditing() }
        .accessibilityIdentifier("task-open-\(item.id.uuidString)")

        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            phoneCardStatus
            phoneCardMetadata
          }
          VStack(alignment: .leading, spacing: 0) {
            phoneCardStatus
            phoneCardMetadata
          }
        }
        if showsLiveActivity, let run = latestRun {
          HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(run.latestMessage ?? run.summary).font(.caption).lineLimit(1)
          }
          .foregroundStyle(.secondary)
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Codex is running. \(run.latestMessage ?? run.summary)")
        }
      }
      .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
      .accessibilityIdentifier("task-card-\(item.id.uuidString)")
    }

    private var phoneCardStatus: some View {
      TaskStatusMenu(item: item).frame(minHeight: 44, alignment: .leading)
    }

    private var phoneCardMetadata: some View {
      HStack(spacing: 8) {
        Text(item.shortID.map { "#\($0)" } ?? "ID pending")
        if item.isFavorite {
          Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel("Favorite")
        }
        if let tag = item.modelTag { Text(tag.title).accessibilityLabel("Model tag: \(tag.title)") }
        planIndicator
        if item.completed {
          Image(systemName: "checkmark.circle").accessibilityLabel("Completed by you")
        }
      }
      .font(.caption).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, minHeight: 28, alignment: .trailing)
      .contentShape(Rectangle())
      .onTapGesture { openDetails() }
    }
  #endif

  @ViewBuilder private var taskContextMenu: some View {
    Button("Edit title", systemImage: "pencil") { beginTitleEditing() }
    Divider()
    Button(
      item.isFavorite ? "Remove from favorites" : "Add to favorites",
      systemImage: item.isFavorite ? "star.slash" : "star"
    ) {
      Task { await model.setFavorite(!item.isFavorite, for: item.id) }
    }
    Section("Model tag") {
      ForEach(TaskModelTag.allCases) { tag in
        Button {
          Task { await model.setModelTag(tag, for: item.id) }
        } label: {
          if item.modelTag == tag {
            Label(tag.title, systemImage: "checkmark")
          } else {
            Text(tag.title)
          }
        }
      }
      Button {
        Task { await model.setModelTag(nil, for: item.id) }
      } label: {
        if item.modelTag == nil {
          Label("None", systemImage: "checkmark")
        } else {
          Text("None")
        }
      }
    }
    Divider()
    let ordered = model.library.items(in: item.projectID, section: item.section, completed: true)
      .filter { $0.priority == item.priority }
    if scope == .board,
      let index = ordered.firstIndex(where: { $0.id == item.id }), index > 0
    {
      Button("Move up in \(item.section.title)", systemImage: "arrow.up") {
        let previous = ordered[index - 1]
        Task {
          await model.perform(
            .reorder(item.id, before: previous.id, expectedRevision: item.revision))
        }
      }
    }
    if scope == .board,
      let index = ordered.firstIndex(where: { $0.id == item.id }),
      index + 1 < ordered.count
    {
      Button("Move down in \(item.section.title)", systemImage: "arrow.down") {
        let next = ordered[index + 1]
        Task {
          await model.perform(
            .reorder(next.id, before: item.id, expectedRevision: next.revision))
        }
      }
    }
    if scope == .board, !ordered.isEmpty { Divider() }
    ForEach(WorkflowSection.allCases.filter { $0 != item.section }) { stage in
      Button {
        model.requestMove(item, to: stage)
      } label: {
        Label("Move to \(stage.title)", systemImage: stage.symbol)
      }
    }
    Divider()
    Section("Change status") {
      ForEach(TaskStatus.allCases.filter(\.isManuallySelectable)) { status in
        Button {
          setStatus(status)
        } label: {
          Label(
            status.title,
            systemImage: status == item.status ? "checkmark.circle.fill" : status.badgeStyle.symbol)
        }
        .disabled(status == item.status)
      }
    }
    Divider()
    Button(item.completed ? "Reopen task" : "Mark complete", systemImage: "checkmark.circle") {
      Task {
        await model.perform(.complete(item.id, !item.completed, expectedRevision: item.revision))
      }
    }
  }

  private var cardContents: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(item.shortID.map { String($0) } ?? "ID pending")
          .stageFont(.caption, weight: .medium).foregroundStyle(.secondary)
        Spacer()
        HStack(spacing: 6) {
          if item.isFavorite {
            Image(systemName: "star.fill")
              .foregroundStyle(.yellow)
              .accessibilityLabel("Favorite")
          }
          if let modelTag = item.modelTag {
            Text(modelTag.title)
              .stageFont(.caption2, weight: .semibold)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background(.quaternary, in: Capsule())
              .accessibilityLabel("Model tag: \(modelTag.title)")
          }
        }
      }
      if let projectName {
        Text(projectName).stageFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
      if isEditingTitle {
        #if os(macOS)
          HStack(alignment: .top, spacing: 8) {
            TextField("Task title", text: $titleDraft, axis: .vertical)
              .textFieldStyle(.plain)
              .stageFont(.body, weight: .semibold)
              .foregroundStyle(.primary)
              .focused($titleFieldFocused)
              .disabled(savingTitle)
              .accessibilityLabel("Task title")
              .accessibilityHint("Changes save when focus leaves the title.")
              .frame(maxWidth: .infinity, alignment: .leading)
              .background {
                GeometryReader { geometry in
                  Color.clear.preference(
                    key: EditingTitleFramePreferenceKey.self,
                    value: geometry.frame(in: .named("taskBoard"))
                  )
                }
              }
            planIndicator
          }
          if let titleSaveMessage {
            HStack(spacing: 6) {
              Text(titleSaveMessage)
                .stageFont(.caption)
                .foregroundStyle(titleSaveMessage == "Couldn't save" ? .red : .secondary)
              if titleSaveMessage == "Couldn't save" {
                Button("Retry") { saveTitle() }
                  .buttonStyle(.borderless)
                  .disabled(savingTitle)
              }
            }
            .accessibilityElement(children: .combine)
          }
        #else
        HStack(spacing: 6) {
          TextField("Task title", text: $titleDraft, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .focused($titleFieldFocused)
            .disabled(savingTitle)
            .onSubmit { saveTitle() }
            .accessibilityLabel("Task title")
            .accessibilityHint("Changes save automatically. Press Return to finish editing.")
          #if os(iOS)
          Button {
            saveTitle()
          } label: {
            Image(systemName: "checkmark")
          }
          .buttonStyle(.borderless)
          .help("Save title (Return)")
          .accessibilityLabel("Save title")
          .disabled(savingTitle)
          #endif
          Button {
            cancelTitleEditing()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.borderless)
          .help("Cancel title edit (Escape)")
          .accessibilityLabel("Cancel title edit")
          .disabled(savingTitle)
        }
        #endif
      } else {
        #if os(iOS)
          HStack(alignment: .top, spacing: 8) {
            Text(item.title).stageFont(.body, weight: .semibold).foregroundStyle(.primary)
              .strikethrough(item.completed)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
              .gesture(
                TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { result in
                  switch result {
                  case .first: beginTitleEditing()
                  case .second: openDetails()
                  }
                }
              )
              .accessibilityLabel(
                "Open task details for \(item.title)\(projectName.map { ", \($0)" } ?? ""); double tap to edit title"
              )
            planIndicator
          }
        #else
          HStack(alignment: .top, spacing: 8) {
            Text(item.title).stageFont(.body, weight: .semibold).foregroundStyle(.primary)
              .strikethrough(item.completed)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
              .gesture(
                TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { result in
                  switch result {
                  case .first: beginTitleEditing()
                  case .second: openDetails()
                  }
                }
              )
              .help("Click to open task details; double-click to edit title")
              .accessibilityLabel(
                "Open task details for \(item.title)\(projectName.map { ", \($0)" } ?? ""); double-click to edit title"
              )
            planIndicator
          }
        #endif

        VStack(alignment: .leading, spacing: 10) {
          TaskStatusMenu(item: item)
          if !item.notes.isEmpty {
            Button {
              openDetails()
            } label: {
              Text(item.notes).stageFont(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
          if item.completed {
            Label("Completed by you", systemImage: "checkmark.circle.fill").stageFont(.caption)
              .foregroundStyle(.secondary)
          }
          if showsLiveActivity, let run = latestRun {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small).scaleEffect(0.72)
              Text(run.latestMessage ?? run.summary)
                .stageFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Codex is running. \(run.latestMessage ?? run.summary)")
          }
        }
      }
    }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12).stroke(
          model.boardSelectedTaskID == item.id || model.selectedTaskID == item.id
            ? Color.accentColor.opacity(0.65) : .primary.opacity(0.07))
      )
      .shadow(color: .black.opacity(0.035), radius: 3, y: 2)
      #if os(macOS)
        .onExitCommand { cancelTitleEditing() }
      #endif
  }

  @ViewBuilder private var planIndicator: some View {
    if item.hasSavedPlan {
      Image(systemName: "paperclip")
        .stageFont(.caption, weight: .medium)
        .foregroundStyle(Color.blue.opacity(0.72))
        .accessibilityLabel("Plan attached")
    }
  }

  private func priorityLabel(_ priority: TaskPriority) -> some View {
    Label("\(priority.rawValue) · \(priority.title)", systemImage: "flag.fill")
      .stageFont(.caption, weight: .semibold).foregroundStyle(.secondary)
      .accessibilityLabel("Priority: \(priority.title)")
  }

  private func openDetails() {
    #if os(macOS)
      editingTaskID = nil
      model.selectedTaskID = item.id
      if scope == .board {
        model.boardSelectedTaskID = item.id
        model.boardFocusedStage = item.section
      }
      onOpenTask?(item.id)
    #else
      onOpenTask?(item.id)
    #endif
  }

  private func setStatus(_ status: TaskStatus) {
    Task {
      await model.perform(.setStatus(item.id, status, expectedRevision: item.revision))
    }
  }

  private func beginTitleEditing() {
    titleDraft = item.title
    titleSaveMessage = nil
    editingTaskID = item.id
  }

  private func cancelTitleEditing() {
    guard !savingTitle else { return }
    titleSaveMessage = nil
    titleDraft = item.title
    if editingTaskID == item.id { editingTaskID = nil }
  }

  private func resolveTitleEditing() {
    guard !savingTitle else { return }
    let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      titleFieldFocused = true
      titleSaveMessage = "Give this task a title."
      return
    }
    guard title != item.title else {
      titleSaveMessage = nil
      titleDraft = item.title
      if editingTaskID == item.id { editingTaskID = nil }
      return
    }
    saveTitle()
  }

  private func saveTitle() {
    guard !savingTitle else { return }
    let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      model.error = "Give this task a title."
      titleSaveMessage = "Give this task a title."
      titleFieldFocused = true
      return
    }
    guard title != item.title else {
      titleSaveMessage = nil
      cancelTitleEditing()
      return
    }
    guard var updated = model.library.tasks.first(where: { $0.id == item.id }) else {
      model.error = "This task no longer exists."
      titleSaveMessage = "Couldn't save"
      return
    }
    updated.title = title
    savingTitle = true
    titleSaveMessage = "Saving…"
    Task {
      let saved = await model.perform(.editTask(updated, expectedRevision: updated.revision))
      savingTitle = false
      if saved {
        titleSaveMessage = nil
        if editingTaskID == item.id { editingTaskID = nil }
      } else {
        titleSaveMessage = "Couldn't save"
      }
    }
  }
}

struct TaskStatusBadge: View {
  let status: TaskStatus

  var body: some View {
    let style = status.badgeStyle
    let tint = style.color.swiftUIColor
    Label(status.title, systemImage: style.symbol)
      .stageFont(.caption, weight: .semibold)
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(tint.opacity(0.1), in: Capsule())
      .accessibilityLabel("Status: \(status.title)")
  }

}

struct CompactCountBadge: View {
  let value: String
  let color: Color
  let accessibilityLabel: String
  var symbol: String? = nil

  var body: some View {
    HStack(spacing: 3) {
      if let symbol {
        Image(systemName: symbol)
      }
      Text(value)
    }
    .font(.caption2.weight(.bold).monospacedDigit())
    .foregroundStyle(color)
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(color.opacity(0.12), in: Capsule())
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }
}

struct TaskStatusMenu: View {
  @Environment(AppModel.self) private var model
  let item: WorkItem

  var body: some View {
    Menu {
      ForEach(TaskStatus.allCases.filter(\.isManuallySelectable)) { status in
        Button {
          Task {
            await model.perform(.setStatus(item.id, status, expectedRevision: item.revision))
          }
        } label: {
          Label(
            status.title,
            systemImage: status == item.status
              ? "checkmark.circle.fill" : status.badgeStyle.symbol)
        }
        .disabled(status == item.status)
      }
    } label: {
      TaskStatusBadge(status: item.status)
        #if os(iOS)
          .padding(.vertical, 8)
          .contentShape(Rectangle())
        #else
          .contentShape(Capsule())
        #endif
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Change status, currently \(item.status.title)")
    .accessibilityHint("Choose a task status")
  }
}

struct RunBadge: View {
  let run: AgentRun
  var body: some View {
    Label(run.status.title, systemImage: symbol)
      .stageFont(.caption, weight: .medium).foregroundStyle(color)
      .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.09), in: Capsule())
  }
  var symbol: String {
    switch run.status {
    case .queued: "clock"
    case .readyForHandoff: "arrow.up.right.square"
    case .running: "sparkles"
    case .needsInput: "hand.raised"
    case .succeeded: "checkmark.circle"
    case .failed, .interrupted: "exclamationmark.circle"
    case .cancelled: "stop.circle"
    case .stale: "questionmark.circle"
    case .superseded: "arrow.uturn.forward"
    }
  }
  var color: Color {
    switch run.status {
    case .running: .purple
    case .needsInput, .interrupted: .orange
    case .superseded: .secondary
    case .failed: .red
    case .succeeded: .green
    default: .secondary
    }
  }
}

extension TaskStatusBadgeColor {
  var swiftUIColor: Color {
    switch self {
    case .secondary: .secondary
    case .purple: .purple
    case .blue: .blue
    case .indigo: .indigo
    case .orange: .orange
    case .yellow: .yellow
    case .red: .red
    case .green: .green
    }
  }
}
