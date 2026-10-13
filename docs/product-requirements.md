# Product requirements

## Reversible project deletion

- As a user, I want to delete a project from Mac or iPhone and hide it from my
  active project list and Recent Tasks, so I can remove it from daily work.
- As a user, I want a Deleted Projects link and a Restore action on both devices,
  so I can bring back the same project with all tasks, history, attachments,
  settings, and repository files. There is no permanent deletion action.
- As a user, I want confirmation before deleting, a clear message when active
  runs prevent deletion, and a usable empty state when my last project is deleted.
- As a user, I want delete and restore commands to synchronize through the paired
  Mac, remain queued during outages, and reject stale lifecycle changes, so an
  old phone request cannot undo a newer restoration. Restore is required before
  changing tasks or starting new work in a deleted project.

## Foundation

- As a user, I want to create a board, so that different projects can have
  separate workflows.
- As a user, I want each task to have a short positive numeric ID unique across
  all projects, so that I can refer to it quickly without replacing its UUID.
  The Mac allocates IDs from a persistent increasing sequence; offline iPhone
  tasks show “ID pending” until accepted and reconciled by task UUID.
- As a user, I want three board sections, Inbox, Planning, and Implementing, so
  that the Mac board is simpler and the iPhone can show the same workflow.
- As a user, I want task status to be separate from section and completion, so
  that each task shows Triage, Planning, Plan Approved, Building, Waiting,
  Error, Quota, or Reviewing while completion remains an independent choice.
- As a user, I want to favorite tasks and assign High or Medium model tags from
  Mac or iPhone, so that I can identify important tasks and the expected model
  capability on either device. These tags do not change task priority or the
  model and reasoning effort selected for a Codex run.
- As a user, I want board quick filters for All, Favorites, High, and Medium
  that combine with search, project, section, and completed-task controls, so I
  can quickly narrow the current board without changing task data.
- As a user, I want High, Medium, and Favorites workspace views across projects
  on Mac and iPhone, so I can open those task collections directly from
  workspace navigation.
- As a user, I want to manually mark a Planning task with a saved plan as Plan
  Approved from Mac or iPhone, so that I can approve the plan on either device.
  Approval changes status only and does not move the task or start Codex.
- As a user, I want each board card to show one colored, icon-led task-status
  badge, while saved-plan details stay in task detail and Codex run history
  stays in task detail and Activity.
- As a user, I want to change task status from the card's status menu, its
  right-click or long-press menu, so that I can correct status without moving
  the task between board sections. Waiting, Error, and Quota remain system-set.
- As a user, I want fixed workspace views for Plan Approved, In Progress,
  Reviewing, and Recently Completed, so that common task filters are always one
  click away. Plan Approved includes ready-to-execute tasks across projects.
  Reviewing includes plans awaiting approval and implementation changes ready
  for review. In Progress includes tasks with active planning or implementation
  runs. Recently Completed is ordered and grouped by completion time. Workspace
  views keep cards in three equal-width columns, leaving unused columns empty
  when a day has fewer than three tasks.
- As a user, I want Triage gray, Planning and Building bright purple, Plan
  Approved blue, Reviewing green, and Waiting/Quota/Error yellow/orange/red, so
  that workflow progress and exceptions are visually distinct.
- As a user, I want successful implementation to move directly from Building
  to Reviewing and completion to stay an independent boolean, so that I do not
  need redundant ready-for-review or Done statuses.
- As a user, I want MCP moves from Implementing back to Planning rejected, so
  that automation cannot reverse board progress.
- As a user, I want Planning and Implementing tasks with Waiting, Error, Quota,
  and Reviewing statuses sorted first in that order, followed by Plan Approved
  tasks and then other tasks, so that work ready for my attention or the next
  stage is easy to find. Within each status group, most recently updated tasks
  come first; timestamp ties use a stable task-ID order.
- As a user, I want Inbox tasks ordered by creation time with the newest first,
  so newly captured work is easy to find. Creation-time ties use a stable
  task-ID order.
- As a user, I want the Mac sections shown as three side-by-side columns with
  vertical task lists and iPhone sections kept as horizontal pages, so each
  device retains a useful board layout.
- As a user, I want to capture and edit tasks, so that ideas are useful before
  planning begins.
- As a user, I want to edit a task title directly from its board card, so that
  I can correct it without opening task detail. The title stays multiline, only
  one card is editable at a time, and Return saves; Escape or Cancel discards
  the edit. Opening another title resolves and closes the previous edit.
