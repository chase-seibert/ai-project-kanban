import Foundation

enum MobileTaskHandoffPrompt {
  enum Intent: Equatable {
    case planning
    case implementation
  }

  static func primaryIntent(for task: WorkItem) -> Intent {
    if task.section == .inbox
      || (task.section == .planning && task.status != .planApproved)
    {
      return .planning
    }
    return .implementation
  }

  static func make(
    for task: WorkItem,
    project: Project,
    intent: Intent
  ) -> String {
    switch intent {
    case .planning:
      PlanHandoffPrompt.make(for: task, project: project, formatPrompt: "")
    case .implementation:
      ImplementationHandoffPrompt.make(for: task, project: project)
    }
  }
}
