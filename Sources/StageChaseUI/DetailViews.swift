import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#endif

#if os(iOS)
  import UIKit
  import PhotosUI
#endif

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

struct ProjectEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var project: Project
  let isNew: Bool
  @State private var saving = false
  @State private var makeTargetDraft = ""
  var body: some View {
    NavigationStack {
      Form {
        Section("Project") {
          #if os(iOS)
            if model.isConnectedPhone && !isNew {
              LabeledContent("Name", value: project.name)
            } else {
              TextField("Name", text: $project.name)
            }
          #else
            TextField("Name", text: $project.name)
          #endif
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
            VStack(alignment: .leading, spacing: 8) {
              Text("Favorite Make targets").font(.headline)
              HStack {
                TextField("Target name", text: $makeTargetDraft)
                  .onSubmit(addMakeTarget)
                Button("Add", action: addMakeTarget)
                  .disabled(!canAddMakeTarget)
              }
              if project.favoriteMakeTargets.isEmpty {
                Text("Add the Make targets you use often. Names are saved with this project.")
                  .stageFont(.caption).foregroundStyle(.secondary)
              } else {
                ForEach(Array(project.favoriteMakeTargets.enumerated()), id: \.offset) {
                  index, name in
                  HStack {
                    Label(name, systemImage: "star.fill")
                    Spacer()
                    Button {
                      guard index > 0 else { return }
                      project.favoriteMakeTargets.swapAt(index, index - 1)
                    } label: {
                      Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help("Move \(name) up")
                    Button {
                      guard index + 1 < project.favoriteMakeTargets.count else { return }
                      project.favoriteMakeTargets.swapAt(index, index + 1)
                    } label: {
                      Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index + 1 == project.favoriteMakeTargets.count)
                    .help("Move \(name) down")
                    Button(role: .destructive) {
                      project.favoriteMakeTargets.remove(at: index)
                    } label: {
                      Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(name) from favorite Make targets")
                  }
                }
              }
            }
            .padding(.top, 5)
          #endif
        }
        Section {
          #if os(macOS)
            Toggle("Allow automatic Codex runs for this project", isOn: $project.automationEnabled)
            Text(
              "This project switch works with the Mac-wide automatic invocation setting. Task details can copy a StageChase MCP prompt or launch it in Codex Desktop. Plans and Codex status do not restrict task columns."
            )
            .stageFont(.callout).foregroundStyle(.secondary)
            Text(
              "Uses StageChase’s selected model and reasoning effort. Usage may count toward your subscription or API billing. Automatic runs do not change task placement or completion. Successful manual task prompts move the task to Review and preserve its completion flag."
            )
            .stageFont(.caption).foregroundStyle(.secondary)
          #else
            Label("Codex runs on the paired Mac", systemImage: "desktopcomputer")
            Text(
              model.isConnectedPhone
                ? "Project profile and model changes apply to newly confirmed runs."
                : "Pair this phone with StageChase on your Mac to manage its Codex settings."
            )
            .stageFont(.callout).foregroundStyle(.secondary)
          #endif
        } header: {
          Text("Automation")
        }
        #if os(macOS)
          Section("Codex workspace") {
            Toggle("Use a managed worktree for implementation", isOn: $project.usesWorktrees)
            Text(
              "When on, dirty repositories use an isolated worktree. When off, implementation runs use this project folder directly, including its existing local changes. Planning always uses the project folder."
            )
            .stageFont(.caption).foregroundStyle(.secondary)
          }
          Section("Codex execution profile") {
            Picker("Permission profile", selection: $project.executionProfile) {
              ForEach(CodexExecutionProfile.allCases) { profile in
                Text(profile.title).tag(profile)
              }
            }
            Text(
              project.executionProfile == .workspaceAccessNoPrompts
                ? "Runs use the workspace-write sandbox, restricted to this run's working folder, with approval prompts disabled."
                : "Runs can read and write files outside this project and access the network. Choose this only when you trust the task and project. Approval prompts are disabled."
            )
            .stageFont(.caption).foregroundStyle(.secondary)
            Text(
              "This project choice is saved with each new run. Retries keep the profile saved on that run."
            )
            .stageFont(.caption).foregroundStyle(.secondary)
          }
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
        #else
          if model.isConnectedPhone && !isNew {
            Section("Repository") {
              PhoneGitControls(project: project, taskID: nil)
            }
            Section("Codex execution profile") {
              Picker("Permission profile", selection: $project.executionProfile) {
                ForEach(CodexExecutionProfile.allCases) { profile in
                  Text(profile.title).tag(profile)
                }
              }
              Text(
                project.executionProfile == .workspaceAccessNoPrompts
                  ? "Runs stay within the project working folder and have no network access. Approval prompts are disabled."
                  : "Full access removes filesystem and network isolation. Runs can change files outside this project. Choose this only when you trust the task and project. Approval prompts are disabled."
              )
              .stageFont(.caption).foregroundStyle(.secondary)
            }
            Section("Codex model") {
              CodexModelOverrideEditor(
                configuration: $project.modelOverride,
                inherited: model.globalModelConfiguration,
                inheritLabel: "Use global model settings",
                catalog: model.modelCatalog)
              if let error = model.modelCatalogError {
                Text(error).stageFont(.caption).foregroundStyle(.orange)
              }
              Text("Changes apply to newly confirmed runs. Existing runs keep their saved model.")
                .stageFont(.caption).foregroundStyle(.secondary)
            }
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
                || (!model.isConnectedPhone && project.automationEnabled
                  && project.directory.isEmpty)
                || (model.isConnectedPhone && !isNew
                  && model.library.projects.first(where: { $0.id == project.id }).map {
                    $0.executionProfile == project.executionProfile
                      && $0.modelOverride == project.modelOverride
                  } == true)
            )
          }
        }
    }
    #if os(macOS)
      .frame(width: 560, height: 700)
    #endif
    .task {
      #if os(iOS)
        if model.isConnectedPhone && !isNew { try? await model.refreshModelCatalog() }
      #endif
    }
  }

  #if os(macOS)
    private var canAddMakeTarget: Bool {
      let target = makeTargetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      return !target.isEmpty && !target.hasPrefix("-")
        && !project.favoriteMakeTargets.contains(target)
    }

    private func addMakeTarget() {
      let target = makeTargetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      guard canAddMakeTarget, (try? MakeTargetService.validate(target)) != nil else { return }
      project.favoriteMakeTargets.append(target)
      makeTargetDraft = ""
    }
  #endif
}

