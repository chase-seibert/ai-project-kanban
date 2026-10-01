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

struct BoardView: View {
  @Environment(AppModel.self) private var model
  @State private var focusedStage: WorkflowSection? = .inbox
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      BoardHeader()
      #if os(iOS)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(WorkflowSection.allCases) { stage in
              Button {
                withAnimation { focusedStage = stage }
                model.boardFocusedStage = stage
              } label: {
                Label(stage.title, systemImage: stage.symbol).stageFont(
                  .subheadline, weight: .semibold
                )
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(
                  focusedStage == stage ? stage.color.opacity(0.14) : .clear, in: Capsule())
              }.buttonStyle(.plain).foregroundStyle(
                focusedStage == stage ? stage.color : .secondary)
            }
          }.padding(.horizontal, 16)
        }.padding(.bottom, 12)
      #endif
      #if os(macOS)
        GeometryReader { geometry in
          HStack(alignment: .top, spacing: 14) {
            ForEach(WorkflowSection.allCases) { section in
              BoardLane(section: section).frame(
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
          let width = laneWidth(geometry.size.width)
          ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
              ForEach(WorkflowSection.allCases) { stage in
                BoardLane(section: stage).frame(
                  width: width, height: max(220, geometry.size.height - 20)
                ).id(stage)
              }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .frame(minWidth: geometry.size.width, alignment: .topLeading)
          }
          .scrollPosition(id: $focusedStage, anchor: .leading)
          .onChange(of: model.boardFocusedStage) { _, value in focusedStage = value }
          #if os(iOS)
            .scrollTargetBehavior(.viewAligned)
          #endif
        }
      #endif
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Palette.canvas)
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
  #if os(iOS)
    private func laneWidth(_ width: CGFloat) -> CGFloat {
      min(420, max(270, width - 48))
    }
  #endif
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
            Text("A little clarity. A lot of forward motion.").foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(model.library.items(in: model.selectedProjectID ?? UUID()).count) open tasks")
            .stageFont(.subheadline).foregroundStyle(.secondary).padding(.top, 10)
        }
      #endif
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
        if !model.isConnectedPhone {
          Button {
            if let project = model.selectedProject { model.sheet = .editProject(project) }
          } label: {
            Image(systemName: "slider.horizontal.3")
          }.buttonStyle(.borderless).help("Project settings")
        }
      }.padding(12).background(Palette.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
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

struct BoardLane: View {
  @Environment(AppModel.self) private var model
  let section: WorkflowSection
  @State private var draft = ""
  @State private var adding = false
  @State private var targeted = false
  @State private var saving = false
  @State private var captureError: String?
  @FocusState private var captureFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: section.symbol).foregroundStyle(section.color)
        Text(section.title).stageFont(.headline)
        Text("\(model.items(section).count)").stageFont(.caption).monospacedDigit().foregroundStyle(
          .secondary
        )
        .padding(.horizontal, 7).padding(.vertical, 3).background(.quaternary, in: Capsule())
        Spacer(minLength: 0)
        Button {
          adding = true
          captureFocused = true
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderless).help("Add to \(section.title)").accessibilityLabel(
          "Add task to \(section.title)")
      }
      Text(section.subtitle).stageFont(.caption).foregroundStyle(.secondary)
      Rectangle().fill(section.color.opacity(0.5)).frame(height: 2)
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(model.items(section)) { item in TaskCard(item: item) }
          if model.items(section).isEmpty && !adding {
            VStack(spacing: 8) {
              Image(systemName: section.symbol).stageFont(.title2).foregroundStyle(
                section.color.opacity(0.65))
              Text(model.search.isEmpty ? "Room for what’s next" : "No matching tasks").stageFont(
                .subheadline)
              Text(
                model.search.isEmpty ? "Drop a task here or add one below." : "Try another search."
              ).stageFont(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 30)
          }
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
        }.padding(.bottom, 12)
      }
      #if os(iOS)
        .refreshable { await model.refreshFromMac(manual: true) }
      #endif
      .scrollIndicators(.hidden)
    }
    .padding(14)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(
      targeted ? section.color.opacity(0.12) : Palette.card.opacity(0.34),
      in: RoundedRectangle(cornerRadius: 16)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16).strokeBorder(
        targeted ? section.color : .primary.opacity(0.055), lineWidth: targeted ? 2 : 1)
    )
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