- As a user, I want to paste an Apple Notes checklist into lane capture and
  create one task per unchecked item, so I can quickly bring a list into a board.
- As a user, I want to move tasks between Inbox, Planning, and Implementing, so
  that the board reflects my current intent.
- As a user, I want section placement to remain independent of plan availability
  and Codex run state, so the board reflects my intent.
- As a user, I want transitions and activity to be recorded, so that I can see
  what changed and why.
- As a user, I want to complete or reopen a task manually while Codex is Waiting
  or active, so that completion remains my decision.
- As a user, I want Mac and iPhone to show concise run status and progress
  instead of a long event timeline, so task detail and Activity stay readable
  and I can open the associated Codex session for its full history.
- As a user, I want to switch projects by tapping the selected project name on
  iPhone, so I can move between boards without returning to the project list.
- As a user, I want the iPhone board's bottom controls to select Inbox,
  Planning, and Implementing using the standard iOS tab bar, so I get familiar
  navigation and the system's native tab-bar material.
- As a user, I want Connection at the top of the iPhone board and the status
  card removed, so sync remains reachable while tasks gain vertical space.
- As a user, I want Activity and Settings to remain available from the board's
  overflow menu, so changing the bottom navigation does not remove those views.
- As a user, I want Project Git in the project menu, so I can inspect the
  paired Mac repository and confirm a project-wide commit from my phone.
- As a user, I want to create a project from my iPhone, so a new project is
  added to the paired Mac library and appears on both devices.
- As a user, I want task details to push onto the iPhone navigation stack, so
  the standard back button and swipe-back gesture return me to the board.
- As a user, I want the iPhone to offer a truthful Codex handoff, so it opens a
  supported thread URL or explains that I need to continue on Mac and can copy
  the session ID.
- As a user, I want stale phone task edits, moves, completion changes, and
  deletions to resolve by source edit time when they remain valid, so the latest
  applicable record wins across Mac and iPhone while exact timestamp ties favor
  the Mac.

## Task image attachments

- As a user, I want to attach an existing image from Mac or iPhone task detail,
  preview it, and remove it, so visual context stays with the task.
- On Mac, users can also paste an image from the clipboard into task attachments.
- As a user, I want paired devices to share attachment metadata during normal
  sync and transfer each image only when attaching or opening its preview, so
  snapshots stay small and previews work on demand.
- Image bytes live in separate durable files. Task records, SQLite rows, and
  snapshots contain stable IDs, media type, size, checksum, and display name
  only. Accept JPEG, PNG, and HEIC up to 4 MB and 8,192 pixels per dimension.
- Backups package task/library JSON and separate image files in a versioned
  archive. Legacy JSON-only backups remain restorable when they contain no image
  references, and restore still requires an empty library.

## Experimental local Wi-Fi sync

- As a user, I want to pair my iPhone with the Mac using a temporary code,
  without separate desktop confirmation, so that the phone shows the same project identities without
  merging libraries by name.
- As a user, I want supported phone edits to queue offline and reach the Mac
  once it is open on the same Wi-Fi network, so that temporary outages do not
  lose my intent.
- As a user, I want a pending count and last-sync time, so cached Mac state is
  not mistaken for a successful refresh, and I want a successful sync to resolve
  every queued change without leaving a conflict for me to handle.
- As a user, I want a Connection tab showing in-progress state, last result,
  editable saved endpoint, and timestamped request/response sizes and outcomes,
  so that I can diagnose failed reconnects without losing queued changes.
- As a user, I want to control automatic phone syncing and pull to refresh the
  board or tap Sync Now, so that I can choose between periodic updates and
  deliberate manual syncs without losing queued edits.
- As a user, I want **Refresh everything from Mac** to replace the phone replica
  with a complete Mac snapshot and discard every queued local change, even when
  incremental sync reports no changes. The action reports progress and the
  number of discarded changes; a failed refresh keeps the current replica and
  offline queue.
- As a user, I want polling and replica updates never to start or manage Codex,
  so that automation remains a confirmed Mac action.

These requirements are implemented in part and remain unverified on devices.
Phone confirmation for automated transitions remains open.

## Project Git status and commits

- The Mac project header provides a compact repository summary. Its popover
  shows branch, HEAD, change counts, refresh, and **Commit all project changes**.
  Task details contain no Git status or commit controls on either platform.