#if os(macOS)
  struct ProjectHeaderControls: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var showingGit = false

    private var currentProject: Project {
      model.library.projects.first(where: { $0.id == project.id }) ?? project
    }
    var body: some View {
      HStack(spacing: 12) {
        makeTargetMenu
        Button {
          showingGit = true
        } label: {
          HStack(spacing: 6) {
            Label(
              model.gitStatuses[project.id]?.branch ?? "Repository",
              systemImage:
                "chevron.left.forwardslash.chevron.right"
            )
            .lineLimit(1)
            if let status = model.gitStatuses[project.id] {
              CompactCountBadge(
                value: "\(status.changedFileCount)",
                color: status.hasChanges ? .orange : .secondary,
                accessibilityLabel: status.hasChanges
                  ? "\(status.changedFileCount) Git changes" : "Git clean",
                symbol: status.hasChanges ? "circle.fill" : nil)
            } else {
              CompactCountBadge(
                value: "-", color: .secondary, accessibilityLabel: "Git status dash")
            }
          }
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showingGit) {
          ProjectGitStatusView(project: currentProject, taskID: nil)
            .frame(width: 350).padding(16)
        }
        Spacer(minLength: 0)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            automationStatus
            Text(
              CodexModelResolver.effective(
                task: nil, project: currentProject.modelOverride,
                global: model.globalModelConfiguration
              ).configuration.summary
            )
            .stageFont(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          automationStatus
        }
        Button {
          model.sheet = .editProject(currentProject)
        } label: {
          Image(systemName: "slider.horizontal.3")
        }
        .buttonStyle(.borderless).help("Project settings")
        .accessibilityLabel("Project settings")
      }
      .tint(.primary)
      .task(id: project.id) { await model.refreshGitStatus(projectID: project.id) }
    }

    private var automationStatus: some View {
      let count = model.activeRuns.filter { $0.projectID == project.id }.count
      let automatic = model.autoInvokeCodex && currentProject.automationEnabled
      return Text(count > 0 ? "\(count) active" : automatic ? "Automatic" : "Manual")
        .stageFont(.caption).foregroundStyle(.secondary)
        .help(
          "Only confirmed moves can start automatic Codex work, when both automatic-invocation settings are enabled."
        )
    }

    private var makeTargetMenu: some View {
      let service = model.makeTargetService
      return Menu {
        if currentProject.favoriteMakeTargets.isEmpty {
          Button("Add favorites in Project settings…") {
            model.sheet = .editProject(currentProject)
          }
        } else {
          ForEach(currentProject.favoriteMakeTargets, id: \.self) { target in
            Button("Run \(target)", systemImage: "play.fill") {
              do {
                try model.runFavoriteMakeTarget(target, projectID: currentProject.id)
                model.sheet = .makeOutput
              } catch MakeTargetError.launch {
                model.sheet = .makeOutput
              } catch {
                model.error = error.localizedDescription
              }
            }.disabled(service.isRunning)
          }
        }
        if service.projectID != nil {
          Divider()
          Button("Show output · \(service.projectName) / \(service.target)") {
            model.sheet = .makeOutput
          }
          if service.isRunning {
            Button("Stop \(service.target)", systemImage: "stop.fill", role: .destructive) {
              service.stop()
            }
          }
        }
      } label: {
        Label(
          service.projectID == project.id || service.isRunning
            ? "Make · \(service.status.label)" : "Make",
          systemImage: service.isRunning ? "gearshape.2" : "hammer"
        )
        .lineLimit(1)
      }
      .menuStyle(.borderlessButton)
      .help("Run a favorite Make target in \(currentProject.name)")
      .accessibilityIdentifier("project-make-target-menu")
    }
  }

  struct MakeOutputSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
      let service = model.makeTargetService
      VStack(alignment: .leading, spacing: 14) {
        Text("\(service.projectName) / \(service.target)").stageFont(.title2, weight: .bold)
        HStack {
          if service.isRunning { ProgressView().controlSize(.small) }
          Text(service.status.label).stageFont(.headline)
          if case .failed(let message) = service.status {
            Text(message).foregroundStyle(.orange).textSelection(.enabled)
          }
        }
        if service.outputWasTruncated {
          Text("Showing the retained output tail (32 KB).").stageFont(.caption).foregroundStyle(
            .secondary)
        }
        ScrollView([.horizontal, .vertical]) {
          Text(
            service.output.isEmpty
              ? (service.isRunning ? "Waiting for output…" : "No output.") : service.output
          )
          .font(.system(.body, design: .monospaced)).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
        HStack {
          Button("Copy output", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(service.copyableOutput, forType: .string)
          }.disabled(service.output.isEmpty)
          if service.isRunning {
            Button("Stop", systemImage: "stop.fill", role: .destructive) { service.stop() }
          }
          Spacer()
          Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        if service.isRunning {
          Text("Closing this window keeps the command running.")
            .stageFont(.caption).foregroundStyle(.secondary)
        }
      }.padding(20).frame(minWidth: 600, idealWidth: 760, minHeight: 400, idealHeight: 520).tint(
        .primary)
    }
  }

  struct ProjectGitStatusView: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let taskID: UUID?

    private var currentProject: Project {
      model.library.projects.first(where: { $0.id == project.id }) ?? project
    }
    private var status: GitRepositoryStatus? {
      if let taskID { return model.gitTaskStatuses[taskID] }
      return model.gitStatuses[project.id]
    }
    private var statusError: String? {
      if let taskID { return model.gitTaskStatusErrors[taskID] }
      return model.gitStatusErrors[project.id]
    }
    private var isBusy: Bool { model.gitBusyProjectIDs.contains(project.id) }

    var body: some View {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 7) {
          if let status {
            Image(
              systemName: status.changedFileCount == 0
                ? "checkmark.circle" : "circle.lefthalf.filled"
            )
            .foregroundStyle(status.changedFileCount == 0 ? .green : .orange)
            Text(status.branch ?? "Detached HEAD")
            if let head = status.head {
              Text(String(head.prefix(12))).monospaced().textSelection(.enabled)
            } else {
              Text("No commits yet")
            }
            Text(status.changedFileCount == 0 ? "Clean" : "\(status.changedFileCount) changed")
              .foregroundStyle(.secondary)
              .help(
                "Staged: \(status.stagedFileCount) · Unstaged: \(status.unstagedFileCount) · Untracked: \(status.untrackedFileCount)"
              )
          } else if let error = statusError {
            Label(error, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange).help(error)
          } else {
            ProgressView().controlSize(.small)
            Text("Loading Git status…").foregroundStyle(.secondary)
          }
          Button {
            Task {
              if let taskID {
                await model.refreshTaskGitStatus(taskID: taskID)
              } else {
                await model.refreshGitStatus(projectID: project.id)
              }
            }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(.borderless).help("Refresh Git status")
          .disabled(isBusy)
        }
        if let taskID {
          Text(
            model.taskUsesSeparateGitWorktree(taskID: taskID)
              ? "Status for this task's recorded Codex worktree."
              : "Shared project repository status; files are not assigned to this task."
          ).stageFont(.caption).foregroundStyle(.secondary)
          Button {
            Task { await model.commitTaskChanges(taskID: taskID) }
          } label: {
            if isBusy { ProgressView().controlSize(.small) }
            Label("Commit all changes for this task", systemImage: "checkmark.circle")
          }
          .disabled(
            isBusy || currentProject.directory.isEmpty
              || model.library.latestRun(for: taskID)?.status.isActive == true
          )
          .help(
            "Stage and commit every change in this task's work folder using its title as the message."
          )
          .accessibilityHint(
            "Stages and commits all repository changes without a file picker or message editor.")
        } else {
          Button {
            Task { await model.commitProjectChanges(projectID: project.id) }
          } label: {
            if isBusy { ProgressView().controlSize(.small) }
            Label("Commit all project changes", systemImage: "checkmark.circle")
          }
          .disabled(isBusy || currentProject.directory.isEmpty)
          .help(
            "Stage and commit every non-ignored change in this project's configured folder using the title of its most recently completed task."
          )
          .accessibilityHint(
            "Stages and commits all changes in the configured project folder with the latest completed task title."
          )
        }
        if let message = model.gitActionMessages[project.id] {
          Text(message).stageFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
      }
      .stageFont(.caption)
      .task(id: "\(project.id.uuidString):\(taskID?.uuidString ?? "project"): \(project.directory)")
      {
        if let taskID {
          await model.refreshTaskGitStatus(taskID: taskID)
        } else {
          await model.refreshGitStatus(projectID: project.id)
        }
      }
    }
  }
#endif

#if os(iOS)
  struct PhoneGitControls: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let taskID: UUID?
    @State private var confirmingCommit = false

    private var key: String { "\(project.id.uuidString):\(taskID?.uuidString ?? "project")" }
    private var status: SyncGitStatus? { model.phoneGitStatuses[key] }
    private var busy: Bool { model.phoneGitBusyProjects.contains(project.id) }

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Label(
            taskID == nil ? "Project Git" : "Task Git",
            systemImage: "chevron.left.forwardslash.chevron.right"
          )
          .stageFont(.subheadline, weight: .semibold)
          Spacer()
          Button {
            Task { await model.refreshPhoneGitStatus(projectID: project.id, taskID: taskID) }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(busy)
          .accessibilityLabel("Refresh Git status")
        }
        if let status {
          Text(
            "\(status.branch ?? "Detached HEAD") · \(status.head.map { String($0.prefix(12)) } ?? "No commits yet")"
          )
          .stageFont(.caption).textSelection(.enabled)
          Text(
            status.changedFileCount == 0
              ? "Clean repository"
              : "\(status.changedFileCount) changed · \(status.stagedFileCount) staged · \(status.unstagedFileCount) unstaged · \(status.untrackedFileCount) untracked"
          )
          .stageFont(.caption).foregroundStyle(.secondary)
        } else if let error = model.phoneGitErrors[key] {
          Text(error).stageFont(.caption).foregroundStyle(.orange)
        } else {
          Text("Git status has not been loaded.").stageFont(.caption).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 6) {
          Button(
            taskID == nil ? "Commit project changes" : "Commit task changes",
            systemImage: "checkmark.circle"
          ) {
            confirmingCommit = true
          }
          .disabled(busy || status?.changedFileCount == 0)
        }
        if let message = model.phoneGitMessages[project.id] {
          Text(message).stageFont(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
      .task(id: key) {
        guard model.isConnectedPhone else { return }
        await model.refreshPhoneGitStatus(projectID: project.id, taskID: taskID)
      }
      .confirmationDialog("Commit changes on the paired Mac?", isPresented: $confirmingCommit) {
        Button("Commit changes", role: .destructive) {
          Task {
            if let taskID {
              await model.commitPhoneTask(taskID: taskID)
            } else {
              await model.commitPhoneProject(projectID: project.id)
            }
          }
        }
      } message: {
        Text(
          taskID == nil
            ? "Stage and commit all changes in the project's configured repository."
            : "Stage and commit all changes in this task's recorded worktree, or the project repository when it has no separate worktree."
        )
      }
    }
  }
