import SwiftUI

#if os(macOS)
  struct CodexModelFields: View {
    @Environment(AppModel.self) private var model
    @Binding var configuration: CodexModelConfiguration
    var catalog: [CodexModelOption]
    private var selectedOption: CodexModelOption? {
      try? CodexModelResolver.option(for: configuration.selection, catalog: catalog)
    }
    var body: some View {
      Picker("Model", selection: $configuration.selection) {
        Text("Latest Luna").tag(CodexModelSelection.latestLuna)
        if case .model(let id) = configuration.selection,
          !catalog.contains(where: { $0.id == id })
        {
          Text("Unavailable · \(id)").tag(CodexModelSelection.model(id))
        }
        ForEach(catalog.filter { !$0.hidden }) { model in
          Text(model.displayName).tag(CodexModelSelection.model(model.id))
        }
      }
      if let selectedOption {
        Picker("Reasoning", selection: $configuration.effort) {
          if !selectedOption.reasoningEfforts.contains(configuration.effort) {
            Text("Unavailable · \(configuration.effort)").tag(configuration.effort)
          }
          ForEach(selectedOption.reasoningEfforts, id: \.self) { effort in
            Text(effort.capitalized).tag(effort)
          }
        }
      } else {
        Text("Refresh the Codex model list to see supported reasoning choices.")
          .stageFont(.caption).foregroundStyle(.secondary)
      }
      Button("Refresh model list") { Task { try? await model.refreshModelCatalog() } }
        .disabled(model.modelCatalogLoading)
    }
  }

  struct CodexModelOverrideEditor: View {
    @Binding var configuration: CodexModelConfiguration?
    var inherited: CodexModelConfiguration
    var inheritLabel: String
    var catalog: [CodexModelOption]
    private var inherits: Binding<Bool> {
      Binding(
        get: { configuration == nil },
        set: { configuration = $0 ? nil : inherited })
    }
    var body: some View {
      Toggle(inheritLabel, isOn: inherits)
      Text("Inherited: \(inherited.summary)").stageFont(.caption).foregroundStyle(.secondary)
      if !inherits.wrappedValue, configuration != nil {
        CodexModelFields(
          configuration: Binding(
            get: { configuration ?? inherited },
            set: { configuration = $0 }),
          catalog: catalog)
      }
    }
  }
#endif

struct ProjectEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var project: Project
  let isNew: Bool
  @State private var saving = false
  var body: some View {
    NavigationStack {
      Form {
        Section("Project") {
          TextField("Name", text: $project.name)
          #if os(macOS)
            HStack {
              TextField("Repository folder", text: $project.directory)
              Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url { project.directory = url.path }
              }
            }
          #endif
        }
        Section {
          #if os(macOS)
            Toggle("Let Codex work on this project", isOn: $project.automationEnabled)
            Text(
              "Every move into Next or Implementation asks for confirmation before starting Codex. Planning writes to to-do/. Implementation requires a saved plan. Commands needing approval appear in the activity panel."
            )
            .stageFont(.callout).foregroundStyle(.secondary)
            Text(
              "Uses StageChase’s selected model and reasoning effort. Usage may count toward your subscription or API billing. Never commits, pushes, or marks tasks complete automatically."
            )
            .stageFont(.caption).foregroundStyle(.secondary)
          #else
            Label("Codex runs on the Mac", systemImage: "desktopcomputer")
            Text(
              "These projects are saved on this iPhone. Mac pairing and synchronization are not connected in this version. You can create projects and organize tasks here; moves do not start Codex on another device."
            )
            .stageFont(.callout).foregroundStyle(.secondary)
          #endif
        } header: {
          Text("Automation")
        }
        #if os(macOS)
          Section("Codex model") {
            CodexModelOverrideEditor(
              configuration: $project.modelOverride,
              inherited: model.globalModelConfiguration,
              inheritLabel: "Use global model settings",
              catalog: model.modelCatalog)
            if let error = model.modelCatalogError {
              Text(error).stageFont(.caption).foregroundStyle(.orange)
            }
            Text(
              "The project override applies to new confirmed runs. Existing runs keep their saved model."
            )
            .stageFont(.caption).foregroundStyle(.secondary)
          }
        #endif
      }.formStyle(.grouped)
        .navigationTitle(isNew ? "New project" : "Project settings")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button(isNew ? "Create project" : "Save") {
              saving = true
              Task {
                if await model.saveProject(project, isNew: isNew) { dismiss() }
                saving = false
              }
            }.disabled(
              project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving
                || (project.automationEnabled && project.directory.isEmpty))
          }
        }
    }
    #if os(macOS)
      .frame(width: 560, height: 620)
    #endif
  }
}