- Project commits stage all non-ignored changes in the configured project folder,
  using the most recently completed task's title. Separate task worktrees are
  not included. Completion timestamps and the existing legacy fallback determine
  recency; a project with no completed task cannot commit, and clean repositories
  do not create empty commits.
- Git actions stay explicit. Runs, task moves, MCP writes, and background phone
  refresh never commit. Paired-phone project Git actions are authenticated,
  online-only requests with deduplicated operation IDs and no returned local paths.
- Marking HEAD as deployed is retired. The app does not infer deployment from
  Make commands. Legacy optional hash/time fields decode and round-trip as inert
  compatibility data. Legacy direct deployment writes receive a terminal rejection.

## Simplified task actions

- Add task has a dedicated blue project-header button and uses the focused section.
- Task title comes first. Launch in Codex and Review plan in Codex (or Plan in Codex
  without a readable plan) use blue primary styling. Review is plan-only.
- Reopen is a blue action beside status for completed tasks. Complete stays visible
  for open tasks. Neither task completion nor reopening is inferred from a run.
- One chronological run history initially expands only the newest run. Older runs
  expand on demand, with failures and required input discoverable from attention rows.
- Context/feedback, StageChase controls, and additional metadata start collapsed.
  Save errors reveal the editor and retain its draft. Priority is hidden on cards
  and in the normal detail form without altering its stored values or ordering.

## Favorite Make targets

- As a user, I want to add, remove, and reorder favorite Make target names in
  Mac Project Settings, so that frequently used project actions are easy to
  find.
- As a user, I want to explicitly run one of a project's favorites from its Mac
  board header, stop an active target, and see bounded output in a native modal,
  so that I can run common repository actions without leaving the board.
- Closing the output modal keeps the command running. Make retains a compact
  result and Show output entry; errors never push terminal output into the board.
- Favorites are project-specific Codable data and round-trip through phone
  snapshots. Settings and execution remain Mac-only. Runs use the latest saved
  project folder, one target argument, and one app-wide active process; they
  never alter tasks, start Codex, or commit Git changes.

## Planned automation

- As a user, I want a confirmed move into Planning to create one persisted Codex
  planning run when automatic invocation is enabled globally and for that
  project, so that planning is explicit and idempotent.
- As a user, I want the Markdown plan to use a readable normalized task-title
  filename with a stable task-ID suffix under lowercase `to-do/`, so I can
  recognize it while keeping duplicate titles distinct.
- As a user, I want plan and Codex links on the task, so that both devices can
  reopen the relevant context.
- As a user, I want a Mac-wide StageChase model and reasoning default, with
  project and task overrides, so that each run uses a deliberate model choice.
- As a user, I want confirmed runs and retries to keep their saved model and
  reasoning effort, so that later settings changes do not silently alter work.
- As a user, I want to change a project's worktree preference and model in
  Project settings, keeping the board header focused on frequent actions.
- As a user, I want worktrees off by default for existing and new projects,
  while retaining an opt-in isolated checkout for dirty repositories.
- As a user, I want unavailable models and unsupported reasoning choices to
  stop visibly before a turn starts, so that the app never substitutes silently.

## Plan format prompt

- As a user, I want generated plans to start with user-story requirements,
  continue with substantive architecture and data-model changes, include basic
  test cases, and finish with high-level implementation details, so that plans
  explain intent, design, and how to recognize working behavior.
- As a user, I want to edit and reset this prompt in Mac Settings, so that I can
  tailor future planning runs without changing application code.
- As a user, I want this preference to remain local to this Mac and apply only
  to planning runs, so that it does not change saved plans or implementation
  instructions.

## Implementation automation

- As a user, I want an **Execute Task** action to execute the selected task in
  StageChase from Planning or Implementing after confirming the model, even when
  automatic invocation is off, so I can start managed Codex work without opening
  Codex Desktop.
- As a user, I want Execute Task to preserve the task's current section
  and leave Launch Codex available as a separate Desktop handoff.
- As a user, I want Plan with StageChase to start a confirmed planning run
  from any task section without moving the task, so StageChase can create a
  plan while preserving my board organization.
- As a user, I want a separate Codex execution profile for each project, so
  projects can use workspace access or explicitly opted-in full access without
  approval prompts.
- As a user, I want each run and retry to use its saved project profile, so
  changing a project setting affects only newly confirmed runs.
- As a user, I want full access to clearly explain that it removes filesystem
  and network isolation, so I can make that choice knowingly.