#endif

struct NewTaskEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var modelOverride: CodexModelConfiguration?
  @State var stage: WorkflowSection
  var body: some View {
    NavigationStack {
      Form {
        TextField("What needs doing?", text: $title, axis: .vertical).lineLimit(2...6)
        Picker("Section", selection: $stage) {
          ForEach(WorkflowSection.allCases) { Text($0.title).tag($0) }
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
                if await model.addTask(title, section: stage, modelOverride: modelOverride) {
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
  @State private var notesSaveTask: Task<Void, Never>?
  @State private var notesSaveMessage: String?
  @State private var deleting = false
  @State private var approvingPlan = false
  @State private var contextExpanded = false
  @State private var moreDetailsExpanded = false
  @State private var titleExpanded = false
  @State private var runDisclosure = TaskRunDisclosureState()
  @State private var feedbackSubmitting = false
  @State private var promptCopied = false
  @State private var planPromptCopied = false
  @State private var importingAttachment = false
  @State private var showingAttachmentPreview = false
  @State private var attachmentPreviewData: Data?
  @State private var attachmentError: String?
  #if os(iOS)
    @State private var selectedPhoto: PhotosPickerItem?
  #endif
  #if os(iOS)
    @State private var showingPlanReader = false
    @State private var codexActionLoading = false
    @State private var phoneContextCopied = false
  #endif
  #if os(macOS)
    @FocusState private var focusedEditor: TaskEditorField?
    private enum TaskEditorField: Hashable {
      case title, notes, planPath, planFeedback
    }
  #endif
  var item: WorkItem? { model.library.tasks.first { $0.id == taskID } }
  private var handoffProject: Project? {
    guard let item else { return nil }
    return model.library.projects.first { $0.id == item.projectID }
  }
  #if os(macOS)
    private var codexHandoffPrompt: String? {
      guard let item, let project = handoffProject else { return nil }
      return TaskHandoffPrompt.make(for: item, project: project)
    }
    private var planCodexHandoffPrompt: String? {
      guard let item, let project = handoffProject else { return nil }
      return PlanHandoffPrompt.make(
        for: item, project: project, formatPrompt: model.resolvedPlanFormatPrompt)
    }
    private var hasReadableAttachedPlan: Bool {
      guard let item, let project = handoffProject else { return false }
      return PlanHandoffPrompt.hasReadablePlan(for: item, project: project)
    }
    private var usesPlanFeedbackField: Bool { !model.isConnectedPhone && hasReadableAttachedPlan }
  #else
    private var usesPlanFeedbackField: Bool { false }
  #endif
  private var canApprovePlan: Bool {
    guard let item, item.status == .planning else { return false }
    #if os(macOS)
      return hasReadableAttachedPlan
    #else
      return item.hasSavedPlan
    #endif
  }
  private var taskRuns: [AgentRun] {
    TaskRunDisclosureState.ordered(model.library.runs.filter { $0.taskID == taskID })
  }
  private var attentionRuns: [AgentRun] {
    taskRuns.filter { [.needsInput, .failed, .interrupted].contains($0.status) }
  }
  var body: some View {
    Group {
      if let item {
        VStack(alignment: .leading, spacing: 0) {
          taskHeader(item)
          Divider()
          ScrollViewReader { proxy in
            ScrollView {
              VStack(alignment: .leading, spacing: 20) {
                if !attentionRuns.isEmpty {
                  Menu {
                    ForEach(attentionRuns) { run in
                      Button(
                        "\(run.kind.rawValue.capitalized) · \(run.status.title) · \(run.createdAt.formatted(date: .abbreviated, time: .shortened))"
                      ) {
                        runDisclosure.setExpanded(true, for: run.id)
                        proxy.scrollTo(run.id, anchor: .top)
                      }
                    }
                  } label: {
                    Label(
                      "\(attentionRuns.count) run(s) need attention",
                      systemImage: "exclamationmark.circle")
                  }.foregroundStyle(.orange)
                }
                runHistory(item)
                taskAttachments(item)
                DisclosureGroup(isExpanded: $contextExpanded) {
                  TextEditor(text: contextBinding).frame(minHeight: 110).scrollContentBackground(
                    .hidden
                  )
                  #if os(macOS)
                    .focused($focusedEditor, equals: usesPlanFeedbackField ? .planFeedback : .notes)
                  #endif
                  .padding(8).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
                  .disabled(model.planFeedbackInFlight.contains(taskID))
                  Text(
                    usesPlanFeedbackField
                      ? "Feedback appends to the saved plan when you leave this field."
                      : "Changes save automatically."
                  )
                  .stageFont(.caption).foregroundStyle(.secondary)
                  if let notesSaveMessage {
                    Text(notesSaveMessage).stageFont(.caption)
                      .foregroundStyle(notesSaveMessage.hasPrefix("Could") ? .red : .secondary)
                  }
                  #if os(macOS)
                    if usesPlanFeedbackField, !model.planFeedbackDraft(for: taskID).isEmpty {
                      Button("Save feedback") { appendPlanFeedbackOnBlur() }
                        .disabled(
                          edited || feedbackSubmitting
                            || model.planFeedbackInFlight.contains(taskID))
                    }
                    if usesPlanFeedbackField, let message = model.planFeedbackMessages[taskID] {
                      Text(message.text).stageFont(.caption)
                        .foregroundStyle(message.isError ? .red : .secondary)
                        .textSelection(.enabled)
                    }
                  #endif

                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(usesPlanFeedbackField ? "Context & plan feedback" : "Task context")
                    Text(contextSummary).stageFont(.caption).foregroundStyle(.secondary)
                  }
                }
                #if os(macOS)
                  DisclosureGroup("StageChase runs") {
                    VStack(alignment: .leading, spacing: 8) {
                      Button("Execute Task", systemImage: "play.fill") {
                        model.requestRunnerRun(item, kind: .implementation)
                      }
                      .disabled(
                        handoffActionsDisabled || item.completed
                          || ![.planning, .implementing].contains(item.section)
                          || handoffProject?.directory.isEmpty != false
                      )
                      .help(
                        ![.planning, .implementing].contains(item.section)
                          ? "Move the task to Planning or Implementing first."
                          : handoffProject?.directory.isEmpty == false
                            ? "Execute this task in StageChase. You will review the model and confirm first."
                            : "Choose a repository folder in Project settings before running this task."
                      )
                      .frame(maxWidth: .infinity, alignment: .leading)
                      Button(
                        hasReadableAttachedPlan
                          ? "Revise plan with StageChase" : "Plan with StageChase",
                        systemImage: "sparkles"
                      ) {
                        model.requestRunnerRun(item, kind: .planning)
                      }
                      .disabled(
                        handoffActionsDisabled || item.completed
                          || handoffProject?.directory.isEmpty != false
                      )
                      .help(
                        handoffProject?.directory.isEmpty == false
                          ? "Have StageChase run a planning session for this task. You will review the model and confirm first."
                          : "Choose a repository folder in Project settings before planning with StageChase."
                      )
                      .frame(maxWidth: .infinity, alignment: .leading)

                    }.padding(.top, 8)
                  }
                #endif
                DisclosureGroup(isExpanded: $moreDetailsExpanded) {
                  VStack(alignment: .leading, spacing: 12) {
                    if !model.isConnectedPhone {
                      VStack(alignment: .leading, spacing: 8) {
                        Text("SAVED PLAN").stageFont(.caption, weight: .semibold).foregroundStyle(
                          .secondary)
                        Text(
                          item.planPath
                            ?? (item.hasSavedPlan ? "Saved plan available on Mac" : "No saved plan")
                        ).stageFont(.callout).foregroundStyle(
                          .secondary
                        )
                        .disabled(model.planFeedbackInFlight.contains(taskID))

                      }
                    }
                    #if os(iOS)
                      if model.isConnectedPhone {
                        VStack(alignment: .leading, spacing: 8) {
                          HStack {
                            Text("SAVED PLAN").stageFont(.caption, weight: .semibold)
                              .foregroundStyle(.secondary)
                            Spacer()
                            Button("Open plan", systemImage: "doc.text") {
                              showingPlanReader = true
                            }
                          }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
                      }
                    #endif
                    #if os(macOS)
                      DisclosureGroup("Codex model") {
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
                      }
                    #endif

                    Button("Delete task", role: .destructive) { deleting = true }
                      .buttonStyle(.borderless)
                      .disabled(model.planFeedbackInFlight.contains(taskID))
                  }.padding(.top, 8)
                } label: {
                  Text("More details")
                }
              }.padding(16).tint(.primary)
            }
          }
        }
      } else {
        ContentUnavailableView("Task unavailable", systemImage: "doc.questionmark")
      }
    }.background(Palette.card)
      #if os(iOS)
        .fullScreenCover(isPresented: $showingPlanReader) {
          if let item { PlanReaderView(item: item) }
        }
      #endif
      .task(id: taskID) {
        draft = item
        contextExpanded = false
        moreDetailsExpanded = false
        titleExpanded = false
        runDisclosure.select(taskID: taskID, runs: taskRuns)
        edited = false
        promptCopied = false
        planPromptCopied = false
        #if os(iOS)
          showingPlanReader = false
          phoneContextCopied = false
          model.phoneCodexActionMessage = nil
        #endif
        #if os(macOS)
          await Task.yield()
          focusedEditor = nil
          if model.launchTaskOnSelectionID == taskID {
            model.launchTaskOnSelectionID = nil
            launchCodex()
          }
        #endif
      }
      .onChange(of: taskRuns.map(\.id)) { _, _ in
        runDisclosure.select(taskID: taskID, runs: taskRuns)
      }
      .onChange(of: contextExpanded) { _, expanded in
        #if os(macOS)
          if !expanded, focusedEditor == .planFeedback {
            focusedEditor = nil
            appendPlanFeedbackOnBlur()
          }
        #endif
      }
      .onChange(of: item) { previous, current in
        guard !edited else { return }
        var refreshed = current
        // A completed debounce must not replace text typed during its save.
        if let notes = draft?.notes, notes != previous?.notes { refreshed?.notes = notes }
        draft = refreshed
      }
      .onChange(of: draft?.notes) { _, value in
        guard !usesPlanFeedbackField, let value else { return }
        scheduleNotesSave(value)
      }
      #if os(macOS)
        .onChange(of: focusedEditor) { previous, current in
          if previous == .planFeedback, current != .planFeedback { appendPlanFeedbackOnBlur() }
        }
      #endif
      .onDisappear {
        #if os(macOS)
          appendPlanFeedbackOnBlur()
        #endif
      }
      .onChange(of: model.saveTaskEditRequestedID) { _, requestedID in
        guard requestedID == taskID else { return }
        model.saveTaskEditRequestedID = nil
        saveTaskEdits()
      }
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
        }.keyboardShortcut(.defaultAction)
      }
      .fileImporter(
        isPresented: $importingAttachment, allowedContentTypes: [.image],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          guard let url = urls.first else { return }
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          do {
            let mediaType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? ""
            Task {
              await addAttachment(
                try Data(contentsOf: url), name: url.lastPathComponent, mediaType: mediaType)
            }
          } catch { attachmentError = error.localizedDescription }
        case .failure(let error): attachmentError = error.localizedDescription
        }
      }
      #if os(iOS)
        .onChange(of: selectedPhoto) { _, photo in
          guard let photo else { return }
          Task {
            do {
              guard let data = try await photo.loadTransferable(type: Data.self) else {
                throw BoardError.invalid("The selected image could not be loaded.")
              }
              let mediaType = photo.supportedContentTypes.first?.preferredMIMEType ?? ""
              await addAttachment(data, name: "Screenshot", mediaType: mediaType)
            } catch { attachmentError = error.localizedDescription }
            selectedPhoto = nil
          }
        }
      #endif
      .sheet(isPresented: $showingAttachmentPreview) {
        AttachmentPreview(data: attachmentPreviewData)
          .padding()
          .frame(minWidth: 360, minHeight: 320)
      }
  }

  @ViewBuilder private func taskAttachments(_ item: WorkItem) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Images").stageFont(.headline)
        Spacer()
        #if os(iOS)
          PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Attach", systemImage: "paperclip")
          }.disabled(item.attachments.count >= TaskAttachmentFiles.maximumCount)
        #else
          HStack(spacing: 8) {
            Button("Paste", systemImage: "document.on.clipboard") {
              pasteClipboardImage()
            }
            .disabled(item.attachments.count >= TaskAttachmentFiles.maximumCount)
            Button("Attach", systemImage: "paperclip") { importingAttachment = true }
              .disabled(item.attachments.count >= TaskAttachmentFiles.maximumCount)
          }
        #endif
      }
      if item.attachments.isEmpty {
        Text("No images attached.").stageFont(.callout).foregroundStyle(.secondary)
      }
      ForEach(item.attachments) { attachment in
        HStack(spacing: 8) {
          Button {
            Task {
              do {
                attachmentPreviewData = try await model.taskAttachmentData(
                  taskID: item.id, attachmentID: attachment.id)
                showingAttachmentPreview = true
                attachmentError = nil
              } catch { attachmentError = error.localizedDescription }
            }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(attachment.displayName).lineLimit(1)
              Text(
                attachment.transferState == .pendingUpload
                  ? "Pending upload"
                  : "Available · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))"
              )
              .stageFont(.caption).foregroundStyle(.secondary)
            }
          }.buttonStyle(.plain)
          Spacer()
          Button(role: .destructive) {
            Task {
              _ = await model.removeTaskAttachment(taskID: item.id, attachmentID: attachment.id)
            }
          } label: {
            Image(systemName: "trash")
          }.buttonStyle(.borderless).accessibilityLabel("Remove \(attachment.displayName)")
        }
      }
      if let attachmentError {
        Text(attachmentError).stageFont(.caption).foregroundStyle(.orange).textSelection(.enabled)
      }
      Text("Images stay in separate files. Previews download only when opened.")
        .stageFont(.caption).foregroundStyle(.secondary)
    }
  }

  private func addAttachment(_ bytes: Data, name: String, mediaType: String) async {
    let saved = await model.addTaskAttachment(
      taskID: taskID, bytes: bytes, displayName: name, mediaType: mediaType)
    if !saved { attachmentError = model.error ?? "Could not attach this image." }
  }

  #if os(macOS)
    private func pasteClipboardImage() {
      let pasteboard = NSPasteboard.general
      if let png = pasteboard.data(forType: .png) {
        Task { await addAttachment(png, name: "Pasted image.png", mediaType: "image/png") }
        return
      }
      if let tiff = pasteboard.data(forType: .tiff),
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      {
        Task { await addAttachment(png, name: "Pasted image.png", mediaType: "image/png") }
        return
      }
      let pastedImage =
        pasteboard.readObjects(
          forClasses: [NSImage.self],
          options: nil
        )?.first as? NSImage
      if let image = pastedImage,
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      {
        Task { await addAttachment(png, name: "Pasted image.png", mediaType: "image/png") }
        return
      }
      attachmentError = "The clipboard does not contain a supported image."
    }
  #endif

  private func taskHeader(_ item: WorkItem) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(item.shortID.map { "Task ID \($0)" } ?? "Task ID pending sync")
        .stageFont(.caption, weight: .medium).foregroundStyle(.secondary)
      HStack(alignment: .top) {
        TextField("Title", text: draftBinding(\.title), axis: .vertical)
          .stageFont(.title2, weight: .bold).textFieldStyle(.plain)
          .lineLimit(titleExpanded ? 1...10 : 1...3)
          #if os(macOS)
            .focused($focusedEditor, equals: .title)
          #endif
          .disabled(model.planFeedbackInFlight.contains(taskID))
        #if os(macOS)
          Button {
            model.selectedTaskID = nil
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }.buttonStyle(.plain).accessibilityLabel("Close task")
        #endif
      }
      if item.title.count > 100 {
        Button(titleExpanded ? "Collapse title" : "Expand title") { titleExpanded.toggle() }
          .buttonStyle(.borderless).stageFont(.caption)
      }
      HStack(spacing: 6) {
        Spacer(minLength: 0)
        if item.completed {
          Button("Reopen", systemImage: "arrow.uturn.backward") { setTaskCompleted(false) }
            .buttonStyle(.borderedProminent).tint(.blue)
        } else {
          Button("Complete", systemImage: "checkmark.circle") { setTaskCompleted(true) }
            .buttonStyle(.bordered)
        }
      }.stageFont(.caption)
      HStack(spacing: 12) {
        Button {
          Task { await model.setFavorite(!item.isFavorite, for: item.id) }
        } label: {
          Label(
            item.isFavorite ? "Favorited" : "Add to favorites",
            systemImage: item.isFavorite ? "star.fill" : "star")
        }
        .buttonStyle(.bordered)
        TaskModelTagMenu(item: item)
      }
      if canApprovePlan {
        Button {
          approvePlan(item)
        } label: {
          Label("Mark plan approved", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 59.0 / 255, green: 130.0 / 255, blue: 246.0 / 255))
        .disabled(approvingPlan)
        .accessibilityHint("Approves the saved plan without moving the task or starting Codex.")
      }
      #if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
          Button {
            requestCodexAction(.run, item: item)
          } label: {
            Label("Launch in Codex", systemImage: "arrow.up.right.square")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent).tint(.blue)
          .disabled(
            codexActionLoading || item.completed
              || ![.planning, .implementing].contains(item.section)
              || model.library.runs.contains(where: { $0.taskID == item.id && $0.status.isActive })
          )
          .accessibilityHint("Starts this task with Codex on the paired Mac.")

          Button {
            requestCodexAction(.plan, item: item)
          } label: {
            Label("Plan in Codex", systemImage: "sparkles")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent).tint(.blue)
          .disabled(
            codexActionLoading || item.completed
              || model.library.runs.contains(where: { $0.taskID == item.id && $0.status.isActive })
          )
          .accessibilityHint("Starts a planning run with Codex on the paired Mac.")

          Button {
            copyPhonePrompt(for: item)
          } label: {
            Label("Copy prompt", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)

          if phoneContextCopied {
            Label("Prompt copied", systemImage: "checkmark.circle.fill")
              .stageFont(.caption).foregroundStyle(.green)
          }
          if let message = model.phoneCodexActionMessage {
            Text(message).stageFont(.caption)
              .foregroundStyle(
                message.localizedCaseInsensitiveContains("could not")
                  || message.localizedCaseInsensitiveContains("pair") ? .orange : .secondary
              )
              .textSelection(.enabled)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
      #endif
      if edited {
        Button("Save changes (⌘Return)") { saveTaskEdits() }
          .buttonStyle(.borderedProminent).tint(.blue)
          .keyboardShortcut(.return, modifiers: [.command])
      }
      #if os(macOS)
        VStack(alignment: .leading, spacing: 8) {
          Button("Launch in Codex", systemImage: "arrow.up.right.square") {
            launchCodex()
          }
          .keyboardShortcut("r", modifiers: [.command])
          .disabled(
            handoffActionsDisabled || codexHandoffPrompt == nil
              || handoffProject?.directory.isEmpty != false
          )
          .help(
            handoffProject?.directory.isEmpty == false
              ? "Open this project in Codex Desktop with the task prompt."
              : "Choose a repository folder in Project settings before launching Codex."
          )
          .buttonStyle(.borderedProminent).tint(.blue)
          .frame(maxWidth: .infinity, alignment: .leading)
          Button(
            hasReadableAttachedPlan ? "Review plan in Codex" : "Plan in Codex",
            systemImage: "arrow.up.right.square"
          ) {
            launchPlanCodex()
          }
          .disabled(
            handoffActionsDisabled || planCodexHandoffPrompt == nil
              || handoffProject?.directory.isEmpty != false
          )
          .help(
            handoffProject?.directory.isEmpty == false
              ? "Open a new Codex Desktop thread with plan-only instructions."
              : "Choose a repository folder in Project settings before planning in Codex."
          )
          .buttonStyle(.borderedProminent).tint(.blue)
          .frame(maxWidth: .infinity, alignment: .leading)

        }
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 10) { secondaryActions }
          VStack(alignment: .leading, spacing: 8) { secondaryActions }
        }.buttonStyle(.borderless).stageFont(.caption).tint(.primary)
        if item.planPath != nil, !hasReadableAttachedPlan {
          Text("The saved plan is missing or empty. Plan in Codex can repair it at the same path.")
            .stageFont(.caption).foregroundStyle(.orange)
        }
        if let message = model.taskRefreshMessages[taskID] {
          Text(message).stageFont(.caption).foregroundStyle(.secondary).lineLimit(2).help(message)
        }
      #endif
    }.padding(16)
  }

  #if os(macOS)
    @ViewBuilder private var secondaryActions: some View {
      if let thread = taskRuns.first(where: { $0.threadID != nil })?.threadID {
        Button("Open existing thread") { model.openCodexSession(thread) }
      }
      if hasReadableAttachedPlan, let path = item?.planPath, let project = handoffProject {
        Button("Open plan") {
          if let url = try? PlanFileStore.resolve(
            projectDirectory: project.directory, relativePath: path)
          {
            NSWorkspace.shared.open(url)
          }
        }
      }
      Button(
        model.taskRefreshInFlight.contains(taskID) ? "Refreshing…" : "Refresh",
        systemImage: "arrow.clockwise"
      ) {
        Task { await model.refreshTask(taskID, preservingEdits: edited) }
      }
      .disabled(model.taskRefreshInFlight.contains(taskID))
      .help("Refresh the saved task, plan, and linked Codex activity.")

      Menu {
        Button("Copy task prompt") { copyCodexPrompt() }
        Button("Copy plan prompt") { copyPlanCodexPrompt() }
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Copy Codex instructions")
    }
  #endif

  private var contextSummary: String {
    #if os(macOS)
      if let message = model.planFeedbackMessages[taskID], message.isError { return message.text }
      if !model.planFeedbackDraft(for: taskID).isEmpty { return "Unsaved feedback" }
    #endif
    if let notesSaveMessage, notesSaveMessage.hasPrefix("Could") { return notesSaveMessage }
    return (draft?.notes.isEmpty == false) ? "Notes available" : "Add context when needed"
  }

  private func runHistory(_ item: WorkItem) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Codex activity").stageFont(.headline)
      if let update = item.latestCodexUpdate, update != taskRuns.first?.summary {
        Text(update).stageFont(.callout).textSelection(.enabled)
        if let date = item.latestCodexUpdateAt {
          Text(date, format: .dateTime.month().day().hour().minute())
            .stageFont(.caption).foregroundStyle(.secondary)
        }
      }
      ForEach(taskRuns) { run in
        DisclosureGroup(
          isExpanded: Binding(
            get: { runDisclosure.expandedIDs.contains(run.id) },
            set: { runDisclosure.setExpanded($0, for: run.id) }
          )
        ) {
          RunDetail(run: run).padding(.top, 8)
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(
              "\(run.id == taskRuns.first?.id ? "Latest run" : "Earlier run") · \(run.kind.rawValue.capitalized)"
            )
            .stageFont(.subheadline, weight: .medium)
            Text(
              "\(run.status.title) · \(run.source == .codexDesktop ? "Codex Desktop" : "StageChase")"
            )
            .stageFont(.caption).foregroundStyle(.secondary)
            Text(run.createdAt, format: .dateTime.month().day().hour().minute())
              .stageFont(.caption2).foregroundStyle(.secondary)
          }
        }.id(run.id)
      }
      if taskRuns.isEmpty {
        Text("No Codex runs yet.").stageFont(.callout).foregroundStyle(.secondary)
      }
    }
  }

  private var contextBinding: Binding<String> {
    #if os(macOS)
      if usesPlanFeedbackField { return planFeedbackBinding }
    #endif
    return Binding(get: { draft?.notes ?? "" }, set: { draft?.notes = $0 })
  }

  private func scheduleNotesSave(_ value: String) {
    guard item?.notes != value else { return }
    notesSaveTask?.cancel()
    notesSaveMessage = "Saving…"
    let savingTaskID = taskID
    notesSaveTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(650))
      guard !Task.isCancelled,
        let currentItem = model.library.tasks.first(where: { $0.id == savingTaskID })
      else { return }
      if await model.perform(
        .saveNotes(currentItem.id, value, expectedRevision: currentItem.revision))
      {
        notesSaveMessage = "Saved"
        if var draft, let latest = self.item {
          if draft.notes == value { draft.notes = value }
          draft.revision = latest.revision
          self.draft = draft
        }
      } else {
        notesSaveMessage = "Could not save context. Your draft is still here."
        contextExpanded = true
      }
    }
  }

  #if os(macOS)
    private func appendPlanFeedbackOnBlur() {
      guard usesPlanFeedbackField, !edited, !feedbackSubmitting, let item else { return }
      let text = model.planFeedbackDraft(for: taskID)
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      feedbackSubmitting = true
      Task {
        defer { feedbackSubmitting = false }
        let saved = await model.appendPlanFeedback(
          taskID: taskID, expectedRevision: item.revision, text: text)
        if !saved { contextExpanded = true }
        notesSaveMessage =
          saved
          ? "Feedback saved to plan."
          : "Could not append feedback. Your draft is still here."
      }
    }
  #endif

  #if os(iOS)
    private func requestCodexAction(_ action: SyncPhoneCodexAction, item: WorkItem) {
      guard !codexActionLoading else { return }
      codexActionLoading = true
      Task {
        await model.requestCodexFromMac(item, action: action)
        codexActionLoading = false
      }
    }

    private func copyPhonePrompt(for item: WorkItem) {
      let notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
      let projectName = handoffProject?.name ?? "Project"
      UIPasteboard.general.string = """
        Work on this existing StageChase task in the project repository. Follow the repository's AGENTS.md instructions. Read the task with the StageChase MCP server first and verify the returned project and task IDs match before making changes.

        Project: \(projectName)
        Project ID: \(item.projectID.uuidString.lowercased())
        Task ID: \(item.id.uuidString.lowercased())
        Task: \(item.shortID.map { "#\($0) · " } ?? "")\(item.title)
        Notes:
        \(notes.isEmpty ? "(No additional notes.)" : notes)
        """
      phoneContextCopied = true
    }

  #endif

  private func draftBinding(_ keyPath: WritableKeyPath<WorkItem, String>) -> Binding<String> {
    Binding(
      get: { draft?[keyPath: keyPath] ?? "" },
      set: {
        draft?[keyPath: keyPath] = $0
        edited = true
      })
  }

  private func saveTaskEdits() {
    guard edited, let draft else { return }
    notesSaveTask?.cancel()
    notesSaveTask = nil
    Task {
      if await model.perform(.editTask(draft, expectedRevision: draft.revision)) {
        self.draft = self.item
        edited = false
      }
    }
  }

  private func approvePlan(_ item: WorkItem) {
    guard !approvingPlan else { return }
    approvingPlan = true
    Task {
      _ = await model.perform(.approvePlan(item.id, expectedRevision: item.revision))
      approvingPlan = false
    }
  }

  private func setTaskCompleted(_ completed: Bool) {
    Task {
      guard let current = item,
        await model.perform(
          .complete(current.id, completed, expectedRevision: current.revision)),
        var localDraft = draft,
        let latest = item
      else { return }
      localDraft.completed = latest.completed
      localDraft.completedAt = latest.completedAt
      localDraft.stage = latest.stage
      localDraft.section = latest.section
      localDraft.status = latest.status
      localDraft.revision = latest.revision
      draft = localDraft
    }
  }

  #if os(macOS)
    private var handoffActionsDisabled: Bool {
      edited || draft?.notes != item?.notes
        || !model.planFeedbackDraft(for: taskID).trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty
        || model.planFeedbackInFlight.contains(taskID)
        || model.library.latestRun(for: taskID)?.status.isActive == true
    }

    private func copyCodexPrompt() {
      guard let item, let project = handoffProject,
        let prompt = TaskHandoffPrompt.copyableContext(for: item, project: project)
      else { return }
      NSPasteboard.general.clearContents()
      guard NSPasteboard.general.setString(prompt, forType: .string) else {
        model.error = "The task context could not be copied to the clipboard."
        return
      }
      promptCopied = true
    }

    private func launchCodex() {
      launchCodex(
        prompt: codexHandoffPrompt,
        promptFailureMessage: "This task prompt could not be prepared.")
    }

    private func launchPlanCodex() {
      launchCodex(
        prompt: planCodexHandoffPrompt,
        promptFailureMessage: "This plan prompt could not be prepared.")
    }

    private func launchCodex(prompt: String?, promptFailureMessage: String) {
      guard let project = handoffProject else { return }
      guard !project.directory.isEmpty else {
        model.error = "Choose a repository folder in Project settings before launching Codex."
        return
      }
      guard let prompt else {
        model.error = promptFailureMessage
        return
      }
      var components = URLComponents()
      components.scheme = "codex"
      components.host = "threads"
      components.path = "/new"
      components.queryItems = [
        URLQueryItem(name: "path", value: project.directory),
        URLQueryItem(name: "prompt", value: prompt),
      ]
      guard let url = components.url, NSWorkspace.shared.open(url) else {
        model.error =
          "Codex Desktop could not open this task. Copy the prompt and paste it into Codex Desktop instead."
        return
      }
    }

    private func copyPlanCodexPrompt() {
      guard let prompt = planCodexHandoffPrompt else { return }
      NSPasteboard.general.clearContents()
      guard NSPasteboard.general.setString(prompt, forType: .string) else {
        model.error = "The plan instructions could not be copied to the clipboard."
        return
      }
      planPromptCopied = true
    }

    private var planFeedbackBinding: Binding<String> {
      Binding(
        get: { model.planFeedbackDraft(for: taskID) },
        set: { model.setPlanFeedbackDraft($0, for: taskID) })
    }
  #endif

  private func hasReadablePlan(path: String, project: Project) -> Bool {
    guard
      let url = try? PlanFileStore.resolve(
        projectDirectory: project.directory, relativePath: path),
      let contents = try? String(contentsOf: url, encoding: .utf8)
    else { return false }
    return !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private struct AttachmentPreview: View {
  let data: Data?
  var body: some View {
    Group {
      if let data {
        #if os(macOS)
          if let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
          } else {
            ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle")
          }
        #else
          if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit()
          } else {
            ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle")
          }
        #endif
      } else {
        ProgressView("Loading image…")
      }
    }
  }
}

