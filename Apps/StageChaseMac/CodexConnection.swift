import Foundation

@MainActor protocol AgentConnection: AnyObject {
  var notification: ((String, [String: Any]) -> Void)? { get set }
  var request: ((Any, String, [String: Any]) -> Void)? { get set }
  var disconnected: ((String) -> Void)? { get set }
  func connect(executable: String) async throws
  func call(_ method: String, _ params: [String: Any]) async throws -> [String: Any]
  func respond(id: Any, result: [String: Any]) throws
  func reject(id: Any, message: String) throws
  func close()
}

/// JSONL transport for the official Codex app-server protocol. Never shells user input.
@MainActor final class CodexConnection: AgentConnection {
  var notification: ((String, [String: Any]) -> Void)?
  var request: ((Any, String, [String: Any]) -> Void)?
  var disconnected: ((String) -> Void)?
  private var process: Process?
  private var input: FileHandle?
  private var output: FileHandle?
  private var errors: FileHandle?
  private var buffer = Data()
  private var nextID = 1
  private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
  private var timeouts: [Int: Task<Void, Never>] = [:]
  var connected: Bool { process?.isRunning == true }

  func connect(executable: String) async throws {
    if connected { return }
    let task = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = ["app-server", "--listen", "stdio://"]
    task.standardInput = stdin
    task.standardOutput = stdout
    task.standardError = stderr
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] =
      "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:"
      + (environment["PATH"] ?? "")
    task.environment = environment
    input = stdin.fileHandleForWriting
    output = stdout.fileHandleForReading
    errors = stderr.fileHandleForReading
    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      Task { @MainActor [weak self] in self?.consume(data) }
    }
    // Drain stderr to prevent deadlocks; protocol errors are reported through JSON-RPC.
    stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
    task.terminationHandler = { [weak self] process in
      let status = process.terminationStatus
      Task { @MainActor [weak self] in self?.lostConnection("Codex app-server exited (\(status)).")
      }
    }
    process = task
    do {
      try task.run()
      _ = try await call(
        "initialize",
        ["clientInfo": ["name": "stagechase", "title": "StageChase", "version": "2.0.0"]])
      try send(["method": "initialized", "params": [:]])
    } catch {
      close()
      throw error
    }
  }

  func call(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
    guard connected else { throw BoardError.invalid("Codex is not connected.") }
    let id = nextID
    nextID += 1
    let response: Data = try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      do { try send(["id": id, "method": method, "params": params]) } catch {
        pending.removeValue(forKey: id)?.resume(throwing: error)
        return
      }
      timeouts[id] = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(45)) } catch { return }
        self?.pending.removeValue(forKey: id)?.resume(
          throwing: BoardError.invalid(
            "Codex did not answer \(method). Check the session before retrying."))
        self?.timeouts.removeValue(forKey: id)
      }
    }
    return try JSONSerialization.jsonObject(with: response) as? [String: Any] ?? [:]
  }

  func respond(id: Any, result: [String: Any]) throws { try send(["id": id, "result": result]) }
  func reject(id: Any, message: String) throws {
    try send(["id": id, "error": ["code": -32601, "message": message]])
  }

  func close() {
    output?.readabilityHandler = nil
    errors?.readabilityHandler = nil
    process?.terminationHandler = nil
    if process?.isRunning == true { process?.terminate() }
    process = nil
    input = nil
    buffer = Data()
    for continuation in pending.values {
      continuation.resume(throwing: BoardError.invalid("Codex connection closed."))
    }
    pending.removeAll()
    for timeout in timeouts.values { timeout.cancel() }
    timeouts.removeAll()
  }

  private func send(_ value: [String: Any]) throws {
    var data = try JSONSerialization.data(withJSONObject: value)
    data.append(0x0A)
    guard let input else { throw BoardError.invalid("Codex input pipe is closed.") }
    try input.write(contentsOf: data)
  }

  private func consume(_ data: Data) {
    guard !data.isEmpty else { return }
    buffer.append(data)
    guard buffer.count < 32 * 1024 * 1024 else {
      lostConnection("Codex returned an oversized message.")
      close()
      return
    }
    while let newline = buffer.firstIndex(of: 0x0A) {
      let line = buffer.prefix(upTo: newline)
      buffer.removeSubrange(...newline)
      guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
        continue
      }
      if let method = object["method"] as? String {
        let params = object["params"] as? [String: Any] ?? [:]
        if let id = object["id"] {
          request?(id, method, params)
        } else {
          notification?(method, params)
        }
      } else if let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
        timeouts.removeValue(forKey: id)?.cancel()
        if let error = object["error"] as? [String: Any] {
          continuation.resume(
            throwing: BoardError.invalid(error["message"] as? String ?? "Codex request failed."))
        } else {
          do {
            continuation.resume(
              returning: try JSONSerialization.data(
                withJSONObject: object["result"] as? [String: Any] ?? [:]))
          } catch { continuation.resume(throwing: error) }
        }
      }
    }
  }
  private func lostConnection(_ reason: String) {
    for continuation in pending.values { continuation.resume(throwing: BoardError.invalid(reason)) }
    pending.removeAll()
    for timeout in timeouts.values { timeout.cancel() }
    timeouts.removeAll()
    disconnected?(reason)
  }
}