- As a user, I want quota exhaustion, sign-in/device authorization, unavailable
  service, genuine input requests, blocked work, and task failures to remain
  visible and retryable where appropriate.
- As a user, I want Codex's final response to remain readable in Desktop, so
  StageChase uses plain text and accepts only an explicit `Completed:` result.
- As a user, I want Implementing runs to use a plan when one is available,
  while allowing implementation without a plan.
- As a user, I want a per-project worktree toggle to choose between direct
  project-folder implementation and managed worktrees for dirty repositories.
  The setting defaults off for all projects; changing it affects future runs
  only, and a retry keeps its saved working folder.
- As a user, I want failed automation to remain visible and retryable, so that
  a transient failure does not lose the plan or hide the work.
- As a user, I want Codex outcomes to update task status without changing its
  section or completing it, so I decide when the task is Done.

## Manual Codex Desktop handoff

- As a user, I want a Mac-wide setting to turn automatic Codex invocation on or
  off, so confirmed section moves are distinct from starting a turn.
- As a user, I want a Launch Codex action to open a new Codex Desktop thread
  with the repository path and StageChase MCP prompt.
- As a user, I want generated task prompts to start with the exact task title
  so the task stays clear in the prompt. Runner-created planning sessions use
  `Plan: <task title>`, while implementation and generic task handoff sessions
  use `Code: <task title>`. Prompt-launched threads remain named by Codex
  Desktop because the launch URL returns no thread ID for StageChase to rename.
- As a user, I want the prompt to identify the project and task by stable IDs,
  include a readable project-relative plan path when one exists, and otherwise
  include the task title and notes.
- As a user, I want successful implementation from that prompt to move the
  identified task to Review through MCP after reporting success, while
  preserving its completion flag; completion and reopening remain my actions
  in StageChase.
- As a user, I want legacy linked-session status refresh and rerun controls to
  remain available for existing handoffs.
- As a user, I want a task-level Refresh action to reread saved task fields,
  discover or recheck its attached plan, and update linked Codex status/activity
  without changing task placement or completion.
- As a user, I want Refresh to preserve unsaved edits, prevent overlapping
  requests, and explain when a plan or linked session is unavailable.
- Manual handoffs, status refreshes, and Codex outcomes do not move a task or
  start work from phone polling or replica updates.
- As a user, I want external `begin_task` to distinguish planning from task
  execution while older callers default to generic task activity, so the task
  history identifies each workflow by kind.
- As a user, I want `begin_task` clients to pass the exact current Codex Desktop
  thread ID when their client exposes it, so StageChase can link the run as soon
  as it is recorded without guessing from a title or task text. When the client
  cannot access that ID, I can link the exact session from task detail.
- As a user, I want the linked task card to show a spinner and the latest short
  Codex message only while a confirmed turn is busy, so waiting, finished, or
  disconnected sessions are not shown as processing.
- As a user, I want one newest-first task history with clear run-kind labels,
  so I can distinguish planning from implementation while expanding older runs only when needed.
- Linking or reconnecting observes an existing thread only; it never submits,
  interrupts, or closes a turn.

## Manual plan handoff

- As a user, I want a contextual Plan in Codex or Review plan in Codex action
  in Mac task detail, so I can create or revise a plan without authorizing
  implementation.
- As a user, I want both actions to use identical plan-only instructions with
  stable project/task IDs, the current Mac plan-format preference, and the
  intended project-relative path, so copying and launching produce the same
  plan workflow.
- As a user, I want the StageChase planning action grouped separately from the
  Plan in Codex and Review plan in Codex handoffs, so I can tell which actions
  start work inside the app and which open Desktop for me.
- As a user, I want a new plan to use a normalized task-title slug plus its full
  task UUID under `to-do/` and a revision to preserve its attached path, so
  plans are recognizable, collision-safe, and honor an existing location.
- As a user, I want Codex to attach the saved readable Markdown plan through
  revision-checked MCP operations and set successful planning to Ready in
  Planning, while preserving task completion and never starting another Codex
  session.
- Opening a plan prompt does not itself change task state. A paired iPhone may
  explicitly request a Mac plan prompt from task detail; background phone sync
  never starts or manages Codex.

## iPhone task controls and Codex settings

- As a user, I want one blue Add task button in the iPhone board toolbar to add
  a task to the currently focused section, so the main creation action is easy
  to find. Keep lane-specific + controls on Mac and remove duplicate per-lane
  phone buttons and Add Task rows.
- As a user, I want a single tap on a task title to open task detail and a double
  tap to edit the title inline, so opening a task is the default phone action.
