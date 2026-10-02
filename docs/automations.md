# Automation behavior

The Mac app is the only runner and must stay open. No cron, login item, public
endpoint, or background daemon is installed. Experimental phone sync is limited
to the local Wi-Fi listener and encrypted commands; device-level behavior is
not yet verified.

| Action | Behavior |
| --- | --- |
| Open, poll, switch project, enable automation | Does not enqueue or start work |
| Refresh model catalog or edit model settings | Does not enqueue or start work |
| Change a project's settings | Saves that project's worktree preference, model override, or execution profile; does not enqueue or start work |
| Edit or reset the plan format prompt | Saves a Mac-local preference; does not enqueue work |
| Confirm adding/moving to Next with automatic invocation enabled globally and for the project | Atomically reserve `to-do/<normalized task-title>-<lowercase task UUID>.md` when no path was selected, persist one planning run, and invoke Codex |
| Planning success | Require an explicit plain-text `Completed:` response plus a readable, nonempty file at the task's reserved path; update the run only, leaving the task column unchanged |
| Confirm adding/moving to Implementation with automatic invocation enabled globally and for the project | Use the project folder, or create a managed worktree for a dirty repository when that project's worktree setting is on; then invoke Codex. A plan is optional context |
| Confirm Run with StageChase from task detail | Queue and run only that task in its current Planning or Implementing section, using the saved project profile; this explicit action works even when automatic invocation or project automation is off |
| Confirm Plan with StageChase from task detail | Queue a planning run from any section, reserve its plan path, and preserve the task's current section and completion state |
| Implementation success | Require an explicit plain-text `Completed:` response; update the run only. The user chooses the task column and completion state |
| Turn off Automatically invoke Codex | Stage changes no longer start turns. Existing active turns continue; task detail still offers Run with StageChase, Plan with StageChase, and the two Codex Desktop handoffs |
| Run with StageChase from task detail | Confirm the resolved model and effort, then start the selected queued run in the Mac runner without opening Codex Desktop or moving the task |
| Plan with StageChase from task detail | Confirm the resolved model and effort, then start a planning run in the Mac runner without opening Codex Desktop or moving the task |
| Copy prompt from task detail | Copy the same StageChase MCP task prompt used by Launch Codex, starting with the exact task title and including stable IDs and a readable project-relative plan path when available |
| Launch Codex from task detail | Open `codex://threads/new` with the repository path and same MCP prompt; let the user start the turn in Desktop. StageChase cannot rename these threads because the URL flow returns no thread ID |
| Successful task-prompt work | After `finish_task` succeeds, move the task to Review through MCP using its latest revision; preserve the completion flag for the user's review |
| Failed or blocked task-prompt work | Report the outcome through MCP and preserve the completion flag |
| Use the optional Codex Desktop MCP connection | Read/create tasks and move them through the Mac library; users complete or reopen tasks in StageChase, and MCP task calls never start or control a Codex turn |
| Refresh manual Codex status | Read the linked session only after the user presses Refresh status; update its run record without changing the task |
| Retry/rerun a manual task | Reuse the saved context in a fresh Desktop session and copy it again; the user starts the new turn |
| Unexpected approval request | Fail visibly under the run's no-prompt policy; retain the session link for continuing in Codex |
| Quota, sign-in/device authorization, unavailable service, or genuine user input | Preserve the specific failure/input explanation and leave the run retryable where appropriate |
| `Blocked:` or unmarked final response | Keep the run failed and retryable; never infer completion from ambiguous prose |
| Blocked/failed/disconnected | Keep task in its stage, preserve error and retry state |
| Stop | Cancel active work; close the owned server and preserve files already changed |
| Close Codex session | Interrupt active work as Interrupted, then confirm shutdown of the owned server; preserve finished outcomes, conversation history, working folder, and files |
| Open in Codex | Open the saved thread link only; does not release or continue the StageChase connection |
| Restart | Mark active/queued runs Interrupted; never automatically replay |
| Retry an automatic run | Explicitly resume the saved model, reasoning effort, session, working folder, and reserved plan path when automatic invocation is enabled |
| Phone snapshot refresh | Read Mac state only; never enqueue or invoke the runner |
| Phone manual task command | Validate device, revision, sequence, and operation receipt on Mac |
| Phone move between stages | Apply the move without starting Codex; phone polling and replica updates never enqueue or invoke work |
| Append plan feedback on Mac | Coordinate an explicit raw-text append to the saved Markdown plan; never enqueue or invoke the runner |
| Phone plan feedback | Direct the user to the Mac, where project plan files are stored |

The **Connection → Codex Desktop task tools** setting starts an opt-in MCP
listener bound to `127.0.0.1`. Use the displayed `codex mcp add stagechase
--url …` command to register it with the Codex Desktop configuration. The
listener is available only while StageChase is open. MCP task creation defaults
to Inbox; moves are explicit, revision-checked changes. Completion and reopening
are available only through the user's StageChase controls.
The repository commits an operation receipt with each MCP write so a retry with
the same operation ID cannot duplicate the change. Moving a task through MCP
never enters the automatic-run path.
`begin_task`, `report_task_update`, and `finish_task` record the session already
open in Codex Desktop and a bounded latest message. They do not create or
control a Desktop session; after a StageChase restart its external state is
shown stale. If work is continuing, Codex begins a new tracking record before
reporting again.

Workspace-write sandboxing and default network restrictions remain enabled.
Unknown requests are not silently approved. The agent is instructed not to
commit, push, publish, deploy, or delete unrelated files. Review approvals and
results; prompt restrictions are not an absolute enforcement boundary.