struct TaskCard: View {
  @Environment(AppModel.self) private var model
  let item: WorkItem
  var body: some View {
    Button {
      model.markTaskChangesRead(item.id)
      #if os(macOS)
        model.selectedTaskID = item.id
        model.boardSelectedTaskID = item.id
        model.boardFocusedStage = item.section
      #else
        model.sheet = .task(item.id)
      #endif
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        if let change = model.unreadTaskChangeKind(for: item.id) {
          Label(change.badgeTitle, systemImage: "circle.fill")
            .stageFont(.caption, weight: .semibold)
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("unread-task-\(item.id.uuidString)")
        }
        if let priority = item.priority {
          Label("\(priority.rawValue) · \(priority.title)", systemImage: "flag.fill")
            .stageFont(.caption, weight: .semibold)
            .foregroundStyle(priority == .high ? .red : priority == .medium ? .orange : .secondary)
            .accessibilityLabel("Priority: \(priority.title)")
        }
        Text(item.title).stageFont(.body, weight: .semibold).foregroundStyle(.primary)
          .strikethrough(
            item.completed
          )
        Label(
          item.status.title,
          systemImage: item.status == .done ? "checkmark.circle.fill" : "circle.fill"
        )
        .stageFont(.caption, weight: .medium).foregroundStyle(
          item.status.isAttentionState ? .orange : .secondary
        )
        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(
          horizontal: false, vertical: true)
        if !item.notes.isEmpty {
          Text(item.notes).stageFont(.subheadline).foregroundStyle(.secondary).lineLimit(3)
        }
        if let run = model.library.latestRun(for: item.id) {
          RunBadge(run: run)
        } else if item.planPath != nil {
          Label("Plan attached", systemImage: "doc.text").stageFont(.caption).foregroundStyle(.blue)
        }
        if item.completed {
          Label("Completed by you", systemImage: "checkmark.circle.fill").stageFont(.caption)
            .foregroundStyle(.green)
        }
      }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
          RoundedRectangle(cornerRadius: 12).stroke(
            model.boardSelectedTaskID == item.id || model.selectedTaskID == item.id
              ? Color.accentColor.opacity(0.65) : .primary.opacity(0.07))
        )
        .shadow(color: .black.opacity(0.035), radius: 3, y: 2)
    }
    .buttonStyle(.plain)
    .draggable("stagechase-task:\(item.id.uuidString)")
    .dropDestination(for: String.self) { values, _ in
      guard let value = values.first, value.hasPrefix("stagechase-task:"),
        let id = UUID(uuidString: String(value.dropFirst("stagechase-task:".count))),
        let source = model.library.tasks.first(where: {
          $0.id == id && $0.projectID == item.projectID
        })
      else { return false }
      guard source.priority == item.priority || source.section != item.section else { return false }
      if source.section == item.section {
        Task {
          await model.perform(.reorder(id, before: item.id, expectedRevision: source.revision))
        }
      } else {
        model.requestMove(source, to: item.section)
      }
      return true
    }
    .contextMenu {
      let ordered = model.library.items(in: item.projectID, section: item.section, completed: true)
        .filter { $0.priority == item.priority }
      if let index = ordered.firstIndex(where: { $0.id == item.id }), index > 0 {
        Button("Move up in \(item.section.title)", systemImage: "arrow.up") {
          let previous = ordered[index - 1]
          Task {
            await model.perform(
              .reorder(item.id, before: previous.id, expectedRevision: item.revision))
          }
        }
      }
      if let index = ordered.firstIndex(where: { $0.id == item.id }), index + 1 < ordered.count {
        Button("Move down in \(item.section.title)", systemImage: "arrow.down") {
          let next = ordered[index + 1]
          Task {
            await model.perform(.reorder(next.id, before: item.id, expectedRevision: next.revision))
          }
        }
      }
      if !ordered.isEmpty { Divider() }
      ForEach(WorkflowSection.allCases.filter { $0 != item.section }) { stage in
        Button {
          model.requestMove(item, to: stage)
        } label: {
          Label("Move to \(stage.title)", systemImage: stage.symbol)
        }
      }
      if !model.isConnectedPhone {
        Divider()
        Button(item.completed ? "Reopen task" : "Mark complete", systemImage: "checkmark.circle") {
          Task {
            await model.perform(
              .complete(item.id, !item.completed, expectedRevision: item.revision))
          }
        }
      }
    }
    .accessibilityLabel("\(item.priority.map { "\($0.title) priority, " } ?? "")\(item.title)")
    .accessibilityHint("Open task details. Drag to another section or use the move menu.")
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
    }
  }
  var color: Color {
    switch run.status {
    case .running: .purple
    case .needsInput, .interrupted: .orange
    case .failed: .red
    case .succeeded: .green
    default: .secondary
    }
  }
}
