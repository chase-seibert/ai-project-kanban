import SwiftUI

#if os(macOS)
  import AppKit
#endif

#if os(iOS)
  import UIKit
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
                || (!model.isConnectedPhone && project.automationEnabled && project.directory.isEmpty)
                || (model.isConnectedPhone && !isNew
                  && model.library.projects.first(where: { $0.id == project.id }).map {
                    $0.executionProfile == project.executionProfile
                      && $0.modelOverride == project.modelOverride
                  } == true))
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
}

#if os(macOS)
  struct ProjectHeaderControls: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var savingWorktree = false
    @State private var worktreeError: String?
    @State private var showingModel = false
    @State private var modelDraft: CodexModelConfiguration?
    @State private var savingModel = false
    @State private var modelError: String?

    private var effectiveModel: (configuration: CodexModelConfiguration, scope: CodexModelScope) {
      CodexModelResolver.effective(
        task: nil, project: project.modelOverride, global: model.globalModelConfiguration)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 10) {
          Toggle(
            "Worktrees",
            isOn: Binding(
              get: {
                model.library.projects.first(where: { $0.id == project.id })?.usesWorktrees ?? false
              },
              set: saveWorktreePreference)
          )
          .toggleStyle(.switch)
          .accessibilityLabel("Use managed worktrees for implementation")
          .help(
            "Dirty repositories use an isolated worktree. Turn off to use the project folder directly."
          )
          .disabled(savingWorktree)

          Button {
            modelDraft = model.library.projects.first(where: { $0.id == project.id })?.modelOverride
            modelError = nil
            showingModel = true
          } label: {
            Label("\(effectiveModel.configuration.summary)", systemImage: "cpu")
              .labelStyle(.titleAndIcon)
              .lineLimit(1)
          }
          .buttonStyle(.borderless)
          .help(
            "Project model · \(effectiveModel.scope.title). Task model choices still take precedence."
          )
          .popover(isPresented: $showingModel, arrowEdge: .bottom) {
            modelPopover.frame(width: 310).padding(14)
          }

          if savingWorktree || savingModel {
            ProgressView().controlSize(.small).help("Saving project settings")
          } else if let error = worktreeError ?? modelError {
            Image(systemName: "exclamationmark.circle.fill")
              .foregroundStyle(.orange)
              .accessibilityLabel("Project settings save failed")
              .help(error)
          }
        }
        ProjectGitStatusView(project: project, taskID: nil, showDeployedAction: true)
      }
    }

    private var modelPopover: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Project model").stageFont(.headline)
        Text("Effective: \(effectiveModel.configuration.summary) · \(effectiveModel.scope.title)")
          .stageFont(.caption).foregroundStyle(.secondary)
        CodexModelOverrideEditor(
          configuration: Binding(
            get: { modelDraft }, set: { modelDraft = $0 }),
          inherited: model.globalModelConfiguration,
          inheritLabel: "Use global model settings",
          catalog: model.modelCatalog)
        if let error = model.modelCatalogError {
          Text(error).stageFont(.caption).foregroundStyle(.orange)
        }
        if let modelError {
          Text(modelError).stageFont(.caption).foregroundStyle(.orange)
        }
        HStack {
          Button("Cancel") { showingModel = false }
            .keyboardShortcut(.cancelAction)
          Spacer()
          Button("Save") { saveModelPreference() }
            .keyboardShortcut(.defaultAction)
            .disabled(savingModel || modelDraft == project.modelOverride)
        }
      }
    }

    private func saveWorktreePreference(_ enabled: Bool) {
      guard !savingWorktree,
        var updated = model.library.projects.first(where: { $0.id == project.id })
      else { return }
      updated.usesWorktrees = enabled
      savingWorktree = true
      worktreeError = nil
      Task {
        let saved = await model.perform(.editProject(updated))
        if !saved { worktreeError = model.error ?? "Could not save the worktree setting." }
        savingWorktree = false
      }
    }

    private func saveModelPreference() {
      guard !savingModel,
        var updated = model.library.projects.first(where: { $0.id == project.id })
      else { return }
      updated.modelOverride = modelDraft
      savingModel = true
      modelError = nil
      Task {
        if await model.perform(.editProject(updated)) {
          showingModel = false
        } else {
          modelError = model.error ?? "Could not save the project model."
        }
        savingModel = false
      }
    }
  }

  struct ProjectGitStatusView: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let taskID: UUID?
    var showDeployedAction = false

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
        if let hash = currentProject.deployedCommitHash {
          HStack(spacing: 5) {
            Text("Deployed: \(String(hash.prefix(12)))").monospaced()
              .textSelection(.enabled)
            if let date = currentProject.deployedAt {
              Text("· \(date.formatted(date: .abbreviated, time: .shortened))")
                .foregroundStyle(.secondary)
            }
          }
        } else {
          Text("No deployed revision recorded").foregroundStyle(.secondary)
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
        if showDeployedAction {
          Button("Record current HEAD as deployed") {
            Task { await model.recordDeployedRevision(projectID: project.id) }
          }
          .disabled(isBusy || status?.head == nil)
          .help("Save the latest commit hash and time as this project's deployed revision.")
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
  @State private var promptCopied = false
  @State private var planPromptCopied = false
  #if os(iOS)
    @State private var planMarkdown: String?
    @State private var planLoadError: String?
    @State private var planLoading = false
    @State private var codexActionLoading = false
  #endif
  #if os(macOS)
    @FocusState private var focusedEditor: TaskEditorField?
    private enum TaskEditorField: Hashable {
      case title, notes, planPath, planFeedback
    }
  #endif
  var item: WorkItem? { model.library.tasks.first { $0.id == taskID } }
  #if os(macOS)
    private var handoffProject: Project? {
      guard let item else { return nil }
      return model.library.projects.first { $0.id == item.projectID }
    }
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
  var body: some View {
    ScrollView {
      if let item {
        VStack(alignment: .leading, spacing: 22) {
          HStack {
            Label(item.section.title, systemImage: item.section.symbol).stageFont(
              .subheadline, weight: .semibold
            ).foregroundStyle(item.section.color)
            Text(item.status.title).stageFont(.caption, weight: .medium)
              .padding(.horizontal, 8).padding(.vertical, 4)
              .background(
                item.status.isAttentionState
                  ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.10),
                in: Capsule())
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
          #if os(macOS)
            if !model.isConnectedPhone {
              VStack(alignment: .leading, spacing: 8) {
                Text("You run in Codex").stageFont(.headline)
                Button("Launch Codex (⌘R)", systemImage: "arrow.up.right.square") {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(
                  hasReadableAttachedPlan ? "Revise plan in Codex" : "Plan in Codex",
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
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("StageChase runs").stageFont(.headline).padding(.top, 6)
                Button("Run with StageChase", systemImage: "play.fill") {
                  model.requestRunnerRun(
                    item, kind: item.section == .planning ? .planning : .implementation)
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
                      ? "Start this task in StageChase. You will review the model and confirm first."
                      : "Choose a repository folder in Project settings before running this task."
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(
                  hasReadableAttachedPlan ? "Revise plan with StageChase" : "Plan with StageChase",
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

                Divider().padding(.vertical, 3)
                Button(
                  model.taskRefreshInFlight.contains(taskID) ? "Refreshing…" : "Refresh",
                  systemImage: "arrow.clockwise"
                ) {
                  Task { await model.refreshTask(taskID, preservingEdits: edited) }
                }
                .disabled(model.taskRefreshInFlight.contains(taskID))
                .help("Refresh the saved task, plan, and linked Codex activity.")
                .frame(maxWidth: .infinity, alignment: .leading)
                if let refreshMessage = model.taskRefreshMessages[taskID] {
                  Text(refreshMessage)
                    .stageFont(.caption)
                    .foregroundStyle(refreshMessage.contains("failed") ? .orange : .secondary)
                    .textSelection(.enabled)
                }
              }
            }
          #endif
          #if os(iOS)
            if model.isConnectedPhone {
              VStack(alignment: .leading, spacing: 10) {
                Label("Codex on Mac", systemImage: "desktopcomputer").stageFont(.headline)
                HStack {
                  Button("Plan in Codex", systemImage: "sparkles") {
                    requestCodexAction(.plan, item: item)
                  }
                  .disabled(codexActionLoading || item.completed)
                  Button("Run with StageChase", systemImage: "play.fill") {
                    requestCodexAction(.run, item: item)
                  }
                  .disabled(
                    codexActionLoading || item.completed
                      || ![.planning, .implementing].contains(item.section)
                      || model.library.latestRun(for: item.id)?.status.isActive == true)
                }
                Text(
                  "Planning opens Codex Desktop on the Mac. Running opens the Mac confirmation first."
                )
                .stageFont(.caption).foregroundStyle(.secondary)
                if let message = model.phoneCodexActionMessage {
                  Text(message).stageFont(.callout)
                    .foregroundStyle(message.localizedCaseInsensitiveContains("could not") ? .orange : .secondary)
                    .textSelection(.enabled)
                }
              }
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
            }
          #endif
          #if os(macOS)
            if !model.isConnectedPhone, let project = handoffProject {
              Divider()
              ProjectGitStatusView(project: project, taskID: item.id)
            }
          #endif
          if draft != nil {
            TextField("Title", text: draftBinding(\.title), axis: .vertical).stageFont(
              .title2, weight: .bold
            ).textFieldStyle(.plain)
              #if os(macOS)
                .focused($focusedEditor, equals: .title)
              #endif
              .disabled(model.planFeedbackInFlight.contains(taskID))
            if model.isConnectedPhone {
              LabeledContent("Priority", value: draft?.priority?.title ?? "No priority")
            } else {
              HStack {
                Text("Priority").foregroundStyle(.secondary)
                Picker(
                  "Priority",
                  selection: Binding(
                    get: { draft?.priority },
                    set: {
                      draft?.priority = $0
                      edited = true
                    }
                  )
                ) {
                  Text("No priority").tag(TaskPriority?.none)
                  ForEach(TaskPriority.allCases) { priority in
                    Text("\(priority.rawValue) · \(priority.title)").tag(
                      TaskPriority?.some(priority))
                  }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
              }
              .disabled(model.planFeedbackInFlight.contains(taskID))
            }
            VStack(alignment: .leading, spacing: 8) {
              Text(usesPlanFeedbackField ? "TASK CONTEXT AND PLAN FEEDBACK" : "TASK CONTEXT")
                .stageFont(.caption, weight: .semibold).foregroundStyle(.secondary)
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
                if usesPlanFeedbackField, let message = model.planFeedbackMessages[taskID] {
                  Text(message.text).stageFont(.caption)
                    .foregroundStyle(message.isError ? .red : .secondary)
                    .textSelection(.enabled)
                }
              #endif
            }
            if !model.isConnectedPhone {
              VStack(alignment: .leading, spacing: 8) {
                Text("SAVED PLAN").stageFont(.caption, weight: .semibold).foregroundStyle(
                  .secondary)
                Text(item.planPath ?? "No saved plan").stageFont(.callout).foregroundStyle(
                  .secondary
                )
                .disabled(model.planFeedbackInFlight.contains(taskID))
                #if os(macOS)
                  if let path = item.planPath,
                    let project = model.library.projects.first(where: { $0.id == item.projectID }),
                    hasReadablePlan(path: path, project: project)
                  {
                    Button("Open plan", systemImage: "doc.text") {
                      NSWorkspace.shared.open(
                        URL(fileURLWithPath: project.directory).appendingPathComponent(path))
                    }
                  }
                #endif
              }
            }
            #if os(iOS)
              if model.isConnectedPhone {
                VStack(alignment: .leading, spacing: 10) {
                  HStack {
                    Text("SAVED PLAN").stageFont(.caption, weight: .semibold)
                      .foregroundStyle(.secondary)
                    Spacer()
                    Button(planMarkdown == nil ? "Open plan" : "Reload", systemImage: "doc.text") {
                      loadPlanFromMac(item)
                    }
                    .disabled(planLoading)
                  }
                  if planLoading { ProgressView("Loading plan from Mac…") }
                  if let planLoadError {
                    Text(planLoadError).stageFont(.callout).foregroundStyle(.orange)
                  }
                  if let planMarkdown {
                    PlanMarkdownView(markdown: planMarkdown)
                  }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
              }
            #endif
            if edited {
              Button("Save changes (⌘Return)") { saveTaskEdits() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
            }
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
          }
          HStack {
            Spacer()
            if !model.isConnectedPhone {
              Button(item.completed ? "Reopen" : "Complete", systemImage: "checkmark.circle") {
                setTaskCompleted(!item.completed)
              }
            }
          }
          Divider()
          VStack(alignment: .leading, spacing: 12) {
            Label("Codex activity", systemImage: "sparkles").stageFont(.headline)
            if let update = item.latestCodexUpdate {
              Text("Latest Codex update").stageFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
              Text(update).textSelection(.enabled)
              if let date = item.latestCodexUpdateAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                  .stageFont(.caption2).foregroundStyle(.secondary)
              }
            }
            if let run = model.library.latestRun(for: taskID) {
              RunDetail(run: run)
            } else {
              Text("No agent has worked on this task.").stageFont(.subheadline, weight: .medium)
              #if os(iOS)
                Text(
                  model.isConnectedPhone
                    ? "Use the Codex on Mac buttons above to request a plan or run. The Mac confirms each StageChase run before Codex starts."
                    : model.autoInvokeCodex && model.selectedProject?.automationEnabled == true
                      ? "Confirmed moves can start Codex. Task placement stays under your control."
                      : "Launch the task in Codex Desktop. Task placement stays under your control."
                )
                .stageFont(.callout).foregroundStyle(.secondary)
              #else
                Text(
                  model.autoInvokeCodex && model.selectedProject?.automationEnabled == true
                    ? "Confirmed moves can start Codex. Task placement stays under your control."
                    : "Launch the task in Codex Desktop. Task placement stays under your control."
                )
                .stageFont(.callout).foregroundStyle(.secondary)
              #endif
            }
          }
          if !model.isConnectedPhone {
            Divider()
            Button("Delete task (Delete)", role: .destructive) { deleting = true }
              .buttonStyle(.borderless)
              .disabled(model.planFeedbackInFlight.contains(taskID))
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
        promptCopied = false
        planPromptCopied = false
        #if os(iOS)
          planMarkdown = nil
          planLoadError = nil
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
      .onChange(of: item?.revision) { _, _ in if !edited { draft = item } }
      .onChange(of: draft?.notes) { _, value in
        guard !usesPlanFeedbackField, let value else { return }
        scheduleNotesSave(value)
      }
      #if os(macOS)
        .onChange(of: focusedEditor) { previous, current in
          if previous == .planFeedback, current != .planFeedback { appendPlanFeedbackOnBlur() }
        }
      #endif
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
    notesSaveTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(650))
      guard !Task.isCancelled, let currentItem = self.item else { return }
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
      }
    }
  }

  #if os(macOS)
    private func appendPlanFeedbackOnBlur() {
      guard usesPlanFeedbackField, !edited, let item else { return }
      let text = model.planFeedbackDraft(for: taskID)
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      Task {
        let saved = await model.appendPlanFeedback(
          taskID: taskID, expectedRevision: item.revision, text: text)
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

    private func loadPlanFromMac(_ item: WorkItem) {
      guard !planLoading else { return }
      planLoading = true
      planLoadError = nil
      Task {
        do { planMarkdown = try await model.readPlanFromMac(item) }
        catch { planLoadError = error.localizedDescription }
        planLoading = false
      }
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
      edited || model.planFeedbackInFlight.contains(taskID)
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

#if os(iOS)
  private struct PlanMarkdownView: View {
    let markdown: String
    private var rendered: AttributedString {
      (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
    var body: some View {
      Text(rendered)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
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
            if run.kind != .task {
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
        if run.kind == .task, run.threadID != nil {
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
