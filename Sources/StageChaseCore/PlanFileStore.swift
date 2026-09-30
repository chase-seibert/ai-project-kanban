import Foundation

public enum PlanFileError: LocalizedError, Sendable {
  case invalidProjectDirectory
  case invalidPlanPath
  case planOutsideProject
  case planUnavailable
  case planNotUTF8
  case emptyPlan
  case emptyFeedback
  case stalePlan
  case writeFailed(String)

  public var errorDescription: String? {
    switch self {
    case .invalidProjectDirectory:
      "Choose an existing project folder before appending feedback."
    case .invalidPlanPath:
      "The saved plan path must be a project-relative Markdown file."
    case .planOutsideProject:
      "The saved plan must remain inside its project folder."
    case .planUnavailable:
      "The saved plan could not be read. Check that the file exists and is accessible."
    case .planNotUTF8:
      "The saved plan is not valid UTF-8 Markdown, so feedback was not appended."
    case .emptyPlan:
      "The saved plan is empty. Add plan content before appending feedback."
    case .emptyFeedback:
      "Enter or dictate feedback before appending it."
    case .stalePlan:
      "The saved plan changed while feedback was being appended. Review it and try again."
    case .writeFailed(let reason):
      "Feedback could not be verified in the plan. Inspect the file before trying again. \(reason)"
    }
  }
}

/// Serializes coordinated appends to project Markdown plans without rewriting their contents.
public actor PlanFileStore {
  public init() {}

  public nonisolated static func resolve(
    projectDirectory: String, relativePath: String
  ) throws -> URL {
    guard projectDirectory.hasPrefix("/") else {
      throw PlanFileError.invalidProjectDirectory
    }
    let root = URL(fileURLWithPath: projectDirectory).standardizedFileURL
      .resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard root.path != "/",
      FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw PlanFileError.invalidProjectDirectory
    }
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
      relativePath.lowercased().hasSuffix(".md"),
      !relativePath.split(separator: "/").contains(".."),
      !relativePath.split(separator: "/").contains(".")
    else {
      throw PlanFileError.invalidPlanPath
    }
    let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
      .resolvingSymlinksInPath()
    guard candidate.path.hasPrefix(root.path + "/") else {
      throw PlanFileError.planOutsideProject
    }
    return candidate
  }

  public func appendFeedback(
    _ feedback: String, projectDirectory: String, relativePath: String
  ) throws {
    guard !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PlanFileError.emptyFeedback
    }
    let url = try Self.resolve(projectDirectory: projectDirectory, relativePath: relativePath)
    var coordinationError: NSError?
    var operationError: Error?
    var wroteAndVerified = false
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) {
      coordinatedURL in
      do {
        let attributes = try FileManager.default.attributesOfItem(atPath: coordinatedURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
          throw PlanFileError.planUnavailable
        }
        let original = try Data(contentsOf: coordinatedURL)
        guard let existingText = String(data: original, encoding: .utf8) else {
          throw PlanFileError.planNotUTF8
        }
        guard !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw PlanFileError.emptyPlan
        }

        let newline = existingText.contains("\r\n") ? "\r\n" : "\n"
        let separator: String
        if existingText.hasSuffix(newline + newline) {
          separator = ""
        } else if existingText.hasSuffix(newline) {
          separator = newline
        } else {
          separator = newline + newline
        }
        let suffix = separator + "## User feedback on the plan" + newline + newline + feedback
        var appended = original
        appended.append(contentsOf: suffix.utf8)
        try appended.write(to: coordinatedURL, options: .atomic)
        if let permissions = attributes[.posixPermissions] {
          try FileManager.default.setAttributes(
            [.posixPermissions: permissions], ofItemAtPath: coordinatedURL.path)
        }
        guard try Data(contentsOf: coordinatedURL) == appended else {
          throw PlanFileError.stalePlan
        }
        wroteAndVerified = true
      } catch {
        operationError = error
      }
    }
    if let operationError { throw operationError }
    if let coordinationError {
      throw PlanFileError.writeFailed(coordinationError.localizedDescription)
    }
    guard wroteAndVerified else { throw PlanFileError.planUnavailable }
  }
}