struct NewTaskEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var modelOverride: CodexModelConfiguration?
  @State var stage: WorkflowStage
  var body: some View {
    NavigationStack {
      Form {
        TextField("What needs doing?", text: $title, axis: .vertical).lineLimit(2...6)
        Picker("Stage", selection: $stage) {
          ForEach(WorkflowStage.allCases) { Text($0.title).tag($0) }
        }
        #if os(macOS)
          if let project = model.selectedProject {
            Section("Codex model") {
              CodexModelOverrideEditor(
                configuration: $modelOverride,
                inherited: project.modelOverride ?? model.globalModelConfiguration,
                inheritLabel: "Use project model settings",
                catalog: model.modelCatalog)
            }
          }
        #endif
      }.formStyle(.grouped).navigationTitle("New task")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Add") {
              Task {
                if await model.addTask(title, stage: stage, modelOverride: modelOverride) {
                  dismiss()
                }
              }
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
    }
    #if os(macOS)
      .frame(width: 500, height: 440)
    #endif
  }
}

struct TaskDetail: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let taskID: UUID
  @State private var draft: WorkItem?
  @State private var edited = false
  @State private var deleting = false
  var item: WorkItem? { model.library.tasks.first { $0.id == taskID } }
  var body: some View {
    ScrollView {
      if let item {
        VStack(alignment: .leading, spacing: 22) {
          HStack {
            Label(item.stage.title, systemImage: item.stage.symbol).stageFont(
              .subheadline, weight: .semibold
            ).foregroundStyle(item.stage.color)
            Spacer()
            Button {
              #if os(macOS)
                model.selectedTaskID = nil
              #else
                dismiss()
              #endif
            } label: {
              Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }.buttonStyle(.plain).accessibilityLabel("Close task")
          }
          if draft != nil {
            TextField("Title", text: draftBinding(\.title), axis: .vertical).stageFont(
              .title2, weight: .bold
            ).textFieldStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
              Text("NOTES").stageFont(.caption, weight: .semibold).foregroundStyle(.secondary)
              TextEditor(text: draftBinding(\.notes)).frame(minHeight: 110).scrollContentBackground(
                .hidden
              )
              .padding(8).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.isConnectedPhone {
              VStack(alignment: .leading, spacing: 8) {
                Text("SAVED PLAN").stageFont(.caption, weight: .semibold).foregroundStyle(
                  .secondary)
                TextField(
                  "to-do/my-plan.md",
                  text: Binding(
                    get: { draft?.planPath ?? "" },
                    set: {
                      draft?.planPath = $0.isEmpty ? nil : $0
                      edited = true
                    })
                )
                .textFieldStyle(.roundedBorder)
                #if os(macOS)
                  if let path = item.planPath,
                    let project = model.library.projects.first(where: { $0.id == item.projectID })
                  {
                    Button("Open plan", systemImage: "doc.text") {
                      NSWorkspace.shared.open(
                        URL(fileURLWithPath: project.directory).appendingPathComponent(path))
                    }
                  }
                #endif
              }
            }
            if edited {
              Button("Save changes") {
                guard let draft else { return }
                Task {
                  if await model.perform(.editTask(draft, expectedRevision: draft.revision)) {
                    self.draft = self.item
                    edited = false
                  }
                }
              }.buttonStyle(.borderedProminent)
            }
            #if os(macOS)
              Section {
                CodexModelOverrideEditor(
                  configuration: Binding(
                    get: { draft?.modelOverride },
                    set: {
                      draft?.modelOverride = $0
                      edited = true
                    }),
                  inherited: model.inheritedConfiguration(for: draft ?? item),
                  inheritLabel: "Use project model settings",
                  catalog: model.modelCatalog)
              } header: {
                Text("Codex model")
              }
            #endif
          }
          HStack {
            Menu {
              ForEach(WorkflowStage.allCases.filter { $0 != item.stage }) { stage in
                Button(stage.title, systemImage: stage.symbol) {
                  model.requestMove(item, to: stage)
                }
              }
            } label: {
              Label("Move", systemImage: "arrow.right")
            }
            Spacer()
            if !model.isConnectedPhone {
              Button(item.completed ? "Reopen" : "Complete", systemImage: "checkmark.circle") {
                Task {
                  await model.perform(
                    .complete(item.id, !item.completed, expectedRevision: item.revision))
                }
              }
            }
          }.disabled(edited || model.library.latestRun(for: taskID)?.status.isActive == true)
          Divider()
          VStack(alignment: .leading, spacing: 12) {
            Label("Codex activity", systemImage: "sparkles").stageFont(.headline)
            if let run = model.library.latestRun(for: taskID) {
              RunDetail(run: run)
            } else {
              Text("No agent has worked on this task.").stageFont(.subheadline, weight: .medium)
              #if os(iOS)
                Text(
                  model.isConnectedPhone
                    ? "Codex runs on Mac. Continue there to confirm an automated move."
                    : "With project automation enabled on Mac, moving to Next starts planning. Moving to Implementation starts coding after you confirm."
                )
                .stageFont(.callout).foregroundStyle(.secondary)
              #else
                Text(
                  "With project automation enabled on Mac, moving to Next starts planning. Moving to Implementation starts coding after you confirm."
                )
                .stageFont(.callout).foregroundStyle(.secondary)
              #endif
            }
          }
          let activity = model.library.activity.filter { $0.taskID == taskID }.suffix(40).reversed()
          if !activity.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text("TIMELINE").stageFont(.caption, weight: .semibold).foregroundStyle(.secondary)
              ForEach(Array(activity)) { event in ActivityRow(event: event) }
            }
          }
          if !model.isConnectedPhone {
            Divider()
            Button("Delete task", role: .destructive) { deleting = true }.buttonStyle(.borderless)
          } else if let run = model.library.latestRun(for: taskID),
            run.status.isActive || [.needsInput, .interrupted].contains(run.status)
          {
            Text("Continue on Mac to manage this Codex run.").stageFont(.callout)
              .foregroundStyle(.secondary)
          }
        }.padding(20)
      } else {
        ContentUnavailableView("Task unavailable", systemImage: "doc.questionmark")
      }
    }.background(Palette.card)
      .task(id: taskID) {
        draft = item
        edited = false
      }
      .onChange(of: item?.revision) { _, _ in if !edited { draft = item } }
      .confirmationDialog(
        "Delete this task and its run history?", isPresented: $deleting, titleVisibility: .visible
      ) {
        Button("Delete task", role: .destructive) {
          guard let item else { return }
          Task {
            if await model.perform(.deleteTask(item.id, expectedRevision: item.revision)) {
              model.selectedTaskID = nil
              dismiss()
            }
          }
        }
      }
  }
  private func draftBinding(_ keyPath: WritableKeyPath<WorkItem, String>) -> Binding<String> {
    Binding(
      get: { draft?[keyPath: keyPath] ?? "" },
      set: {
        draft?[keyPath: keyPath] = $0
        edited = true
      })
  }
}

