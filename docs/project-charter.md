# Project charter

## Goal

Build StageChase as a private native macOS/iOS project board that moves ideas
from Inbox to Review while keeping project plans, local code, and Codex context
together.

## Context

The supplied plan defines a Mac-authoritative architecture with a SwiftUI Mac
app, an iPhone companion, a five-stage workflow, local project configuration,
and explicit Codex automation triggered only by confirmed stage transitions.

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

The source plan is preserved in `docs/initial-brainstorm.md`. Future work can
inspect the local Xcode project, configured Codex desktop behavior, the chosen
Tailscale network, and the configured project directories. Public name/store
and trademark checks remain separate from implementation.

## Questions to answer

- What local API and pairing design is appropriate for one-user Tailscale access?
- Which Codex desktop/session adapter is stable enough for persisted planning?
- How should dirty checkout detection distinguish unrelated user changes?
- What backup/export format protects the local task database?

## Deliverables

The first deliverable is the native board foundation tracked in
`docs/deliverables.md`. Follow-on deliverables are pairing, synchronization,
planning automation, implementation automation, and hardening.

## Status and next session

Status: foundation implemented and build-verified. Next recommended session:
add the Mac local API and pairing spike, then introduce a protocol-backed
automation coordinator without starting Codex during ordinary sync.