- As a user, I want task detail buttons to ask StageChase on my paired Mac to
  prepare a planning run or a task run, so I can start either workflow from the
  phone. The phone tap confirms the request, and the Mac verifies the task
  revision before starting Codex.
- As a user, I want to open a saved plan from phone task detail and read its
  Markdown inline, so the plan is available without leaving the task. The phone
  requests the bounded file contents only when I open it, and does not receive
  the Mac's project path.
- Project Git is reachable from the selected project's board menu. The phone
  reads Git status and requests a confirmed project-wide commit through the
  authenticated paired-Mac connection; it never runs Git against a phone-local
  path. Task detail has no Git action.
- On phone task detail, keep the title first and show Reopen, **Launch in
  Codex**, **Plan in Codex**, and **Copy prompt** before optional details.
  Launch and Plan are explicit revision-checked requests to start the task or
  planning run on the paired Mac; the user's tap is confirmation. Copy prompt
  provides a StageChase-aware prompt for another Codex chat. Keep task context
  collapsed initially and saved-plan reading under More details.
- As a user, I want to change a project's Codex execution profile and model from
  paired iPhone Project settings, so future confirmed Mac runs use my choices.
  Existing run snapshots remain unchanged, and the full-access profile keeps its
  filesystem and network warning visible.
- Explicit phone controls may request these Mac actions over the authenticated
  pairing. Background polling, replica updates, and queued board edits never
  start or manage Codex.
- A paired iPhone can mark a task complete or reopen it with the latest task
  revision, and can delete it after confirmation. The Mac rejects stale edits
  and deletion during an active run. These actions do not start or manage Codex.
- The iPhone board overflow menu has a Refresh from Mac action that reports
  progress and the latest result. It uses the same queued-edit-first manual
  refresh as pull-to-refresh.
- No documented external Codex URL contract currently establishes how to select
  a remote host/workspace and pass task context. Do not construct a remote URL;
  keep task context copyable until Codex documents that contract.

## Project sidebar review and Git state

- As a user, I want each project row to show compact unlabeled counts for its total open tasks, tasks ready for plan review, tasks ready for code review, and changed Git files.
- Plan-review counts use the blue Plan Approved badge treatment; code-review counts use the green Reviewing treatment; changed-file counts use orange. The number colors and treatments explain the values without repeated labels.
- Missing or unavailable Git status uses a dash in the Git count position; the sidebar does not show an unavailable message.
- Review counts exclude completed tasks and are derived from the current library. Opening a task or selecting a project does not change any counts or add read state.
- Git status is transient presentation data. A clean repository shows zero changed files; changed repositories show the changed-file count, including staged, unstaged, and untracked work. Refresh occurs when the sidebar row appears and after existing Git actions, without background polling.
- Mac and iPhone align the four count badges to the right of the project name, allowing long names to wrap beneath themselves. The phone reads Git state through an explicit direct request to its paired Mac.
- The Mac project header echoes the Git changed-file count in orange. Each main board column shows blue plan-review and green code-review badges only when it contains open tasks with those statuses; the counts are scoped to that column.

## Codex Desktop task tools

- As a user, I want Codex Desktop to list, read, and create project tasks, so I
  can work from the repository already open in that session.
- As a user, I want explicit, revision-checked moves and completion changes to
  appear in StageChase, so task state stays in the local library.
- As a user, I want a readable project-relative plan attached to its task after
  planning, then its status set to Ready while it remains in Planning.
- As a user, I want successful implementation to enter Review, then mark Done
  only when I sign off, so Codex outcomes never close the loop automatically.
- As a user, I want Codex to report a concise latest session update, so the
  task detail shows recent progress without copying a conversation transcript.
- The Mac-only MCP listener starts automatically on app launch by default, can
  be stopped persistently in Connection settings, and is loopback-only. Tool
  calls never start, resume, retry, stop, or approve Codex work, and only an
  explicit user action can mark a task Done.

## Plan feedback

- As a user, I want one automatically saved context field for task notes or plan
  feedback, so I can edit context without an extra append action.
- With a readable plan attached, leaving the field appends its exact wording
  under a `User feedback on the plan` heading. Appending preserves existing plan
  content, does not start Codex or change the task, and reports file errors
  without clearing the draft or duplicating a successful retry.
- Plan feedback is available on Mac, where the project plan file is stored.
  The phone explains where to append it; feedback and project plan files are
  not included in phone sync.
