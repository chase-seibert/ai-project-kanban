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
- As a user, I want transitions and activity to be recorded, so that I can see
  what changed and why.
- As a user, I want edits to carry revisions, so that a stale iPhone write does
  not silently overwrite a newer Mac transition.

## Planned automation

- As a user, I want a confirmed move into Next to create one persisted Codex
  planning session, so that planning is explicit and idempotent.
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

## Implementation automation

- As a user, I want Implementation to require a plan, so that Codex does not
  act on an unplanned idea.
- As a user, I want dirty project state to select a managed worktree, so that
  unrelated local changes are protected.
- As a user, I want failed automation to remain visible and retryable, so that
  a transient failure does not lose the plan or hide the work.
- As a user, I want Review to remain manual, so that I decide when work is
  complete.