struct RunDetail: View {
  @Environment(AppModel.self) private var model
  let run: AgentRun
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        RunBadge(run: run)
        Spacer()
        Text(run.kind.rawValue.capitalized).stageFont(.caption).foregroundStyle(.secondary)
      }
      Text(run.summary).stageFont(.callout).textSelection(.enabled)
      Text(run.modelConfiguration?.summary ?? "Model not recorded")
        .stageFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      if let error = run.error {
        Text(error).stageFont(.callout).foregroundStyle(.red).textSelection(.enabled)
      }
      ForEach(Array(run.steps.enumerated()), id: \.offset) { _, step in
        Label(
          step.text,
          systemImage: step.status == "completed"
            ? "checkmark.circle.fill"
            : step.status == "inProgress" ? "circle.lefthalf.filled" : "circle"
        )
        .stageFont(.callout).foregroundStyle(step.status == "completed" ? .secondary : .primary)
      }
      #if os(macOS)
        if let approval = model.runner?.approval, approval.runID == run.id {
          VStack(alignment: .leading, spacing: 10) {
            Label("Your approval is needed", systemImage: "hand.raised.fill").stageFont(.headline)
            Text(approval.message).stageFont(.caption, design: .monospaced).textSelection(
              .enabled)
            HStack {
              Button("Deny") { Task { await model.runner?.answerApproval(allow: false) } }
              Button("Allow once") { Task { await model.runner?.answerApproval(allow: true) } }
                .buttonStyle(.borderedProminent)
            }
          }.padding(12).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        if let thread = run.threadID {
          let closeReason = model.closeCodexSessionReason(run.id)
          let closing = closeReason == "Closing…"
          HStack {
            Button("Open in Codex", systemImage: "arrow.up.right.square") {
              model.openCodexSession(thread)
            }.disabled(closing)
            Button("Copy session ID", systemImage: "doc.on.doc") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(thread, forType: .string)
            }.labelStyle(.iconOnly).help("Copy session ID")
            Button(closing ? "Closing…" : "Close Codex session", systemImage: "xmark.circle") {
              Task { await model.closeCodexSession(run.id) }
            }
            .disabled(closeReason != nil)
            .help(
              closeReason
                ?? "Release this session from StageChase so you can continue in the Codex desktop app. Files and conversation history are kept."
            )
          }
        }
        if let path = run.workDirectory {
          Button("Reveal working folder", systemImage: "folder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
          }
        }
      #endif
      HStack {
        if !model.isConnectedPhone && [.failed, .interrupted, .cancelled].contains(run.status) {
          Button(
            run.modelConfiguration == nil ? "Review model and retry" : "Retry in same session",
            systemImage: "arrow.clockwise"
          ) {
            Task { await model.retry(run.id) }
          }
        }
        if !model.isConnectedPhone && run.status.isActive {
          Button("Stop run", systemImage: "stop.circle", role: .destructive) {
            Task { await model.stop(run.id) }
          }
        }
      }
      Text(run.updatedAt, format: .dateTime.month().day().hour().minute()).stageFont(.caption2)
        .foregroundStyle(.tertiary)
    }
  }
}

