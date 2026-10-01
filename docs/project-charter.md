# Project charter

## Goal

Build StageChase as a private native macOS/iOS project board that organizes
ideas across five stages while keeping project plans, local code, and Codex
context together.

## Context

The supplied plan defines a Mac-authoritative architecture with a SwiftUI Mac
app, an iPhone companion, a five-stage workflow, local project configuration,
and explicit Codex work: automatic turns follow confirmed stage transitions
when enabled, while manual Desktop task prompts are started by the user and
report task state through the local StageChase MCP.

## Constraints and non-goals

The first release does not include Apple Reminders, arbitrary columns,
multi-user collaboration, public cloud hosting, automatic completion, calendar
scheduling, or user-facing command-line tools. No third-party dependency is
required for the foundation.

## People and roles

| Role | Person or system | Responsibility |
| --- | --- | --- |
| Product owner | Chase Seibert | Product direction, review, and release decisions |
| Implementer | Codex | Code, tests, documentation, and verification |
| Automation authority | StageChase Mac app | Local files, Codex sessions, Git/worktree state |

## Sources and independent investigation

The source plan is preserved in `docs/initial-brainstorm.md`. Implementation can
inspect the local Xcode project, configured Codex desktop behavior, the local
Wi-Fi route, and the configured project directories. Public name/store and
trademark checks remain separate from implementation.

## Questions to answer

- How should local Wi-Fi pairing and command validation be verified on devices?
- Which Codex desktop/session adapter is stable enough for persisted planning?
- How should dirty checkout detection distinguish unrelated user changes?
- What backup/export format protects the local task database?

## Deliverables

The first deliverable is the native board foundation tracked in
`docs/deliverables.md`. Follow-on deliverables are pairing, synchronization,
planning automation, implementation automation, and hardening.

## Status and next session

Status: foundation and experimental local Wi-Fi sync implementation are
build-verified; device-level sync acceptance remains open. The sync path is
Mac-authoritative and must not start Codex during ordinary refresh.
