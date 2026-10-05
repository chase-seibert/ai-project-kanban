import AppKit
import Darwin
import Foundation

let bundleIdentifier = "com.cseibert.StageChaseMac"
let timeout: TimeInterval = 20

let runningApps = NSRunningApplication.runningApplications(
  withBundleIdentifier: bundleIdentifier)

for app in runningApps where !app.isTerminated {
  guard app.terminate() else {
    fputs(
      "Could not request a graceful quit from StageChase (PID \(app.processIdentifier)).\n",
      stderr
    )
    exit(EXIT_FAILURE)
  }
}

let deadline = Date().addingTimeInterval(timeout)
while Date() < deadline {
  let remainingApps = NSRunningApplication.runningApplications(
    withBundleIdentifier: bundleIdentifier
  ).filter { !$0.isTerminated }
  if remainingApps.isEmpty { break }
  _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
}

let remainingApps = NSRunningApplication.runningApplications(
  withBundleIdentifier: bundleIdentifier
).filter { !$0.isTerminated }
if !remainingApps.isEmpty {
  fputs(
    "StageChase did not quit within \(Int(timeout)) seconds; not launching another copy.\n",
    stderr
  )
  exit(EXIT_FAILURE)
}