struct ActivityRow: View {
  let event: Activity
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(event.message).stageFont(.callout).textSelection(.enabled)
      Text(event.date, format: .dateTime.month().day().hour().minute()).stageFont(.caption2)
        .foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct ActivityPanel: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          Text("Activity").stageFont(.title2, weight: .bold)
          Spacer()
          Text("\(model.activeRuns.count) active").stageFont(.caption).foregroundStyle(.secondary)
        }
        Text(model.runnerMessage).stageFont(.callout).foregroundStyle(.secondary)
        if model.projectRuns.isEmpty {
          ContentUnavailableView(
            "Nothing running", systemImage: "sparkles",
            description: Text(
              "Agent progress, approvals, and session links will appear here. Enabling automation alone never starts work."
            ))
        }
        ForEach(model.projectRuns) { run in
          VStack(alignment: .leading, spacing: 12) {
            Text(model.library.tasks.first { $0.id == run.taskID }?.title ?? "Task").stageFont(
              .headline)
            RunDetail(run: run)
          }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        }
        Text("RECENT EVENTS").stageFont(.caption, weight: .semibold).foregroundStyle(.secondary)
        ForEach(
          Array(
            model.library.activity.filter {
              model.selectedProjectID == nil || $0.projectID == model.selectedProjectID
                || $0.projectID == nil
            }.suffix(100).reversed())
        ) { event in
          ActivityRow(event: event)
          Divider()
        }
      }.padding(20)
    }.background(Palette.canvas)
  }
}
