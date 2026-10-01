# Automation behavior

The Mac app is the only runner and must stay open. No cron, login item, public
endpoint, or background daemon is installed. Experimental phone sync is limited
to the local Wi-Fi listener and encrypted commands; device-level behavior is
not yet verified.

| Action | Behavior |
| --- | --- |
| Open, poll, switch project, enable automation | Does not enqueue or start work |
| Refresh model catalog or edit model or approval settings | Does not enqueue or start work |
| Edit or reset the plan format prompt | Saves a Mac-local preference; does not enqueue work |
| Confirm adding/moving to Next with automatic invocation enabled globally and for the project | Atomically reserve `to-do/<lowercase task UUID>.md` when no path was selected, persist one planning run, and invoke Codex |
| Planning success | Require structured success plus a readable, nonempty file at the task's reserved path; update the run only, leaving the task column unchanged |
| Confirm adding/moving to Implementation with automatic invocation enabled globally and for the project | Prepare a checkout/worktree and invoke Codex; a plan is optional context |
| Implementation success | Require structured success; update the run only. The user chooses the task column and completion state |
| Turn off Automatically invoke Codex | Stage changes no longer start turns. Existing active turns continue; task detail still offers a manual Desktop handoff |
| Run in Codex from task detail | Persist task context, create an empty Codex Desktop session, copy the context, and open that session; the user starts the turn in Desktop |
| Use the optional Codex Desktop MCP connection | Read/create tasks and explicitly move/complete them through the Mac library; MCP task calls never start or control a Codex turn |
| Refresh manual Codex status | Read the linked session only after the user presses Refresh status; update its run record without changing the task |
| Retry/rerun a manual task | Reuse the saved context in a fresh Desktop session and copy it again; the user starts the new turn |
| Approval request in Ask me mode | Show Allow once / Deny and Needs Approval state |
| Approval request in Auto-approve requests mode | One-time accept only for supported command/file requests that do not ask for broader permissions |
| Unsupported interaction | Fail visibly; retain session link for continuing in Codex |
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
to Inbox; moves and completion are explicit, revision-checked, separate changes.
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

## Approval mode

The Mac-only setting defaults to **Approve for me**. It uses Codex's built-in
`approvalPolicy: never` while keeping `workspaceWrite`, the run's selected
writable root, and `networkAccess: false`. Codex does not pause for ordinary
approval prompts; the sandbox still limits file writes and network access.

**Ask me** keeps Codex's `on-request` policy and shows supported command and
file-change approval requests in Activity for a one-time Allow once / Deny
decision. **Auto-approve requests** also uses `on-request`, then StageChase
responds `accept` once for each supported command or file-change request. It
does not grant session-wide approval, a broader filesystem root, or network
access. Unknown, overlapping, stale, mismatched, and permission-widening
requests fail visibly instead of being automatically accepted.

StageChase snapshots the selected mode when a queued run starts. Settings
changes apply to later runs and explicitly confirmed retries. The preference is
stored in Mac-local UserDefaults and is excluded from library sync and exports.
If a saved mode is malformed, Settings shows an error and the runner waits for
the user to choose a valid mode.

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
preserved; otherwise StageChase uses the lowercase task UUID path above. A
reservation by itself is not a saved plan: the run succeeds only after Codex
reports completion and StageChase verifies readable, non-whitespace Markdown at
that exact path. The task stays in its current column. Open plan and Mac
feedback actions require a readable file and are available regardless of the
task's column. Failed and interrupted runs retain the path for retry. Legacy
failed planning runs without a path receive the canonical path when explicitly
retried.

The Mac-wide **Automatically invoke Codex** preference gates automatic turns;
the existing project switch must also be enabled for stage-triggered automation.
With automatic invocation off, users can choose **Run in Codex** on any task.
StageChase stores the task context and linked session, copies the context for
the user, and opens the session in Codex Desktop without submitting a turn.
Task detail keeps the context available to copy later. Refresh status is an
explicit `thread/read` action and never polls in the background or changes task
placement. Automatic run settings do not restrict stage placement based on a
plan, completion state, or Codex run status.

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
