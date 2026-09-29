# StageChase

A native, local-first workspace for **multiple projects**, with five fixed stages:
Inbox → Next → Planned → Implementation → Review.

The September 29 rewrite replaces the prototype. Each project has its own board,
folder, and automation setting. Both apps offer project creation, full-height
top-aligned lanes, per-column quick capture, drag-and-drop, task details, and
explicit completion. The Mac adds search, a task inspector, agent activity,
native undo/redo for manual task edits, keyboard shortcuts, and text-size settings.

## Run

No third-party packages or native dependency installations are needed.

```sh
make test         # workflow, migration, persistence, and regression tests
make runner-test  # offline app-server integration fixtures; no model usage
make codex-check  # installed Codex handshake and sign-in check; no model turn
make run          # development-signed Mac build and launch
make sim-launch   # iPhone Simulator build, install, and launch
make phone-deploy # signed build, install, and launch on the configured iPhone
```

## Codex automation

On Mac, open **Project settings**, choose a project folder, and enable Codex.
Moving or adding a task to **Next** asks for confirmation before a planning run.
Moving to **Implementation** requires a saved Markdown plan and confirmation.
Activity shows queued/running/approval/failed/finished states, plan steps, public
messages, bounded command output, the working folder, and a Codex session link.
Runs can be stopped or explicitly retried in their saved session.

The adapter uses the installed Codex app-server, the existing sign-in, and the
user's configured model. Workspace-write sandboxing remains enabled; supported
command/file permission requests require approval. Unsupported interactive
requests stop with a visible explanation. Completion requires a structured
successful outcome; planning also requires a nonempty saved plan. Codex never
marks tasks complete. The prompt forbids commits, pushes, deployment, and
unrelated deletion; review approvals and changes rather than treating prompt
restrictions as an absolute enforcement layer.

## Data and device boundary

The versioned SwiftData/SQLite library lives under Application Support/StageChase.
The original `store.json` imports once and is preserved, with an additional
`store.json.pre-v2-backup`. Errors never silently create an empty replacement.
Settings offers JSON backup export and restore into an empty library.

**Mac–iPhone pairing and live synchronization are not implemented.** Libraries
are independent. The phone clearly states that its moves do not start Codex on
the Mac. No HTTP listener, public hosting, or background service is installed.
The Mac app must remain open for its runner.

For an isolated UI preview, launch either app with `--preview-library`; on iPhone,
add `--preview-board` to show the board immediately. Preview data is in memory
and never runs Codex or replaces the real library.

See [setup](docs/setup-install.md), [architecture](docs/architecture.md),
[design](docs/design.md), [automation](docs/automations.md), and
[verification](reports/verification-2026-09-29.md).
