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

## 2026-09-29 — Prototype Mac-authoritative sync on trusted local Wi-Fi

For the initial phone sync increment, keep the Mac app open as the authority and
use a user-enabled local TCP listener. Pair by short-lived code; code entry
automatically authorizes the phone without desktop confirmation. Treat the
code as a temporary bearer credential. Protect framed application messages with
AES-GCM and store device keys in
Keychain. This transport is not TLS and is restricted to a trusted local Wi-Fi
network. Tailnet setup is deferred by user direction. Keep phone state in a
separate replica and durable outbox; leave device-level acceptance open until
pairing and propagation are visibly exercised on devices.