## Codex execution profiles

Each project defaults to **Workspace access, no prompts**. StageChase sends
`approvalPolicy: never`, `sandbox: workspace-write`, and a matching
`workspaceWrite` turn policy limited to the run's working folder with network
access disabled. **Full access, no prompts** is a separate per-project opt-in;
it sends `sandbox: danger-full-access` at thread start/resume and
`dangerFullAccess` for the turn. This profile removes filesystem and network
isolation. Both profiles disable ordinary Codex approval prompts, while the
existing StageChase confirmation before automatic work remains required.

The profile is part of the shared project record and appears on phone replicas
as informational data only. Only the Mac runner can execute tasks. Each new run
stores its project's profile, and retries reuse that run snapshot after project
settings change. Older projects decode to the restricted workspace profile;
older runs acquire the project's current profile once when retried. Quota,
sign-in or device authorization, unavailable service, user input, blocked work,
and other task failures remain visible and are never reclassified as approval
requests.

Runner final messages are plain text for readable Codex Desktop conversations.
Only an explicit `Completed:` response can succeed; `Blocked:` and unmarked
responses fail safely. Planning also requires a readable, nonempty plan at the
reserved path.

Mac Settings includes a bounded, editable plan-format prompt. Its default
organizes planning output as user requirements, architecture and data model,
basic test cases, and high-level implementation details, in that order. Blank
or whitespace-only text falls back to the default. StageChase adds the resolved
text only to a planning turn; implementation prompts and saved plans are
unchanged. The preference is Mac-local, excluded from library export/sync, and
does not override the fixed task scope, approval policy, sandbox, or final
outcome requirements. Prompt wording is guidance rather than a security control.

Close Codex session is available for saved sessions. It is disabled while a
different run owns the shared app-server process. A successful close pauses
automatic queue draining; queued work stays queued until a confirmed stage
action or explicit Retry resumes the runner. Closing does not delete a retained
worktree or session history. After release, use Open in Codex to open the same
thread and continue it manually there. StageChase does not import desktop results.

Events and approvals share one serial queue so a delayed Running update cannot
overwrite Needs Approval. Public command logs are bounded per entry. Private
reasoning events are not collected. Treat generated plans/output as untrusted.

`make runner-test` runs offline fixtures without model usage. `make codex-check`
checks the installed server/sign-in without starting a turn. Real model work
requires an intentional confirmed action and uses the account's allowance.
Screenshot preview mode never invokes Codex.

A planning path is reserved on the task in the same confirmed reducer update
that queues its run. An existing user-selected relative Markdown path is
preserved; otherwise StageChase uses the readable task-title slug and full task
UUID path above. A
reservation by itself is not a saved plan: the run succeeds only after Codex
reports completion and StageChase verifies readable, non-whitespace Markdown at
that exact path. The task stays in its current column. Open plan and Mac
feedback actions require a readable file and are available regardless of the
task's column. Failed and interrupted runs retain the path for retry. Legacy
failed planning runs without a path receive the canonical path when explicitly
retried.

The Mac-wide **Automatically invoke Codex** preference and project automation
switch gate stage-triggered automatic turns. **Run with StageChase** is a
separate, explicit task-detail action: it confirms the model and effort and
starts only that task through the Mac runner, even with either automation gate
off. **Plan with StageChase** works from any section, reserves a plan path,
and leaves the task in place. The independent **Plan in Codex** and **Launch
Codex** actions open Desktop for the user without submitting a turn. Launch
uses the implementation prompt, and plan handoff uses the plan-only prompt.
Each Desktop prompt identifies the project and task by stable IDs and includes
the task title, notes, and any readable project-relative plan path. Launch opens
`codex://threads/new` with the project folder and prompt; it does not submit a
turn. Run with StageChase can still need the user's attention for quota,
sign-in/device unlock, service errors, or genuine requests for input. The prompt directs Codex to update the task through the StageChase MCP and
move successful implementation to Review. Completion remains under the user's
control in StageChase.
Automatic run settings do not restrict stage placement based on a plan,
completion state, or Codex run status.

Reference: [official app-server docs](https://learn.chatgpt.com/docs/app-server).

## Model selection

The Mac's StageChase default is Latest Luna with High reasoning. Optional
project and task pairs override it in that order. The Latest Luna policy
resolves against visible stable Luna models in the connected `model/list`
catalog and compares numeric version components. StageChase does not substitute
another model or effort when the selected choice is unavailable or unsupported.

The confirmation shows the resolved model and effort. StageChase stores that
pair, selection policy, and source with the queued run, then sends explicit
`model` and `effort` fields to app-server. Existing runs keep their saved pair
when defaults change. Older runs without a saved choice need a reviewed choice
before retry. The global preference is Mac-local and is not included in library
exports; project/task overrides and run records travel with the library. The
iPhone does not query the catalog or run Codex. The phone shows safe run status
summaries but has no remote approval, Stop, or Retry controls.

The Mac board header shows the selected project's effective model and offers a
project override editor. Task overrides still take precedence. Each project
also has a **Use worktrees** toggle in the Mac header. It defaults off for new
projects and older project payloads that lack the setting. When enabled, a dirty
repository uses a managed worktree for a new implementation run; clean
repositories and planning runs use the project folder. When disabled,
implementation runs use the project folder directly, including local changes.
Newly confirmed runs save the selected worktree setting with the run. Existing
retries always reuse their saved working folder and model snapshot. Editing
either header setting starts no work, and changes apply only to future
confirmed runs.
