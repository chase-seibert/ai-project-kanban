import AppKit
import SwiftUI

@main struct StageChaseMacApp: App {
  @State private var model = AppModel()
  @AppStorage("textScale") private var textScale = 1.0
  var body: some Scene {
    WindowGroup("StageChase") {
      RootView().environment(model).environment(\.stageTextScale, textScale).font(
        .system(size: 13 * textScale)
      )
      .frame(minWidth: 1050, minHeight: 620)
      .tint(.indigo)
    }.defaultSize(width: 1560, height: 900)
      .commands {
        CommandGroup(replacing: .newItem) {
          Button("New Task… (⌘N)") { model.sheet = .newTask(.inbox) }.keyboardShortcut("n")
            .disabled(
              model.selectedProject == nil)
          Button("New Project…") { model.sheet = .newProject }.keyboardShortcut(
            "n", modifiers: [.command, .shift])
        }
        CommandMenu("Task") {
          Button("New task in focused column (⌘T)") {
            guard model.selectedProjectID != nil else { return }
            model.sheet = .newTask(model.boardFocusedStage)
          }.disabled(model.selectedProjectID == nil)
          Divider()
          Button("Copy plan or prompt (⌘C)") {
            guard let item = selectedBoardTask(model, includeDetailSelection: true),
              let project = model.library.projects.first(where: { $0.id == item.projectID }),
              let text = TaskHandoffPrompt.copyableContext(for: item, project: project)
            else { return }
            NSPasteboard.general.clearContents()
            if !NSPasteboard.general.setString(text, forType: .string) {
              model.error = "The task context could not be copied to the clipboard."
            }
          }.disabled(selectedBoardTask(model, includeDetailSelection: true) == nil)
          Button("Save changes (⌘Return)") {
            model.saveTaskEditRequestedID = model.selectedTaskID
          }.disabled(model.selectedTaskID == nil)
          Button("Launch Codex (⌘R)") {
            guard let item = selectedBoardTask(model, includeDetailSelection: true) else { return }
            model.selectedTaskID = item.id
            model.launchTaskOnSelectionID = item.id
          }.disabled(selectedBoardTask(model, includeDetailSelection: true) == nil)
          Button("Delete selected task (Delete)") {
            model.taskPendingDeletionID = selectedBoardTask(model, includeDetailSelection: true)?.id
          }.disabled(selectedBoardTask(model, includeDetailSelection: true) == nil)
          Divider()
          Button("Set priority: High (1)") { setSelectedPriority(.high, model: model) }
            .disabled(selectedBoardTask(model, includeDetailSelection: false) == nil)
          Button("Set priority: Medium (2)") { setSelectedPriority(.medium, model: model) }
            .disabled(selectedBoardTask(model, includeDetailSelection: false) == nil)
          Button("Set priority: Low (3)") { setSelectedPriority(.low, model: model) }
            .disabled(selectedBoardTask(model, includeDetailSelection: false) == nil)
          Divider()
          Button("Move task to previous column (⌘←)") { moveSelectedTask(-1, model: model) }
            .disabled(!canMoveSelectedTask(-1, model: model))
          Button("Move task to next column (⌘→)") { moveSelectedTask(1, model: model) }
            .disabled(!canMoveSelectedTask(1, model: model))
        }
        CommandMenu("Navigate") {
          Button("Previous task (↑)") { moveTaskSelection(-1, model: model) }
          Button("Next task (↓)") { moveTaskSelection(1, model: model) }
          Divider()
          Button("Previous column (←)") { moveColumnFocus(-1, model: model) }
          Button("Next column (→)") { moveColumnFocus(1, model: model) }
        }
        CommandGroup(after: .toolbar) {
          Button("Show Activity") {
            model.selectedTaskID = nil
            model.showActivity.toggle()
          }.keyboardShortcut("a", modifiers: [.command, .shift])
          Divider()
          Button("Larger Text") { textScale = min(1.4, textScale + 0.05) }.keyboardShortcut("+")
          Button("Smaller Text") { textScale = max(0.85, textScale - 0.05) }.keyboardShortcut("-")
          Button("Actual Text Size") { textScale = 1 }.keyboardShortcut("0")
        }
      }
    Settings {
      AppSettings().environment(model).environment(\.stageTextScale, textScale)
        .font(.system(size: 13 * textScale))
    }
  }
}

@MainActor private func selectedBoardTask(_ model: AppModel, includeDetailSelection: Bool)
  -> WorkItem?
{
  let id = model.boardSelectedTaskID ?? (includeDetailSelection ? model.selectedTaskID : nil)
  guard let id else { return nil }
  return model.library.tasks.first { $0.id == id }
}

@MainActor private func setSelectedPriority(_ priority: TaskPriority, model: AppModel) {
  guard let item = selectedBoardTask(model, includeDetailSelection: false) else { return }
  Task { await model.setPriority(priority, for: item.id) }
}

@MainActor private func moveSelectedTask(_ offset: Int, model: AppModel) {
  guard let item = selectedBoardTask(model, includeDetailSelection: true),
    let index = WorkflowStage.allCases.firstIndex(of: item.stage)
  else { return }
  let target = index + offset
  guard WorkflowStage.allCases.indices.contains(target) else { return }
  model.requestMove(item, to: WorkflowStage.allCases[target])
}

@MainActor private func canMoveSelectedTask(_ offset: Int, model: AppModel) -> Bool {
  guard let item = selectedBoardTask(model, includeDetailSelection: true),
    let index = WorkflowStage.allCases.firstIndex(of: item.stage)
  else { return false }
  return WorkflowStage.allCases.indices.contains(index + offset)
}

@MainActor private func moveTaskSelection(_ offset: Int, model: AppModel) {
  guard model.selectedProjectID != nil else { return }
  let items = model.items(model.boardFocusedStage)
  guard !items.isEmpty else {
    model.boardSelectedTaskID = nil
    return
  }
  let current = items.firstIndex { $0.id == model.boardSelectedTaskID }
  let next = min(items.count - 1, max(0, (current ?? (offset > 0 ? -1 : items.count)) + offset))
  model.boardSelectedTaskID = items[next].id
}

@MainActor private func moveColumnFocus(_ offset: Int, model: AppModel) {
  let stages = WorkflowStage.allCases
  guard let index = stages.firstIndex(of: model.boardFocusedStage),
    stages.indices.contains(index + offset)
  else { return }
  let stage = stages[index + offset]
  model.boardFocusedStage = stage
  if let selected = selectedBoardTask(model, includeDetailSelection: false), selected.stage == stage
  {
    return
  }
  model.boardSelectedTaskID = model.items(stage).first?.id
}
