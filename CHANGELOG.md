# Changelog

## 2026-10-01

- Corrected generated manual task prompts to move successful implementation work
  to Review and leave it incomplete for user review.
- Generated plan filenames now use readable normalized task-title slugs with
  full task-ID suffixes; planning, implementation, and manual prompts start
  with the task title, and Codex sessions use the task title alone.
- Added Mac Git status in project headers and task details, including the
  current branch and commit hash, plus a task action that stages all project
  changes and commits with the task title as its message. Added an optional
  per-project deployed-revision checkpoint recorded from current `HEAD`.
- Added unread badges for task column and completion changes. Project badges count
  changed tasks, while task badges clear independently when a task is opened.
- Added Mac-only Copy plan prompt and Plan in Codex task-detail actions. Their
  shared plan-only prompt carries the plan-format preference, preserves the
  selected path, and attaches successful plans without completing the task.
- Lane quick capture now turns pasted Apple Notes unchecked checklist entries
  into separate tasks, while preserving explicit Codex confirmation for later
  moves into automated stages.
- Start the loopback-only Codex Desktop MCP listener automatically on app launch
  by default, with a persistent Stop/Start choice in Connection settings.
- Added Mac project-header controls for a per-project managed-worktree toggle
  and model override. Worktrees default off for existing and new projects;
  project-folder runs with local changes are explained in the UI.
- Added an opt-in, loopback-only MCP task server for Codex Desktop. It lists
  projects/tasks, reads tasks, creates Inbox tasks, and supports explicit,
  revision-checked stage and completion changes through the local library.
- Persisted bounded MCP operation receipts in the same save as task changes so
  retried writes are idempotent and visible to normal board/phone sync refresh.
- Added revision-checked MCP plan attachment for readable, nonempty Markdown
  files inside the project folder. Synchronized local and reusable agent
  instructions to attach plans and move successful planning tasks to Planned,
  and to complete tasks after successful implementation.
- Added a Connection settings control and Codex CLI setup command. MCP task
  operations never start StageChase's Codex runner. Added explicit external
  session bookkeeping and a bounded latest update visible in task detail.
- Added Copy prompt and Launch Codex actions to task details. Both use the
  same prompt with stable project/task IDs and a readable project-relative
  plan path when available; successful MCP-reported work marks that task
  complete without changing its stage.

## 2026-10-01

- Added optional task priorities, priority-first ordering within columns, sync
  snapshot support, and keyboard navigation and task actions on Mac. Added Task
  and Navigate menus that list shortcuts, plus shortcut hints on task actions.
- Opening a task no longer focuses its editable fields automatically, keeping
  board shortcuts available until a field is deliberately selected.
- Return now submits either task deletion confirmation dialog.

## 2026-09-30

- Added a Mac-wide automatic-invocation setting and task-level Codex Desktop
  handoffs that save/copy context, open a linked session, support manual status
  refresh, and allow retry/rerun from task detail.
- Made task columns independent of plans and Codex state; stage moves remain
  available during runs, and Codex outcomes no longer move tasks automatically.
- Reserve each confirmed planning run's task-relative plan path before the run
  starts, reuse it on retry, and require a readable nonempty file at that path
  before reporting planning success.
- Added an editable Mac-local plan format prompt with user requirements,
  architecture/data model, basic test cases, and high-level implementation
  sections, applied only to future planning turns.
- Added Mac-local Codex approval modes: Codex no-prompt policy by default,
  explicit Ask me decisions, and one-time automatic approval for supported
  command/file requests without widening workspace or network access.
- Added Mac task-detail feedback that appends typed or dictated raw text to the
  saved plan under a user-feedback heading, without starting Codex.
- Added Close Codex session for explicit desktop handoff, preserving saved
  results and workspaces while pausing the runner queue until a later action.
- Prevented concurrent Mac listener starts from binding twice to port 47928.
  Port conflicts now explain how to release the port before retrying.
- Added a saved phone automatic-sync toggle plus board pull-to-refresh and an
  explicit Sync Now action that work even when automatic syncing is off.
- Replaced long Mac and iPhone activity timelines with compact run details and
  Codex session handoff, retaining full event history in storage.

## 2026-09-29

- Replaced prototype code with independently identified multi-project boards.
- Rebuilt both native interfaces: top-aligned lanes, quick capture, drag/drop,
  card reordering, task detail, activity, and explicit project creation.
- Fixed iPhone compatibility-mode sizing with generated launch configuration.
- Added versioned SwiftData/SQLite, legacy import, preserved backups,
  export/empty-library restore, and manual-task undo/redo.
- Added Codex app-server integration with durable runs, progress, logs, approvals,
  session links, stop/retry, structured outcomes, and dirty-checkout isolation.
- Added Latest Luna · High model defaults, project/task overrides, model
  catalog validation, and saved model/effort snapshots for confirmed runs and retries.
- Added model/persistence regressions and offline runner integration fixtures.
- Added an experimental local Wi-Fi sync path: temporary-code pairing, encrypted
  protocol messages, authoritative Mac receipts, phone replica cache, and a
  durable phone outbox. Pairing is automatic from the temporary code. Added a
  Connection tab on phone and in Mac Settings with progress, editable endpoint,
  and bounded timestamped network-exchange logs. The Mac listener resumes on
  app launch after the user has enabled it. Device-level acceptance remains open.

## 2026-09-28

- Created the StageChase macOS and iOS SwiftUI app targets.
- Added the shared fixed-stage data model, local persistence, revisioned task
  transitions, activity history, and structured automation references.
- Added board/task editing interfaces for Mac and iPhone.
- Added Swift package tests and Makefile build/test/simulator/device targets.
