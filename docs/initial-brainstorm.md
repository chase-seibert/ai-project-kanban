# Initial brainstorm

Source: the user-supplied StageChase project plan dated 2026-09-28.

StageChase is a private project board for moving ideas from capture through
planning, implementation, and review, with Codex available when the user
explicitly advances work to an automation-owned stage. The fixed columns are
Inbox, Next, Planned, Implementation, and Review. The Mac owns local project
files, Codex sessions, Git state, and automation; the iPhone is the capture and
editing companion over a private connection.

The plan calls for native SwiftUI apps, local persistence, optimistic
concurrency, offline iOS writes, Markdown plans under lowercase `to-do/`,
idempotent planning, dirty-checkout detection, worktree-backed implementation,
activity/error history, and manual completion from Review.

The first implementation pass deliberately focuses on the Mac/iPhone board
foundation. Network pairing, a local API, Codex process/session adapters, and
Git worktree coordination remain follow-on phases.