#if os(iOS)
  private struct PlanReaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: WorkItem
    @State private var markdown = ""
    @State private var feedback = ""
    @State private var loading = true
    @State private var submitting = false
    @State private var loadError: String?
    @State private var message: String?
    @State private var requestID: UUID?
    @State private var runID: UUID?
    @FocusState private var feedbackFocused: Bool
    var body: some View {
      NavigationStack {
        ScrollView {
          Group {
            if loading {
              ProgressView("Loading plan from Mac…").frame(maxWidth: .infinity, minHeight: 180)
            } else if let loadError {
              ContentUnavailableView {
                Label("Plan unavailable", systemImage: "doc.text.magnifyingglass")
              } description: {
                Text(loadError)
              } actions: {
                Button("Retry") { loadPlan() }
              }
            } else {
              PlanMarkdownDocument(markdown: markdown)
            }
          }
        }
        .background(Palette.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $feedback)
              .focused($feedbackFocused)
              .frame(minHeight: 96, maxHeight: 150)
              .scrollContentBackground(.hidden)
              .padding(4)
              .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
              .accessibilityLabel("Plan feedback")
              .accessibilityHint("Type or dictate feedback, then save to replan the task.")
            if let message {
              Text(message).font(.footnote).foregroundStyle(
                message.localizedCaseInsensitiveContains("could not")
                  || message.localizedCaseInsensitiveContains("changed") ? .orange : .secondary
              )
              .textSelection(.enabled)
            }
            Button {
              submitFeedback()
            } label: {
              if submitting {
                ProgressView().frame(maxWidth: .infinity)
              } else {
                Label("Save & replan", systemImage: "sparkles")
                  .frame(maxWidth: .infinity)
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
              submitting || runID != nil
                || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityHint("Submits this feedback and starts a planning run on the paired Mac.")
          }
          .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
          .background(.regularMaterial)
        }
        .navigationTitle("Saved plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
          }
        }
      }
      .task { loadPlan() }
      .task(id: runID) { await followRun() }
      .onChange(of: feedback) { _, _ in
        if !submitting && runID == nil { requestID = nil }
      }
    }

    private func loadPlan() {
      guard !submitting else { return }
      loading = true
      loadError = nil
      Task {
        do { markdown = try await model.readPlanFromMac(item) } catch {
          loadError = error.localizedDescription
        }
        loading = false
      }
    }

    private func submitFeedback() {
      guard !submitting, runID == nil,
        !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return }
      submitting = true
      feedbackFocused = false
      message = "Sending feedback to the Mac…"
      let id = requestID ?? UUID()
      requestID = id
      Task {
        do {
          runID = try await model.requestPlanRevisionFromMac(
            item, feedback: feedback, requestID: id)
          message = "Feedback saved. The plan is being revised on the Mac."
        } catch {
          message = error.localizedDescription
        }
        submitting = false
      }
    }

    private func followRun() async {
      guard let runID else { return }
      while !Task.isCancelled {
        await model.refreshFromMac(manual: true)
        guard let run = model.library.runs.first(where: { $0.id == runID }) else {
          message = "Waiting for the Mac to report planning progress…"
          try? await Task.sleep(for: .seconds(2))
          continue
        }
        switch run.status {
        case .succeeded:
          if let latest = model.library.tasks.first(where: { $0.id == item.id }) {
            do {
              markdown = try await model.readPlanFromMac(latest)
              feedback = ""
              requestID = nil
              message = "Plan updated."
            } catch {
              message =
                "Plan revision finished, but the updated plan could not be loaded: \(error.localizedDescription)"
            }
          }
          return
        case .failed, .cancelled, .interrupted, .stale, .superseded:
          message =
            run.error
            ?? "The plan revision did not finish. Your feedback is still here; save again to retry."
          self.runID = nil
          requestID = nil
          return
        case .needsInput:
          message =
            "The Mac needs your attention before this plan revision can continue. Your feedback is still here."
          return
        default:
          message =
            run.status == .queued
            ? "Plan revision queued on the Mac…" : "Plan revision running on the Mac…"
          try? await Task.sleep(for: .seconds(2))
        }
      }
    }
  }

  private struct PlanMarkdownDocument: View {
    let markdown: String

    private var blocks: [PlanMarkdownBlock] {
      PlanMarkdownParser.parse(markdown)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
          blockView(block)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
      .padding(.vertical, 16)
    }

    @ViewBuilder private func blockView(_ block: PlanMarkdownBlock) -> some View {
      switch block {
      case .heading(let level, let text):
        inlineText(text)
          .font(headingFont(level))
          .fixedSize(horizontal: false, vertical: true)
      case .paragraph(let text):
        inlineText(text)
          .lineSpacing(5)
          .fixedSize(horizontal: false, vertical: true)
      case .list(let items, let ordered):
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            HStack(alignment: .firstTextBaseline, spacing: 9) {
              Text(ordered ? "\(index + 1)." : "•")
                .font(.body.weight(ordered ? .semibold : .regular))
                .frame(minWidth: ordered ? 22 : 12, alignment: .leading)
              inlineText(item)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      case .quote(let text):
        HStack(alignment: .top, spacing: 12) {
          RoundedRectangle(cornerRadius: 1.5)
            .fill(.secondary.opacity(0.55))
            .frame(width: 3)
          inlineText(text)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
        }
      case .code(let text):
        ScrollView(.horizontal) {
          Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
      case .divider:
        Divider()
      }
    }

    private func inlineText(_ text: String) -> Text {
      let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace)
      let attributed =
        (try? AttributedString(markdown: text, options: options))
        ?? AttributedString(text)
      return Text(attributed)
    }

    private func headingFont(_ level: Int) -> Font {
      switch level {
      case 1: .largeTitle.weight(.bold)
      case 2: .title2.weight(.bold)
      case 3: .title3.weight(.bold)
      case 4: .headline.weight(.bold)
      case 5: .subheadline.weight(.bold)
      default: .callout.weight(.bold)
      }
    }
  }

  private enum PlanMarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case list([String], ordered: Bool)
    case quote(String)
    case code(String)
    case divider
  }

  private enum PlanMarkdownParser {
    private struct ListMarker {
      let ordered: Bool
      let content: String
    }

    static func parse(_ markdown: String) -> [PlanMarkdownBlock] {
      let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")
      var blocks: [PlanMarkdownBlock] = []
      var index = 0

      while index < lines.count {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
          index += 1
          continue
        }

        if let fence = codeFence(in: trimmed) {
          index += 1
          var code: [String] = []
          while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix(fence) { break }
            code.append(lines[index])
            index += 1
          }
          if index < lines.count { index += 1 }
          blocks.append(.code(code.joined(separator: "\n")))
          continue
        }

        if let heading = heading(in: trimmed) {
          blocks.append(.heading(heading.level, heading.text))
          index += 1
          continue
        }

        if isThematicBreak(trimmed) {
          blocks.append(.divider)
          index += 1
          continue
        }

        if isQuoteLine(trimmed) {
          var quote: [String] = []
          while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            guard isQuoteLine(candidate) else { break }
            quote.append(String(candidate.dropFirst().drop(while: { $0 == " " || $0 == "\t" })))
            index += 1
          }
          blocks.append(.quote(quote.joined(separator: "\n")))
          continue
        }

        if let marker = listMarker(in: trimmed) {
          let ordered = marker.ordered
          var items: [String] = []
          while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            guard let next = listMarker(in: candidate), next.ordered == ordered else { break }
            items.append(next.content)
            index += 1
            while index < lines.count {
              let continuation = lines[index]
              let continuationTrimmed = continuation.trimmingCharacters(in: .whitespaces)
              if continuationTrimmed.isEmpty || startsBlock(continuationTrimmed) { break }
              let indentation = continuation.prefix(while: { $0 == " " || $0 == "\t" }).count
              guard indentation >= 2 else { break }
              items[items.count - 1] += " " + continuationTrimmed
              index += 1
            }
          }
          blocks.append(.list(items, ordered: ordered))
          continue
        }

        var paragraph = [trimmed]
        index += 1
        if index < lines.count,
          let setextLevel = setextHeadingLevel(
            in: lines[index].trimmingCharacters(in: .whitespaces))
        {
          blocks.append(.heading(setextLevel, paragraph.joined(separator: " ")))
          index += 1
          continue
        }
        while index < lines.count {
          let candidate = lines[index].trimmingCharacters(in: .whitespaces)
          if candidate.isEmpty || startsBlock(candidate) { break }
          paragraph.append(candidate)
          index += 1
        }
        blocks.append(.paragraph(paragraph.joined(separator: " ")))
      }

      return blocks
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
      let count = line.prefix(while: { $0 == "#" }).count
      guard (1...6).contains(count), line.dropFirst(count).first?.isWhitespace == true else {
        return nil
      }
      let text = line.dropFirst(count).trimmingCharacters(in: .whitespaces)
      return text.isEmpty ? nil : (count, text)
    }

    private static func listMarker(in line: String) -> ListMarker? {
      guard let first = line.first else { return nil }
      if ["-", "*", "+"].contains(first), line.dropFirst().first?.isWhitespace == true {
        let content = line.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
        return ListMarker(ordered: false, content: String(content))
      }

      guard let markerIndex = line.firstIndex(where: { $0 == "." || $0 == ")" }),
        markerIndex > line.startIndex,
        line[..<markerIndex].allSatisfy(\.isNumber),
        line[line.index(after: markerIndex)...].first?.isWhitespace == true
      else { return nil }
      let content = line[line.index(after: markerIndex)...]
        .drop(while: { $0 == " " || $0 == "\t" })
      return ListMarker(ordered: true, content: String(content))
    }

    private static func codeFence(in line: String) -> String? {
      for fence in ["```", "~~~"] where line.hasPrefix(fence) { return fence }
      return nil
    }

    private static func isQuoteLine(_ line: String) -> Bool {
      line == ">" || line.hasPrefix("> ") || line.hasPrefix(">\t")
    }

    private static func isThematicBreak(_ line: String) -> Bool {
      ["---", "***", "___"].contains { marker in
        line.count >= 3 && line.allSatisfy { $0 == marker.first }
      }
    }

    private static func setextHeadingLevel(in line: String) -> Int? {
      guard line.count >= 1 else { return nil }
      if line.allSatisfy({ $0 == "=" }) { return 1 }
      if line.allSatisfy({ $0 == "-" }) { return 2 }
      return nil
    }

    private static func startsBlock(_ line: String) -> Bool {
      heading(in: line) != nil || codeFence(in: line) != nil || isThematicBreak(line)
        || isQuoteLine(line) || listMarker(in: line) != nil
    }
  }
