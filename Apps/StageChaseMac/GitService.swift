import Foundation

struct GitRepositoryStatus: Sendable {
  var branch: String?
  var head: String?
  var upstream: String?
  var aheadCount: Int
  var behindCount: Int
  var changedFileCount: Int
  var stagedFileCount: Int
  var unstagedFileCount: Int
  var untrackedFileCount: Int
  var isEmptyRepository: Bool
  var hasChanges: Bool { changedFileCount > 0 }
  var canPush: Bool { upstream != nil && aheadCount > 0 && behindCount == 0 }
}

struct GitCommitResult: Sendable {
  var hash: String
}

enum GitServiceError: LocalizedError {
  case missingFolder
  case noChanges
  case command(String)

  var errorDescription: String? {
    switch self {
    case .missingFolder:
      "Choose an existing project folder to use Git."
    case .noChanges:
      "There are no changes to commit."
    case .command(let message): message
    }
  }
}

struct GitService: Sendable {
  func status(in folder: URL) async throws -> GitRepositoryStatus {
    try await Task.detached(priority: .utility) {
      let folder = try Self.validateFolder(folder)
      let output = try Self.run(
        ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"], at: folder)
      var records = output.split(separator: 0, omittingEmptySubsequences: true).map(Array.init)
      let branch: String?
      if let first = records.first, first.starts(with: Array("## ".utf8)) {
        let description = String(decoding: first.dropFirst(3), as: UTF8.self)
        if description.hasPrefix("No commits yet on ") {
          branch = String(description.dropFirst("No commits yet on ".count))
        } else if description == "HEAD (no branch)" {
          branch = nil
        } else {
          branch =
            String(description.split(whereSeparator: \.isWhitespace).first ?? "")
            .components(separatedBy: "...").first
        }
        records.removeFirst()
      } else {
        branch = nil
      }

      var staged = 0
      var unstaged = 0
      var untracked = 0
      var changedFiles = 0
      var index = 0
      while index < records.count {
        let record = records[index]
        index += 1
        guard record.count >= 3 else { continue }
        let x = record[0]
        let y = record[1]
        changedFiles += 1
        if x == UInt8(ascii: "?") {
          untracked += 1
        } else {
          if x != UInt8(ascii: " ") { staged += 1 }
          if y != UInt8(ascii: " ") { unstaged += 1 }
          if x == UInt8(ascii: "R") || y == UInt8(ascii: "R")
            || x == UInt8(ascii: "C") || y == UInt8(ascii: "C")
          {
            index += 1
          }
        }
      }
      let headResult = try? Self.runResult(["rev-parse", "--verify", "HEAD"], at: folder)
      let head =
        headResult?.status == 0
        ? String(decoding: headResult!.output, as: UTF8.self).trimmingCharacters(
          in: .whitespacesAndNewlines)
        : nil
      let upstreamResult = try? Self.runResult(
        ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], at: folder)
      let upstream =
        upstreamResult?.status == 0
        ? String(decoding: upstreamResult!.output, as: UTF8.self).trimmingCharacters(
          in: .whitespacesAndNewlines)
        : nil
      var aheadCount = 0
      var behindCount = 0
      if upstream != nil, head != nil,
        let counts = try? Self.run(
          ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], at: folder)
      {
        let values = String(decoding: counts, as: UTF8.self)
          .split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        if values.count == 2 {
          behindCount = values[0]
          aheadCount = values[1]
        }
      }
      return GitRepositoryStatus(
        branch: branch, head: head, upstream: upstream, aheadCount: aheadCount,
        behindCount: behindCount, changedFileCount: changedFiles,
        stagedFileCount: staged, unstagedFileCount: unstaged,
        untrackedFileCount: untracked, isEmptyRepository: head == nil)
    }.value
  }

  func push(in folder: URL) async throws {
    try await Task.detached(priority: .userInitiated) {
      let folder = try Self.validateFolder(folder)
      let upstreamData = try Self.run(
        ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], at: folder)
      let upstream = String(decoding: upstreamData, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard let separator = upstream.firstIndex(of: "/") else {
        throw GitServiceError.command("The configured upstream could not be identified.")
      }
      let remote = String(upstream[..<separator])
      let branch = String(upstream[upstream.index(after: separator)...])
      guard !remote.isEmpty, !branch.isEmpty else {
        throw GitServiceError.command("The configured upstream could not be identified.")
      }
      _ = try Self.run(["push", "--", remote, "HEAD:refs/heads/\(branch)"], at: folder)
    }.value
  }

  func commitAll(in folder: URL, taskTitle: String) async throws -> GitCommitResult {
    let message = Self.commitMessage(taskTitle)
    guard !message.isEmpty else {
      throw GitServiceError.command("Add a task title before committing.")
    }
    return try await Task.detached(priority: .userInitiated) {
      let folder = try Self.validateFolder(folder)
      let status = try Self.run(
        ["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: folder)
      guard !status.isEmpty else { throw GitServiceError.noChanges }
      _ = try Self.run(["add", "-A"], at: folder)
      _ = try Self.run(["commit", "-m", message], at: folder)
      let hash = try Self.run(["rev-parse", "--verify", "HEAD"], at: folder)
      return GitCommitResult(
        hash: String(decoding: hash, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }.value
  }

  static func commitMessage(_ title: String) -> String {
    title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func validateFolder(_ folder: URL) throws -> URL {
    guard !folder.path.isEmpty else { throw GitServiceError.missingFolder }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw GitServiceError.missingFolder }
    return folder
  }

  private static func run(_ arguments: [String], at folder: URL) throws -> Data {
    let result = try runResult(arguments, at: folder)
    guard result.status == 0 else {
      let detail = String(decoding: result.output, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      throw GitServiceError.command(
        detail.isEmpty ? "Git failed with exit code \(result.status)." : detail)
    }
    return result.output
  }

  private static func runResult(_ arguments: [String], at folder: URL) throws -> (
    status: Int32, output: Data
  ) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = folder
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch {
      throw GitServiceError.command("Could not start Git: \(error.localizedDescription)")
    }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, output)
  }
}
