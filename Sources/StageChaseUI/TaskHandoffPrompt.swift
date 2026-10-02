#if os(macOS)
  import Foundation

  enum TaskHandoffPrompt {
    static func make(for task: WorkItem, project: Project) -> String {
      let readablePlanPath = task.planPath.flatMap { path in
        hasReadablePlan(path: path, project: project) ? path : nil
      }
      let taskBrief: String
      if let readablePlanPath {
        taskBrief = """
          Read and follow the existing task plan at the project-relative path `\(readablePlanPath)`.
          Use the task title and notes below as identifying context.
          """
      } else {
        taskBrief = """
          No readable saved plan is attached. Execute the task described by its title and notes below.
          """
      }
      let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
      return """
        Task: \(task.title)

        Execute this existing task in the repository opened in this Codex Desktop session. Follow this repository's AGENTS.md instructions. Use the StageChase MCP server (`stagechase`) to read and update the task; do not start or manage another Codex session.

        First call `read_task` with the exact project and task IDs below and verify the returned IDs match. Then inspect the task context and work on it.

        \(taskBrief)

        Project name: \(project.name)
        Project ID (`project_id`): \(project.id.uuidString.lowercased())
        Task ID (`task_id`): \(task.id.uuidString.lowercased())
        Task title: \(task.title)
        Task notes:
        \(notes.isEmpty ? "(No additional notes.)" : notes)

        When work actually begins, call `begin_task` with `activity_kind: "implementation"` and a fresh `operation_id`, and keep its returned `run_id` and task revision. Report concise progress through `report_task_update` when useful, always passing the latest task revision and saving the revision returned. On successful implementation, call `finish_task` with status `succeeded` and a concise final message, passing the latest revision; then move the task to `review` with the latest task revision and a fresh operation ID. Preserve the current completion flag; completion and reopening are actions the user controls in StageChase, and MCP has no completion action. If work fails, call `finish_task` with `failed` or `cancelled` as appropriate. If work needs user input, report that outcome through `report_task_update` with status `needsInput`. Use a fresh operation ID for each write; on revision conflict reread the task before deciding what to do. If the MCP is unavailable, do not claim the task was updated or moved.
        """
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

    private static func hasReadablePlan(path: String, project: Project) -> Bool {
      guard
        let url = try? PlanFileStore.resolve(
          projectDirectory: project.directory, relativePath: path),
        let contents = try? String(contentsOf: url, encoding: .utf8)
      else { return false }
      return !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }
#endif
