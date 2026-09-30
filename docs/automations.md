# Automation behavior

The Mac app is the only runner and must stay open. No cron, login item, public
endpoint, or background daemon is installed. Experimental phone sync is limited
to the local Wi-Fi listener and encrypted commands; device-level behavior is
not yet verified.

| Action | Behavior |
| --- | --- |
| Open, poll, switch project, enable automation | Does not enqueue or start work |
| Refresh model catalog or edit model settings | Does not enqueue or start work |
| Confirm adding/moving to Next | Persist one planning run and invoke Codex |
| Planning success | Require structured success plus a saved nonempty plan; move to Planned |
| Confirm Implementation | Require plan; prepare checkout/worktree; invoke Codex |
| Implementation success | Require structured success; move to Review, never Completed |
| Approval request | Show Allow once / Deny and Needs Approval state |
| Unsupported interaction | Fail visibly; retain session link for continuing in Codex |
| Blocked/failed/disconnected | Keep task in its stage, preserve error and retry state |
| Stop | Cancel active work; close the owned server and preserve files already changed |
| Close Codex session | Interrupt active work as Interrupted, then confirm shutdown of the owned server; preserve finished outcomes, conversation history, working folder, and files |
| Open in Codex | Open the saved thread link only; does not release or continue the StageChase connection |
| Restart | Mark active/queued runs Interrupted; never automatically replay |
| Retry | Explicitly resume the saved model, reasoning effort, session, and working folder |
| Phone snapshot refresh | Read Mac state only; never enqueue or invoke the runner |
| Phone manual task command | Validate device, revision, sequence, and operation receipt on Mac |
| Phone move into automated stage | Keep it on Mac until phone confirmation context is implemented |
| Append plan feedback on Mac | Coordinate an explicit raw-text append to the saved Markdown plan; never enqueue or invoke the runner |
| Phone plan feedback | Direct the user to the Mac, where project plan files are stored |

Workspace-write sandboxing and default network restrictions remain enabled.
Unknown requests are not silently approved. The agent is instructed not to
commit, push, publish, deploy, or delete unrelated files. Review approvals and
results; prompt restrictions are not an absolute enforcement boundary.

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