#endif

struct RunDetail: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  let run: AgentRun
  #if os(iOS)
    @State private var codexOpenFailed = false
    @State private var sessionIDCopied = false
  #endif
  #if os(macOS)
    @State private var isShowingSessionPicker = false
  #endif
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        RunBadge(run: run)
        Spacer()
        Text(run.kind.rawValue.capitalized).stageFont(.caption).foregroundStyle(.secondary)
      }
      Text(run.summary).stageFont(.callout).textSelection(.enabled)
      if run.kind != .task {
        Text(run.modelConfiguration?.summary ?? "Model not recorded")
          .stageFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
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
        if let context = run.handoffContext {
          Button("Copy task context", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(context, forType: .string)
          }
        }
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
            if run.kind != .task, run.source != .codexDesktop {
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
        }
        if run.source == .codexDesktop {
          Button(
            run.threadID == nil ? "Link Codex Desktop session" : "Change linked session",
            systemImage: "link"
          ) {
            isShowingSessionPicker = true
          }
          .disabled(model.runner?.isBusy == true)
          .sheet(isPresented: $isShowingSessionPicker) {
            DesktopSessionPicker(run: run)
          }
        }
        if run.threadID != nil {
          Button(
            model.runStatusRefreshInFlight.contains(run.id) ? "Refreshing…" : "Refresh status",
            systemImage: "arrow.clockwise"
          ) {
            Task { await model.refreshCodexStatus(run.id) }
          }
          .disabled(model.runStatusRefreshInFlight.contains(run.id))
        }
        if let path = run.workDirectory {
          Button("Reveal working folder", systemImage: "folder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
          }
        }
      #else
        if let thread = run.threadID {
          Button("Open in Codex", systemImage: "arrow.up.right.square") {
            guard let url = URL(string: "codex://threads/\(thread)") else {
              codexOpenFailed = true
              return
            }
            openURL(url) { accepted in
              if !accepted { codexOpenFailed = true }
            }
          }
          if codexOpenFailed {
            HStack(alignment: .firstTextBaseline) {
              Text("Continue in Codex on your Mac.")
                .stageFont(.caption).foregroundStyle(.secondary)
              Spacer(minLength: 8)
              Button(sessionIDCopied ? "Copied" : "Copy session ID", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = thread
                sessionIDCopied = true
              }
            }
          }
        }
      #endif
      HStack {
        #if os(macOS)
          if !model.isConnectedPhone, run.source != .codexDesktop, run.kind == .task,
            [.failed, .interrupted, .cancelled, .succeeded].contains(run.status)
          {
            Button("Retry in Codex", systemImage: "arrow.clockwise") {
              Task { await model.rerunInCodex(run.id) }
            }
          } else if !model.isConnectedPhone, run.source != .codexDesktop, model.autoInvokeCodex,
            model.library.projects.first(where: { $0.id == run.projectID })?.automationEnabled
              == true,
            [.failed, .interrupted, .cancelled].contains(run.status)
          {
            Button(
              run.modelConfiguration == nil ? "Review model and retry" : "Retry in same session",
              systemImage: "arrow.clockwise"
            ) {
              Task { await model.retry(run.id) }
            }
          }
        #endif
        if !model.isConnectedPhone, run.source != .codexDesktop, run.status.isActive {
          Button("Stop run", systemImage: "stop.circle", role: .destructive) {
            Task { await model.stop(run.id) }
          }
        }
      }
      Text(run.updatedAt, format: .dateTime.month().day().hour().minute()).stageFont(.caption2)
        .foregroundStyle(.tertiary)
    }
    #if os(iOS)
      .onChange(of: run.threadID) { _, _ in
        codexOpenFailed = false
        sessionIDCopied = false
      }
    #endif
  }
}

