#if os(macOS)
  import Foundation

  enum TaskHandoffPrompt {
    static func make(for task: WorkItem, project: Project) -> String {
      ImplementationHandoffPrompt.make(for: task, project: project)
    }

    static func copyableContext(for task: WorkItem, project: Project) -> String? {
      if let path = task.planPath,
        let url = try? PlanFileStore.resolve(
          projectDirectory: project.directory, relativePath: path),
        let text = try? String(contentsOf: url, encoding: .utf8),
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return text
      }
      return make(for: task, project: project)
    }
  }
#endif
