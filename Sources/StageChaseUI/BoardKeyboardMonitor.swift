#if os(macOS)
  import AppKit
  import SwiftUI

  struct BoardKeyboardMonitor: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSView {
      let view = NSView(frame: .zero)
      context.coordinator.install(for: view)
      return view
    }
    func updateNSView(_ view: NSView, context: Context) {
      context.coordinator.model = model
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
      coordinator.remove()
    }

    @MainActor final class Coordinator {
      var model: AppModel
      weak var view: NSView?
      var monitor: Any?
      init(model: AppModel) { self.model = model }

      func install(for view: NSView) {
        self.view = view
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
          guard let self, self.view?.window === NSApp.keyWindow else { return event }
          return self.handle(event)
        }
      }

      func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
      }

      private func handle(_ event: NSEvent) -> NSEvent? {
        if NSWorkspace.shared.isVoiceOverEnabled { return event }
        let command = event.modifierFlags.contains(.command)
        let firstResponder = view?.window?.firstResponder
        let isEditing = firstResponder is NSTextView || firstResponder is NSTextField
        if isEditing {
          // Command-Return is handled by the Save changes button's keyboard shortcut.
          return event
        }

        if command {
          switch event.keyCode {
          case 123:
            moveSelected(by: -1)
            return nil
          case 124:
            moveSelected(by: 1)
            return nil
          case 8:
            copySelected()
            return nil
          case 17:
            guard model.selectedProjectID != nil else { return nil }
            model.sheet = .newTask(model.boardFocusedStage)
            return nil
          case 15:
            launchSelected()
            return nil
          default: return event
          }
        }

        switch event.keyCode {
        case 126:
          moveTaskSelection(by: -1)
          return nil
        case 125:
          moveTaskSelection(by: 1)
          return nil
        case 123:
          moveFocus(by: -1)
          return nil
        case 124:
          moveFocus(by: 1)
          return nil
        case 51, 117:
          if selectedTask != nil { model.taskPendingDeletionID = selectedTask?.id }
          return nil
        default: break
        }
        guard let digit = event.charactersIgnoringModifiers,
          let value = Int(digit), (1...3).contains(value), let item = selectedTask
        else { return event }
        Task { await model.setPriority(TaskPriority(rawValue: value), for: item.id) }
        return nil
      }

      private var selectedTask: WorkItem? {
        guard let id = model.boardSelectedTaskID ?? model.selectedTaskID else { return nil }
        return model.library.tasks.first { $0.id == id }
      }

      private func moveTaskSelection(by offset: Int) {
        guard model.selectedProjectID != nil else { return }
        let items = model.items(model.boardFocusedStage)
        guard !items.isEmpty else {
          model.boardSelectedTaskID = nil
          return
        }
        let current = items.firstIndex { $0.id == model.boardSelectedTaskID }
        let next = min(
          items.count - 1, max(0, (current ?? (offset > 0 ? -1 : items.count)) + offset))
        model.boardSelectedTaskID = items[next].id
      }

      private func moveFocus(by offset: Int) {
        let stages = WorkflowStage.allCases
        guard let index = stages.firstIndex(of: model.boardFocusedStage) else { return }
        let targetIndex = index + offset
        guard stages.indices.contains(targetIndex) else { return }
        let stage = stages[targetIndex]
        model.boardFocusedStage = stage
        if let selectedTask, selectedTask.stage == stage { return }
        model.boardSelectedTaskID = model.items(stage).first?.id
      }

      private func moveSelected(by offset: Int) {
        guard let item = selectedTask,
          let index = WorkflowStage.allCases.firstIndex(of: item.stage)
        else { return }
        let destination = index + offset
        guard WorkflowStage.allCases.indices.contains(destination) else { return }
        model.requestMove(item, to: WorkflowStage.allCases[destination])
      }

      private func copySelected() {
        guard let item = selectedTask,
          let project = model.library.projects.first(where: { $0.id == item.projectID })
        else { return }
        guard let text = TaskHandoffPrompt.copyableContext(for: item, project: project) else {
          return
        }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
          model.error = "The task context could not be copied to the clipboard."
          return
        }
      }

      private func launchSelected() {
        guard let item = selectedTask else { return }
        model.selectedTaskID = item.id
        model.launchTaskOnSelectionID = item.id
      }
    }
  }
#endif
