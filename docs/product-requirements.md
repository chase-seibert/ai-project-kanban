# Product requirements

## Foundation

- As a user, I want to create a board, so that different projects can have
  separate workflows.
- As a user, I want the five workflow stages to remain fixed, so that every
  board has a predictable path from idea to review.
- As a user, I want to capture and edit tasks, so that ideas are useful before
  planning begins.
- As a user, I want to move tasks between stages, so that the board reflects my
  current intent.
- As a user, I want task placement to remain independent of plan availability,
  Codex run state, and run outcome, so the columns reflect my intent.
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

## Planned automation

- As a user, I want a confirmed move into Next to create one persisted Codex
  planning run when automatic invocation is enabled globally and for that
  project, so that planning is explicit and idempotent.
- As a user, I want the Markdown plan to live in lowercase `to-do/`, so that it
  remains an ordinary project file I can inspect and version.
- As a user, I want plan and Codex links on the task, so that both devices can
  reopen the relevant context.
- As a user, I want a Mac-wide StageChase model and reasoning default, with
  project and task overrides, so that each run uses a deliberate model choice.
- As a user, I want confirmed runs and retries to keep their saved model and
  reasoning effort, so that later settings changes do not silently alter work.
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

- As a user, I want Implementation runs to use a plan when one is available,
  while allowing implementation without a plan.
- As a user, I want dirty project state to select a managed worktree, so that
  unrelated local changes are protected.
- As a user, I want failed automation to remain visible and retryable, so that
  a transient failure does not lose the plan or hide the work.
- As a user, I want Codex outcomes to leave the task in its current stage, so I
  decide where it belongs and when it is complete.

## Manual Codex Desktop handoff

- As a user, I want a Mac-wide setting to turn automatic Codex invocation on or
  off, so that confirmed stage moves can be separated from starting a turn.
- As a user, I want a task-level Run in Codex action that saves task context,
  opens a linked Codex Desktop session, and copies the context for me to start
  manually.
- As a user, I want to copy the saved context later, refresh the linked session
  status on demand, and retry or rerun from the task.
- Manual handoffs, status refreshes, and Codex outcomes do not move a task or
  start work from phone polling or replica updates.

## Plan feedback

- As a user, I want to type or dictate feedback on a saved plan and explicitly
  append it under a `User feedback on the plan` heading, so my raw feedback is
  preserved with the project document.
- Appending feedback preserves the submitted wording and existing plan content,
  does not start Codex or change the task, and reports file errors without
  clearing the draft.
- Plan feedback is available on Mac, where the project plan file is stored.
  The phone explains where to append it; feedback and project plan files are
  not included in phone sync.
