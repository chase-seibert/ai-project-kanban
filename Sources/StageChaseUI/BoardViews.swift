import SwiftUI
import UniformTypeIdentifiers

extension WorkflowStage {
  var color: Color {
    switch self {
    case .inbox: .secondary
    case .next: .purple
    case .planned: .blue
    case .implementation: .orange
    case .review: .green
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
  @State private var focusedStage: WorkflowStage? = .inbox
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      BoardHeader()
      #if os(iOS)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(WorkflowStage.allCases) { stage in
              Button {
                withAnimation { focusedStage = stage }
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
      GeometryReader { geometry in
        let width = laneWidth(geometry.size.width)
        ScrollView(.horizontal) {
          HStack(alignment: .top, spacing: 14) {
            ForEach(WorkflowStage.allCases) { stage in
              BoardLane(stage: stage).frame(
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
        #if os(iOS)
          .scrollTargetBehavior(.viewAligned)
        #endif
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Palette.canvas)
  }
  private func laneWidth(_ width: CGFloat) -> CGFloat {
    #if os(macOS)
      max(225, (width - 40 - 56) / 5)
    #else
      min(420, max(270, width - 48))
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
            Text("A little clarity. A lot of forward motion.").foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(model.library.items(in: model.selectedProjectID ?? UUID()).count) open tasks")
            .stageFont(.subheadline).foregroundStyle(.secondary).padding(.top, 10)
        }
      #endif
      HStack(spacing: 8) {
        Image(
          systemName: model.selectedProject?.automationEnabled == true ? "sparkles" : "pause.circle"
        )
        .foregroundStyle(model.selectedProject?.automationEnabled == true ? .purple : .secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(automationTitle).stageFont(.subheadline, weight: .medium)
          #if os(iOS)
            Text(currentPhoneSubtitle).stageFont(.caption).foregroundStyle(.secondary)
          #else
            Text(
              model.selectedProject?.automationEnabled == true
                ? "Next → plan · Implementation → code · You approve the moves"
                : "Move cards freely. Enable Codex in project settings when you’re ready."
            )
            .stageFont(.caption).foregroundStyle(.secondary)
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
        model.selectedProject?.automationEnabled == true
          ? "Codex is ready when you are" : "Manual board · Codex is off"
      }
    #endif
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
  let stage: WorkflowStage
  @State private var draft = ""
  @State private var adding = false
  @State private var targeted = false
  @State private var saving = false
  @FocusState private var captureFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: stage.symbol).foregroundStyle(stage.color)
        Text(stage.title).stageFont(.headline)
        Text("\(model.items(stage).count)").stageFont(.caption).monospacedDigit().foregroundStyle(
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
        .buttonStyle(.borderless).help("Add to \(stage.title)").accessibilityLabel(
          "Add task to \(stage.title)")
      }
      Text(stage.subtitle).stageFont(.caption).foregroundStyle(.secondary)
      Rectangle().fill(stage.color.opacity(0.5)).frame(height: 2)
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(model.items(stage)) { item in TaskCard(item: item) }
          if model.items(stage).isEmpty && !adding {
            VStack(spacing: 8) {
              Image(systemName: stage.symbol).stageFont(.title2).foregroundStyle(
                stage.color.opacity(0.65))
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
              HStack {
                Button("Cancel") {
                  adding = false
                  draft = ""
                }.buttonStyle(.borderless)
                Spacer()
                Button("Add task") { save() }.buttonStyle(.borderedProminent).controlSize(.small)
                  .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
              }
            }.padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
              .overlay(RoundedRectangle(cornerRadius: 12).stroke(stage.color.opacity(0.5)))
          } else {
            Button {
              adding = true
              captureFocused = true
            } label: {
              Label("Add task", systemImage: "plus").stageFont(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(
                  .horizontal, 6)
            }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(
              "Quick add to \(stage.title)")
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
      targeted ? stage.color.opacity(0.12) : Palette.card.opacity(0.34),
      in: RoundedRectangle(cornerRadius: 16)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16).strokeBorder(
        targeted ? stage.color : .primary.opacity(0.055), lineWidth: targeted ? 2 : 1)
    )
    .dropDestination(for: String.self) { values, _ in
      guard let value = values.first, value.hasPrefix("stagechase-task:"),
        let id = UUID(uuidString: String(value.dropFirst("stagechase-task:".count))),
        let item = model.library.tasks.first(where: {
          $0.id == id && $0.projectID == model.selectedProjectID
        })
      else { return false }
      model.requestMove(item, to: stage)
      return true
    } isTargeted: {
      targeted = $0
    }
  }
  private func save() {
    guard !saving, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    saving = true
    Task {
      if await model.addTask(draft, stage: stage) {
        draft = ""
        captureFocused = true
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
      #if os(macOS)
        model.selectedTaskID = item.id
      #else
        model.sheet = .task(item.id)
      #endif
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        Text(item.title).stageFont(.body, weight: .semibold).foregroundStyle(.primary)
          .strikethrough(
            item.completed
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
            model.selectedTaskID == item.id
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
      if source.stage == item.stage {
        Task {
          await model.perform(.reorder(id, before: item.id, expectedRevision: source.revision))
        }
      } else {
        model.requestMove(source, to: item.stage)
      }
      return true
    }
    .contextMenu {
      let ordered = model.library.items(in: item.projectID, stage: item.stage, completed: true)
      if let index = ordered.firstIndex(where: { $0.id == item.id }), index > 0 {
        Button("Move up in \(item.stage.title)", systemImage: "arrow.up") {
          let previous = ordered[index - 1]
          Task {
            await model.perform(
              .reorder(item.id, before: previous.id, expectedRevision: item.revision))
          }
        }
      }
      if let index = ordered.firstIndex(where: { $0.id == item.id }), index + 1 < ordered.count {
        Button("Move down in \(item.stage.title)", systemImage: "arrow.down") {
          let next = ordered[index + 1]
          Task {
            await model.perform(.reorder(next.id, before: item.id, expectedRevision: next.revision))
          }
        }
      }
      if !ordered.isEmpty { Divider() }
      ForEach(WorkflowStage.allCases.filter { $0 != item.stage }) { stage in
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
    .accessibilityHint("Open task details. Drag to another column or use the move menu.")
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
    case .running: "sparkles"
    case .needsInput: "hand.raised"
    case .succeeded: "checkmark.circle"
    case .failed, .interrupted: "exclamationmark.circle"
    case .cancelled: "stop.circle"
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
