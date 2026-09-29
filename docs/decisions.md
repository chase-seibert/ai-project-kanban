# Decisions

## 2026-09-28 — Start with the board foundation

The supplied plan is larger than one safe implementation pass. Implement the
native Mac/iPhone board, shared model, local persistence, revisioned transitions,
and activity log first. Keep Codex, API, pairing, and Git/worktree operations
behind follow-on protocols so they cannot be accidentally invoked by polling.

## 2026-09-28 — Use five hardcoded stages

Inbox, Next, Planned, Implementation, and Review are application constants.
Custom columns are explicitly outside the first release.

## 2026-09-28 — Keep persistence dependency-free initially

Use an atomic JSON snapshot behind `JSONSnapshotStore` while the single-user
data shape is small. Revisit SwiftData when local API, migration, and backup
requirements are specified.