#if os(macOS)
  private struct DesktopSessionPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let run: AgentRun
    @State private var sessions: [DesktopThreadCandidate] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var linkingID: String?

    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text("Link Codex Desktop session").stageFont(.title3, weight: .bold)
        Text(
          "Choose the exact thread where you pasted this task's prompt. Linking resumes observation only; it does not submit a turn."
        )
        .stageFont(.callout).foregroundStyle(.secondary)
        if loading { ProgressView("Loading sessions…") }
        if let errorMessage { Text(errorMessage).foregroundStyle(.orange).textSelection(.enabled) }
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(sessions) { session in
              Button {
                linkingID = session.id
                Task {
                  do {
                    try await model.runner?.linkDesktopSession(runID: run.id, threadID: session.id)
                    dismiss()
                  } catch { errorMessage = error.localizedDescription }
                  linkingID = nil
                }
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(session.name).stageFont(.body, weight: .semibold)
                    Spacer()
                    Text(session.status.capitalized).stageFont(.caption).foregroundStyle(.secondary)
                  }
                  if !session.preview.isEmpty {
                    Text(session.preview).stageFont(.caption).foregroundStyle(.secondary).lineLimit(
                      2)
                  }
                  Text(session.id).stageFont(.caption2).foregroundStyle(.tertiary).textSelection(
                    .enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
              }
              .buttonStyle(.plain)
              .disabled(linkingID != nil)
            }
          }
        }
        if !loading && sessions.isEmpty && errorMessage == nil {
          ContentUnavailableView("No sessions found", systemImage: "bubble.left.and.bubble.right")
        }
        HStack {
          Spacer()
          Button("Cancel") { dismiss() }
        }
      }
      .padding(20)
      .frame(minWidth: 460, minHeight: 360)
      .task {
        do { sessions = try await model.runner?.desktopThreads(for: run.id) ?? [] } catch {
          errorMessage = error.localizedDescription
        }
        loading = false
      }
    }
  }
#endif

struct ActivityPanel: View {
  @Environment(AppModel.self) private var model
  private var visibleRuns: [AgentRun] {
    model.activeRuns.filter {
      model.selectedProjectID == nil || $0.projectID == model.selectedProjectID
    }.sorted { $0.createdAt > $1.createdAt }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          Text("Activity").stageFont(.title2, weight: .bold)
          Spacer()
          Text("\(visibleRuns.count) active").stageFont(.caption).foregroundStyle(.secondary)
        }
        Text(model.runnerMessage).stageFont(.callout).foregroundStyle(.secondary)
        if visibleRuns.isEmpty {
          ContentUnavailableView(
            "Nothing running", systemImage: "sparkles",
            description: Text(
              "Active run progress and approvals appear here. Open saved sessions from a task. Enabling automation alone never starts work."
            ))
        }
        ForEach(visibleRuns) { run in
          VStack(alignment: .leading, spacing: 12) {
            Text(model.library.tasks.first { $0.id == run.taskID }?.title ?? "Task").stageFont(
              .headline)
            RunDetail(run: run)
          }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        }
      }.padding(20)
    }.background(Palette.canvas)
  }
}
