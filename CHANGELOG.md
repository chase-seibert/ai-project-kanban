# Changelog

## 2026-09-29

- Replaced prototype code with independently identified multi-project boards.
- Rebuilt both native interfaces: top-aligned lanes, quick capture, drag/drop,
  card reordering, task detail, activity, and explicit project creation.
- Fixed iPhone compatibility-mode sizing with generated launch configuration.
- Added versioned SwiftData/SQLite, legacy import, preserved backups,
  export/empty-library restore, and manual-task undo/redo.
- Added Codex app-server integration with durable runs, progress, logs, approvals,
  session links, stop/retry, structured outcomes, and dirty-checkout isolation.
- Added Latest Luna · High model defaults, project/task overrides, model
  catalog validation, and saved model/effort snapshots for confirmed runs and retries.
- Added model/persistence regressions and offline runner integration fixtures.
- Explicitly labeled the still-unimplemented Mac–iPhone synchronization boundary.

## 2026-09-28

- Created the StageChase macOS and iOS SwiftUI app targets.
- Added the shared fixed-stage data model, local persistence, revisioned task
  transitions, activity history, and structured automation references.
- Added board/task editing interfaces for Mac and iPhone.
- Added Swift package tests and Makefile build/test/simulator/device targets.
