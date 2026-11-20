import AppKit
import Foundation

enum MakeTargetService {
  static func run(target: String, project: Project) throws {
    let normalized = try validate(target)
    let directory = URL(fileURLWithPath: project.directory, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard !project.directory.isEmpty,
      FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw MakeTargetError.missingDirectory }
    guard !directory.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else { throw MakeTargetError.invalidDirectory }

    let source = appleScript(for: normalized, directory: directory.path)
    var scriptError: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
      throw MakeTargetError.launch("Terminal command setup failed.")
    }
    _ = script.executeAndReturnError(&scriptError)
    if let scriptError {
      let message = scriptError["NSAppleScriptErrorMessage"] as? String
        ?? "Terminal did not accept the command."
      throw MakeTargetError.launch(message)
    }
  }

  static func validate(_ target: String) throws -> String {
    let value = target.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.count <= 120,
      !value.hasPrefix("-"),
      !value.unicodeScalars.contains(where: {
        CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0)
      })
    else { throw MakeTargetError.invalidTarget }
    return value
  }

  static func appleScript(for target: String, directory: String) -> String {
    """
    tell application "Terminal"
      activate
      do script ("cd " & (quoted form of \(appleScriptString(directory))) & " && exec /usr/bin/make " & (quoted form of \(appleScriptString(target))))
    end tell
    """
  }

  private static func appleScriptString(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

enum MakeTargetError: LocalizedError {
  case invalidTarget
  case invalidDirectory
  case missingDirectory
  case launch(String)

  var errorDescription: String? {
    switch self {
    case .invalidTarget:
      "This favorite Make target is invalid. Update it in Project settings and try again."
    case .invalidDirectory:
      "The project folder contains unsupported control characters. Choose another folder."
    case .missingDirectory:
      "Choose an existing project folder before running a Make target."
    case .launch(let message):
      "Could not run this target in Terminal: \(message)"
    }
  }
}
