import Foundation
import Observation

enum MakeTargetStatus: Equatable {
  case idle
  case running
  case succeeded
  case failed(String)
  case stopped

  var label: String {
    switch self {
    case .idle: "Ready"
    case .running: "Running"
    case .succeeded: "Succeeded"
    case .failed: "Failed"
    case .stopped: "Stopped"
    }
  }
}

@MainActor @Observable final class MakeTargetService {
  private(set) var status: MakeTargetStatus = .idle
  private(set) var projectID: UUID?
  private(set) var projectName = ""
  private(set) var target = ""
  private(set) var output = ""
  private(set) var outputWasTruncated = false
  var copyableOutput: String {
    (outputWasTruncated ? "[Retained output tail (32 KB)]\n" : "") + output
  }
  private(set) var isRunning = false
  private let maximumOutputBytes = 32_000
  private var process: Process?
  private var stopping = false

  func start(target: String, project: Project) throws {
    guard !isRunning else { throw MakeTargetError.alreadyRunning }
    let normalized = try Self.validate(target)
    let directory = URL(fileURLWithPath: project.directory, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard !project.directory.isEmpty,
      FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw MakeTargetError.missingDirectory }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/make")
    process.arguments = [normalized]
    process.currentDirectoryURL = directory
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    self.process = process
    self.projectID = project.id
    self.projectName = project.name
    self.target = normalized
    self.output = ""
    self.outputWasTruncated = false
    self.status = .running
    self.isRunning = true
    self.stopping = false

    for pipe in [stdout, stderr] {
      pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
        let data = handle.availableData
        guard !data.isEmpty else {
          handle.readabilityHandler = nil
          return
        }
        let text = String(decoding: data, as: UTF8.self)
        Task { @MainActor [weak self] in self?.append(text) }
      }
    }
    process.terminationHandler = { [weak self] finished in
      Task { @MainActor [weak self] in
        guard let self, self.process === finished else { return }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        self.isRunning = false
        if self.stopping {
          self.status = .stopped
        } else if finished.terminationStatus == 0 {
          self.status = .succeeded
        } else {
          self.status = .failed("make exited with status \(finished.terminationStatus).")
        }
        self.process = nil
      }
    }
    do {
      try process.run()
    } catch {
      stdout.fileHandleForReading.readabilityHandler = nil
      stderr.fileHandleForReading.readabilityHandler = nil
      self.process = nil
      self.isRunning = false
      self.status = .failed(error.localizedDescription)
      throw MakeTargetError.launch(error.localizedDescription)
    }
  }

  func stop() {
    guard isRunning, let process else { return }
    stopping = true
    process.terminate()
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

  private func append(_ value: String) {
    output.append(value)
    if output.utf8.count > maximumOutputBytes {
      outputWasTruncated = true
      output = String(decoding: output.utf8.suffix(maximumOutputBytes), as: UTF8.self)
    }
  }
}

enum MakeTargetError: LocalizedError {
  case invalidTarget
  case missingDirectory
  case alreadyRunning
  case launch(String)

  var errorDescription: String? {
    switch self {
    case .invalidTarget:
      "Enter a nonempty Make target without a leading dash or line breaks."
    case .missingDirectory:
      "Choose an existing project folder before running a Make target."
    case .alreadyRunning:
      "A Make target is already running. Stop it before starting another."
    case .launch(let message):
      "Could not start make: \(message)"
    }
  }
}
