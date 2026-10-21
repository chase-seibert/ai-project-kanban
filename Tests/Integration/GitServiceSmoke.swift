import Foundation

@main struct GitServiceSmoke {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stagechase-git-smoke-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let bare = root.appendingPathComponent("remote.git")
    let local = root.appendingPathComponent("local")
    let other = root.appendingPathComponent("other")
    try command(["init", "--bare", "--initial-branch=main", bare.path], at: root)
    try command(["init", "--initial-branch=main", local.path], at: root)
    try configure(local)
    try writeCommit("one", in: local)
    try command(["remote", "add", "origin", bare.path], at: local)
    try command(["push", "--set-upstream", "origin", "main"], at: local)

    let service = GitService()
    var status = try await service.status(in: local)
    try expect(status.upstream == "origin/main", "upstream was not detected")
    try expect(status.aheadCount == 0 && status.behindCount == 0, "fresh upstream was not clean")

    try writeCommit("two", in: local)
    status = try await service.status(in: local)
    try expect(status.aheadCount == 1 && status.canPush, "ahead commit was not pushable")
    try await service.push(in: local)
    status = try await service.status(in: local)
    try expect(status.aheadCount == 0 && status.behindCount == 0, "push did not update status")
    let untracked = local.appendingPathComponent("untracked.txt")
    try Data("local only".utf8).write(to: untracked)
    status = try await service.status(in: local)
    try expect(status.hasChanges && !status.canPush, "uncommitted files were treated as pushable")
    try FileManager.default.removeItem(at: untracked)

    try command(["clone", bare.path, other.path], at: root)
    try configure(other)
    try writeCommit("remote", in: other)
    try command(["push", "origin", "main"], at: other)
    try command(["fetch", "origin"], at: local)
    status = try await service.status(in: local)
    try expect(status.behindCount == 1 && !status.canPush, "behind branch was treated as pushable")
    try writeCommit("local-divergence", in: local)

    let noUpstream = root.appendingPathComponent("no-upstream")
    try command(["init", "--initial-branch=main", noUpstream.path], at: root)
    try configure(noUpstream)
    try writeCommit("local", in: noUpstream)
    let noUpstreamStatus = try await service.status(in: noUpstream)
    try expect(
      noUpstreamStatus.upstream == nil && !noUpstreamStatus.canPush,
      "missing upstream was not reported")

    let hook = bare.appendingPathComponent("hooks/pre-receive")
    try Data("#!/bin/sh\nexit 1\n".utf8).write(to: hook)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
    do {
      try await service.push(in: local)
      throw SmokeFailure.assertion("remote rejection was not returned as an error")
    } catch is SmokeFailure {
      throw SmokeFailure.assertion("remote rejection was not returned as an error")
    } catch {
      print("GitService bare-remote scenarios passed.")
    }
  }

  private static func configure(_ folder: URL) throws {
    try command(["config", "user.name", "StageChase Test"], at: folder)
    try command(["config", "user.email", "stagechase@example.invalid"], at: folder)
  }

  private static func writeCommit(_ contents: String, in folder: URL) throws {
    try Data(contents.utf8).write(to: folder.appendingPathComponent("file.txt"))
    try command(["add", "file.txt"], at: folder)
    try command(["commit", "-m", contents], at: folder)
  }

  @discardableResult private static func command(_ arguments: [String], at folder: URL) throws
    -> String
  {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = folder
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw SmokeFailure.command("git \(arguments.joined(separator: " ")): \(text)")
    }
    return text
  }

  private static func expect(_ condition: Bool, _ message: String) throws {
    guard condition else { throw SmokeFailure.assertion(message) }
  }
}

private enum SmokeFailure: Error, CustomStringConvertible {
  case assertion(String)
  case command(String)
  var description: String {
    switch self {
    case .assertion(let message), .command(let message): message
    }
  }
}
