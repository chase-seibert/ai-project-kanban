import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.undoManager) private var undoManager
  @Environment(\.scenePhase) private var scenePhase
  @State private var phoneBoard = false
  var body: some View {
    @Bindable var model = model
    Group {
      if let error = model.loadError {
        ContentUnavailableView {
          Label(
            "Your library couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
          Text(error + "\nYour existing files have not been replaced.")
        } actions: {
          Button("Try again") {
            Task {
              model.loadError = nil
              await model.load()
            }
          }
        }
      } else if !model.ready {
        ProgressView("Opening your projects…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        #if os(macOS)
          NavigationSplitView {
            ProjectSidebar()
              .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 310)
          } detail: {
            HStack(spacing: 0) {
              if model.selectedProject != nil { BoardView() } else { WelcomeView() }
              if let id = model.selectedTaskID {
                Divider()
                TaskDetail(taskID: id).frame(width: 340)
              } else if model.showActivity {
                Divider()
                ActivityPanel().frame(width: 370)
              }
            }
            .toolbar {
              ToolbarItemGroup {
                Button {
                  model.sheet = .newTask(model.boardFocusedStage)
                } label: {
                  Label("New task (⌘T)", systemImage: "plus")
                }.disabled(model.selectedProject == nil).help("New task in the focused section")
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
                  }
                } label: {
                  Image(systemName: "ellipsis.circle")
                }
              }
            }.searchable(text: $model.search, prompt: "Find tasks")
          }
        #else
          TabView {
            NavigationStack {
              ProjectSidebar(onOpen: { phoneBoard = true })
                .navigationTitle("Projects")
                .toolbar {
                  ToolbarItem(placement: .primaryAction) {
                    if !model.isConnectedPhone {
                      Button("New project", systemImage: "plus") { model.sheet = .newProject }
                    }
                  }
                }
                .navigationDestination(isPresented: $phoneBoard) {
                  BoardView().navigationTitle(model.selectedProject?.name ?? "Board")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                      ToolbarItem(placement: .primaryAction) {
                        Menu {
                          Button("Add task", systemImage: "plus") { model.sheet = .newTask(.inbox) }
                          Toggle("Show completed", isOn: $model.showCompleted)
                          if let project = model.selectedProject, !model.isConnectedPhone {
                            Button("Project settings", systemImage: "slider.horizontal.3") {
                              model.sheet = .editProject(project)
                            }
                          }
                        } label: {
                          Image(systemName: "ellipsis.circle")
                        }
                      }
                    }
                }
            }.tabItem { Label("Projects", systemImage: "square.grid.2x2") }
            NavigationStack { ActivityPanel().navigationTitle("Activity") }.tabItem {
              Label("Activity", systemImage: "waveform.path.ecg")
            }
            NavigationStack { SyncConnectionView().navigationTitle("Connection") }.tabItem {
              Label("Connection", systemImage: "network")
            }
            NavigationStack { AppSettings().navigationTitle("Settings") }.tabItem {
              Label("Settings", systemImage: "gearshape")
            }
          }
        #endif
      }
    }
    .sheet(item: $model.sheet, onDismiss: { model.sheetDidDismiss() }) { sheet in
      Group {
        switch sheet {
        case .newProject: ProjectEditor(project: Project(name: ""), isNew: true)
        case .editProject(let project): ProjectEditor(project: project, isNew: false)
        case .newTask(let stage): NewTaskEditor(stage: stage)
        case .task(let id): TaskDetail(taskID: id)
        case .settings:
          NavigationStack {
            AppSettings().navigationTitle("Settings")
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
      "Start Codex \(model.pendingMove?.stage == .next ? "planning" : "implementation")?",
      isPresented: Binding(
        get: { model.pendingMove != nil }, set: { if !$0 { model.pendingMove = nil } }),
      titleVisibility: .visible
    ) {
      if let move = model.pendingMove {
        Button(
          move.retryRunID == nil ? "Start Codex" : "Confirm model and retry"
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
        model.pendingMove?.retryRunID == nil ? "Keep moved task" : "Cancel", role: .cancel
      ) {
        model.pendingMove = nil
      }
    } message: {
      if let move = model.pendingMove {
        Text(
          [
            move.loading ? "Loading model settings…" : nil,
            move.configuration?.summary,
            move.retryRunID == nil
              ? "The task is already in \(move.stage.title). Cancel to leave it there without starting Codex."
              : nil,
            move.error == nil || move.retryRunID != nil
              ? nil : "The move is saved; Codex did not start.",
            move.error,
          ].compactMap { $0 }.joined(separator: "\n")
            + "\nUsage may be billed. You can watch progress, approve commands, or stop the run in Activity."
        )
      } else {
        Text("Codex starts only after confirmation.")
      }
    }
    .task(id: scenePhase) {
      model.undoManager = undoManager
      await model.load()
      if model.isPreview && ProcessInfo.processInfo.arguments.contains("--preview-board") {
        phoneBoard = true
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
}

struct ProjectSidebar: View {
  @Environment(AppModel.self) private var model
  var onOpen: (() -> Void)?
  var body: some View {
    List {
      Section {
        ForEach(model.library.projects) { project in
          let unreadCount = model.unreadProjectChangeCount(project.id)
          HStack(spacing: 8) {
            Button {
              model.select(project.id)
              onOpen?()
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(
                  project.id == model.selectedProjectID ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                  Text(project.name).stageFont(.body, weight: .medium).foregroundStyle(.primary)
                  #if os(iOS)
                    Text("\(model.library.items(in: project.id).count) open tasks").stageFont(
                      .caption
                    )
                    .foregroundStyle(.secondary)
                  #endif
                }
                Spacer()
                #if os(macOS)
                  Text("\(model.library.items(in: project.id).count)").stageFont(.caption)
                    .monospacedDigit().foregroundStyle(.secondary)
                #else
                  Image(systemName: "chevron.right").stageFont(.caption).foregroundStyle(.tertiary)
                #endif
              }
              .padding(.vertical, 6)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            if unreadCount > 0 {
              Button {
                model.markProjectChangesRead(project.id)
              } label: {
                Text("\(unreadCount)")
                  .font(.caption2.weight(.bold).monospacedDigit())
                  .foregroundStyle(.white)
                  .padding(.horizontal, 7)
                  .padding(.vertical, 3)
                  .background(Color.accentColor, in: Capsule())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Clear \(unreadCount) changed tasks in \(project.name)")
              .accessibilityIdentifier("unread-project-\(project.id.uuidString)")
              .help("Clear changed task badges for this project")
            }
          }
          .accessibilityElement(children: .contain)
          .listRowBackground(
            project.id == model.selectedProjectID ? Color.accentColor.opacity(0.1) : .clear
          )
          .contextMenu {
            if !model.isConnectedPhone {
              Button("Project settings…") { model.sheet = .editProject(project) }
            }
          }
        }
        if !model.isConnectedPhone {
          Button {
            model.sheet = .newProject
          } label: {
            Label("New project", systemImage: "plus.circle").padding(.vertical, 6)
          }
          .buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityIdentifier(
            "new-project")
        }
      } header: {
        Text("YOUR PROJECTS")
      }
      #if os(macOS)
        Section("Workspace") {
          Button {
            model.selectedTaskID = nil
            model.showActivity.toggle()
          } label: {
            Label("Agent activity", systemImage: "waveform.path.ecg")
          }.buttonStyle(.plain)
          Button {
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
    #if os(macOS)
      .listStyle(.sidebar).navigationTitle("StageChase")
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 5) {
          Label("Your work, in motion", systemImage: "square.stack.3d.up").stageFont(
            .caption, weight: .medium)
          Text("\(model.library.projects.count) projects · stored on this Mac").stageFont(.caption2)
          .foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
      }
    #else
      .listStyle(.insetGrouped)
    #endif
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
  var body: some View {
    #if os(macOS)
      TabView {
        GeneralSettingsForm().tabItem { Label("General", systemImage: "gearshape") }
        SyncConnectionView().tabItem { Label("Connection", systemImage: "network") }
      }
      .frame(minWidth: 640, minHeight: 680)
    #else
      GeneralSettingsForm()
    #endif
  }
}

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
        Section("Approval mode") {
          Picker(
            "When Codex needs approval",
            selection: Binding(
              get: { model.approvalMode },
              set: { model.setApprovalMode($0) })
          ) {
            ForEach(CodexApprovalMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          Text(approvalModeDescription)
            .stageFont(.caption).foregroundStyle(.secondary)
          if let error = model.approvalModeError {
            Text(error).stageFont(.caption).foregroundStyle(.orange)
          }
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
            : "Restore never overwrites existing projects. Original prototype JSON is kept alongside the new library."
        ).stageFont(.caption).foregroundStyle(.secondary)
      }
    }.formStyle(.grouped)
      #if os(macOS)
        .frame(width: 600, height: 760)
      #endif
      .fileExporter(
        isPresented: $exporting, document: document, contentType: .json,
        defaultFilename: "StageChase-backup"
      ) { result in
        if case .failure(let error) = result { model.error = error.localizedDescription }
      }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
        switch result {
        case .success(let url): Task { await model.restore(url) }
        case .failure(let error): model.error = error.localizedDescription
        }
      }
  }

  private var approvalModeDescription: String {
    switch model.approvalMode {
    case .approveForMe:
      "Uses Codex’s built-in no-prompt policy inside StageChase’s existing workspace sandbox."
    case .askMe:
      "Show supported command and file-change requests here for a one-time decision."
    case .autoApproveRequests:
      "StageChase answers supported requests once. It cannot grant broader file access or network access."
    }
  }
}
