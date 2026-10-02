# Product requirements

## Foundation

- As a user, I want to create a board, so that different projects can have
  separate workflows.
- As a user, I want three board sections, Inbox, Planning, and Implementing, so
  that the Mac board is simpler and the iPhone can show the same workflow.
- As a user, I want task status to be separate from section, so that each task
  shows whether it is in triage, planning, ready, building, waiting, error,
  quota, review, or done.
- As a user, I want Waiting, Error, Quota, and Review tasks sorted first in that
  order within their section, so that attention-needed work is easy to find.
- As a user, I want the Mac sections shown as three side-by-side columns with
  vertical task lists and iPhone sections kept as horizontal pages, so each
  device retains a useful board layout.
- As a user, I want to capture and edit tasks, so that ideas are useful before
  planning begins.
- As a user, I want to paste an Apple Notes checklist into lane capture and
  create one task per unchecked item, so I can quickly bring a list into a board.
- As a user, I want to move tasks between Inbox, Planning, and Implementing, so
  that the board reflects my current intent.
- As a user, I want section placement to remain independent of plan availability
  and Codex run state, so the board reflects my intent.
- As a user, I want transitions and activity to be recorded, so that I can see
  what changed and why.
- As a user, I want Mac and iPhone to show concise run status and progress
  instead of a long event timeline, so task detail and Activity stay readable
  and I can open the associated Codex session for its full history.
- As a user, I want the iPhone to offer a truthful Codex handoff, so it opens a
  supported thread URL or explains that I need to continue on Mac and can copy
  the session ID.
- As a user, I want edits to carry revisions, so that a stale iPhone write does
  not silently overwrite a newer Mac transition.

## Experimental local Wi-Fi sync

- As a user, I want to pair my iPhone with the Mac using a temporary code,
  without separate desktop confirmation, so that the phone shows the same project identities without
  merging libraries by name.
- As a user, I want supported phone edits to queue offline and reach the Mac
  once it is open on the same Wi-Fi network, so that temporary outages do not
  lose my intent.
- As a user, I want a pending count, last-sync time, and visible conflicts, so
  that cached Mac state is not mistaken for a successful refresh.
- As a user, I want a Connection tab showing in-progress state, last result,
  editable saved endpoint, and timestamped request/response sizes and outcomes,
  so that I can diagnose failed reconnects without losing queued changes.
- As a user, I want to control automatic phone syncing and pull to refresh the
  board or tap Sync Now, so that I can choose between periodic updates and
  deliberate manual syncs without losing queued edits.
- As a user, I want polling and replica updates never to start or manage Codex,
  so that automation remains a confirmed Mac action.

These requirements are implemented in part and remain unverified on devices.
Phone confirmation for automated transitions and conflict reapplication remain
open.

## Git status and deployed revision

- As a user, I want the Mac project header and task detail to show the current
  branch, `HEAD` commit hash, and shared working-tree status, so I can see
  changes and commits made either inside or outside StageChase.
- As a user, I want a direct task action to stage all non-ignored project
  changes and commit them with a single-line version of the task title, so I do
  not need to select files or write a separate message.
- As a user, I want a project-header action to stage and commit all changes in
  the configured project folder using the title of the most recently completed
  task in that project, so I can save shared project work without opening a
  task.
- Completed tasks retain their completion time across later edits; older
  completed records without a completion time use their update time as a
  best-effort fallback. A project with no completed task cannot create a
  project commit, and clean repositories do not create empty commits.
- As a user, I want to record the current `HEAD` as a project's deployed
  revision, so I can compare the deployment checkpoint with current code.
- Git status comes from the configured Mac project folder, or from the latest
  run's recorded worktree when one exists. Task detail shows shared project
  status without claiming individual file ownership; branch-to-task association
  is deferred.
- Git operations are explicit Mac actions. Codex runs, task moves, MCP reads or
  writes, and phone synchronization never commit. Recording a deployed revision
  is manual and can become stale when deployments happen elsewhere.
- The deployed hash and timestamp are optional backward-compatible project
  fields. Phone replicas may display this checkpoint, but never receive local
  repository paths or status contents.

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
- As a user, I want to change a project's worktree preference and model from its
  Mac board header, so project run choices are quick to see and edit.
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
  and Codex sessions to use that title alone, so the task stays clear in both
  the prompt and Desktop session list.
- As a user, I want the prompt to identify the project and task by stable IDs,
  include a readable project-relative plan path when one exists, and otherwise
  include the task title and notes.
- As a user, I want successful implementation from that prompt to move the
  identified task to Review through MCP after reporting success, leaving it
  incomplete until I sign off; failed or blocked work remains incomplete.
- As a user, I want legacy linked-session status refresh and rerun controls to
  remain available for existing handoffs.
- As a user, I want a task-level Refresh action to reread saved task fields,
  discover or recheck its attached plan, and update linked Codex status/activity
  without changing task placement or completion.
- As a user, I want Refresh to preserve unsaved edits, prevent overlapping
  requests, and explain when a plan or linked session is unavailable.
- Manual handoffs, status refreshes, and Codex outcomes do not move a task or
  start work from phone polling or replica updates.

## Manual plan handoff

- As a user, I want a contextual Plan in Codex or Revise plan in Codex action
  in Mac task detail, so I can create or revise a plan without authorizing
  implementation.
- As a user, I want both actions to use identical plan-only instructions with
  stable project/task IDs, the current Mac plan-format preference, and the
  intended project-relative path, so copying and launching produce the same
  plan workflow.
- As a user, I want a new plan to use a normalized task-title slug plus its full
  task UUID under `to-do/` and a revision to preserve its attached path, so
  plans are recognizable, collision-safe, and honor an existing location.
- As a user, I want Codex to attach the saved readable Markdown plan through
  revision-checked MCP operations and set successful planning to Ready in
  Planning, while leaving the task incomplete and never starting another Codex
  session.
- Opening a plan prompt does not itself change task state. Plan handoff controls remain unavailable on iPhone and paired
  phone replicas.

## Unread task changes

- As a user, I want task cards to identify column moves and completion-status
  changes that I have not opened, so I can see what changed after returning.
- As a user, I want each project row to show how many tasks have unread changes,
  so I can find affected projects quickly.
- Opening a task clears only that task's badge. Selecting a project clears its
  project-level badge independently. Read markers are local to each device.
- Only column and completion-status changes create these badges; task edits and
  agent activity do not.

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
