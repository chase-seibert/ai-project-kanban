# StageChase agent instructions

Also load the user-level instructions at `/Users/cseibert/.codex/AGENTS.md`.
Those instructions define the shared engineering and Apple-platform defaults;
this file only adds repository-specific guidance.

## Repo map

- `StageChase.xcodeproj/` — native macOS and iOS app targets.
- `Sources/StageChaseCore/` — shared workflow model and local persistence.
- `Apps/StageChaseMac/` — Mac board, editor, activity log, and Settings UI.
- `Apps/StageChasePhone/` — iPhone board, capture, task detail, and board setup UI.
- `Tests/StageChaseCoreTests/` — Swift Testing coverage for core behavior.
- `docs/` — project brief, architecture, design, requirements, and setup notes.
- `scripts/` — reusable project helpers.
- `reports/` — shareable generated outputs.
- `memory/` — project memory and cached source notes; read `memory/AGENTS.md` first.
- `tasks/` — delegated-work index.
- `skills/` — agent-neutral reusable skills. `.codex/skills/` would contain
  Codex symlinks when the project harness has write access to that directory.

## Commands

Prefer Makefile targets over ad hoc commands:

- `make test` — run shared model tests.
- `make build` / `make run` — build or launch the Mac app.
- `make sim-build` / `make sim-launch` — build or launch the iPhone app in Simulator.
- `make phone-build`, `make phone-install`, `make phone-launch`,
  `make phone-deploy` — physical-device workflow.
- `make clean` — remove project build outputs.

## Product boundaries

Keep the five stages fixed in `WorkflowStage`. Do not add Apple Reminders,
custom columns, automatic completion, public cloud hosting, or user-facing
CLI tools without an explicit product decision. Polling/synchronization must
not start or manage Codex. Automatic turns require a confirmed stage transition
with both automatic-invocation settings enabled; a manual turn starts only when
the user opens a task handoff in Codex Desktop and starts work there. An
opt-in loopback MCP endpoint also allows direct task reads and explicit task
writes; MCP calls must never start or manage a Codex turn. Require project/task
IDs and expected revisions for existing-task writes.

The implementation includes multi-project boards, a Mac Codex runner behind
AgentConnection, and an experimental local Wi-Fi sync path. Preserve
idempotence, revision checks, visible activity, explicit approvals, and
failed-run retry state. Sync has not passed device-level acceptance; distinguish
build/test coverage from verified Mac–iPhone behavior. The phone must never
start, approve, stop, or retry Mac Codex work through polling or replica updates.

## Codex Desktop MCP task workflow

When the StageChase MCP connection is available, use `list_projects` and
`list_tasks` to find tasks by stable IDs, then `read_task` before implementation.
Call `begin_task` only after the user asks to start work. Report concise progress
with `report_task_update`; call `finish_task` with the final summary when the
work ends. A successful code change does not itself complete or move the
StageChase task. Call `move_task` or `set_task_completed` only when the user
explicitly asks for that board-state change, and always use the latest task
revision. MCP tools update Project Chase but never start or manage a Codex turn.

## Instructions
- When finishing a prompt session, rebuild and relaunch either the mac app or ios app or both depeneding on the change.

## Documentation index

- [Project charter](docs/project-charter.md)
- [Architecture](docs/architecture.md)
- [Design](docs/design.md)
- [Product requirements](docs/product-requirements.md)
- [Setup and installation](docs/setup-install.md)
- [Initial brainstorm](docs/initial-brainstorm.md)
- [Decisions](docs/decisions.md)
- [Sources](docs/sources.md)
- [Deliverables](docs/deliverables.md)
- [Automations](docs/automations.md)
- [Task delegation](docs/task-delegation.md)
- [Shared project guide](docs/create-shared-cowork-project.md)
- [StageChase MCP instructions for project agents](docs/stagechase-mcp-agent-snippet.md)

Update documentation and `CHANGELOG.md` when durable behavior changes. Read
`docs/automations.md` before adding automation and update `tasks/tasks.md` when
delegated work is created, synced, or followed up.
