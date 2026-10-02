import CryptoKit
import Foundation
import Network

@MainActor @Observable final class MCPServer {
  private(set) var status = "Off"
  private(set) var endpoint: String?
  private(set) var error: String?
  private let repository: LibraryRepository
  private let token: String
  var onLibraryChanged: ((Library) -> Void)?
  private var listener: NWListener?

  init(repository: LibraryRepository, preferences: UserDefaults = .standard) {
    self.repository = repository
    if let existing = preferences.string(forKey: "stageChaseMCPToken"),
      existing.range(of: #"^[a-f0-9-]{36}$"#, options: .regularExpression) != nil
    {
      token = existing
    } else {
      let newToken = UUID().uuidString.lowercased()
      preferences.set(newToken, forKey: "stageChaseMCPToken")
      token = newToken
    }
  }

  func start() {
    guard listener == nil else { return }
    do {
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(
        host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: 49282)!)
      let listener = try NWListener(using: parameters)
      self.listener = listener
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in self?.accept(connection) }
      }
      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor in
          guard let self else { return }
          switch state {
          case .ready:
            self.status = "Listening on this Mac"
            self.endpoint = "http://127.0.0.1:49282/mcp/\(self.token)"
            self.error = nil
          case .failed(let failure):
            self.status = "Unavailable"
            self.error = failure.localizedDescription
            self.listener?.cancel()
            self.listener = nil
          case .cancelled:
            self.status = "Off"
            self.endpoint = nil
          default: break
          }
        }
      }
      listener.start(queue: .main)
      status = "Starting"
    } catch {
      status = "Unavailable"
      self.error = error.localizedDescription
    }
  }

  func stop() {
    listener?.cancel()
    listener = nil
    status = "Off"
    endpoint = nil
  }

  private func accept(_ connection: NWConnection) {
    connection.start(queue: .main)
    receive(connection, data: Data())
  }

  private func receive(_ connection: NWConnection, data: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
      [weak self] chunk, _, done, failure in
      Task { @MainActor in
        guard let self else {
          connection.cancel()
          return
        }
        let combined = data + (chunk ?? Data())
        if let failure {
          self.error = failure.localizedDescription
          connection.cancel()
          return
        }
        if let request = Self.httpRequest(combined) {
          let response = await self.handle(request)
          let bytes = Self.httpResponse(response)
          connection.send(
            content: bytes, completion: .contentProcessed { _ in connection.cancel() })
        } else if done || combined.count > 65_536 {
          let bytes = Self.httpResponse(
            (413, Self.rpcError(nil, code: -32000, message: "Request too large.")))
          connection.send(
            content: bytes, completion: .contentProcessed { _ in connection.cancel() })
        } else {
          self.receive(connection, data: combined)
        }
      }
    }
  }

  private func handle(_ request: (String, String, Data)) async -> (Int, Data) {
    let (method, path, body) = request
    guard path == "/mcp/\(token)" else { return (404, Data()) }
    guard method == "POST" else { return (405, Data()) }
    let message: [String: Any]
    do {
      guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw BoardError.invalid("Expected a JSON-RPC object.")
      }
      message = object
    } catch { return (400, Self.rpcError(nil, code: -32700, message: "Invalid JSON.")) }
    let id = message["id"]
    guard let rpcMethod = message["method"] as? String else {
      return (400, Self.rpcError(id, code: -32600, message: "Invalid JSON-RPC request."))
    }
    if rpcMethod.hasPrefix("notifications/") { return (202, Data()) }
    switch rpcMethod {
    case "initialize":
      return (
        200,
        Self.rpcResult(
          id,
          result: [
            "protocolVersion": (message["params"] as? [String: Any])?["protocolVersion"] as? String
              ?? "2025-03-26",
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "stagechase", "version": "1.0.0"],
            "instructions":
              "Task reads and writes update the local StageChase library. MCP stage moves are explicit and never start Codex work. Only the user can complete or reopen a task in StageChase; MCP has no completion write.",
          ])
      )
    case "ping": return (200, Self.rpcResult(id, result: [:]))
    case "tools/list": return (200, Self.rpcResult(id, result: ["tools": Self.tools]))
    case "tools/call":
      let params = message["params"] as? [String: Any] ?? [:]
      guard let name = params["name"] as? String else {
        return (200, Self.rpcError(id, code: -32602, message: "A tool name is required."))
      }
      let arguments = params["arguments"] as? [String: Any] ?? [:]
      do {
        let result = try await callTool(name, arguments: arguments)
        let data =
          (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
          ?? Data("{}".utf8)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return (
          200,
          Self.rpcResult(
            id, result: ["content": [["type": "text", "text": text]], "structuredContent": result])
        )
      } catch {
        return (
          200,
          Self.rpcResult(
            id,
            result: [
              "isError": true, "content": [["type": "text", "text": error.localizedDescription]],
            ])
        )
      }
    default: return (200, Self.rpcError(id, code: -32601, message: "Method not found."))
    }
  }

  func callTool(_ name: String, arguments: [String: Any]) async throws -> [String: Any] {
    let library = try await repository.load()
    switch name {
    case "list_projects":
      return [
        "projects": library.projects.map { ["id": $0.id.uuidString.lowercased(), "name": $0.name] }
      ]
    case "list_tasks":
      let projectID = try uuid("project_id", arguments)
      guard library.projects.contains(where: { $0.id == projectID }) else {
        throw BoardError.missing
      }
      let stage = try stageFilter(arguments["stage"])
      let includeCompleted = arguments["include_completed"] as? Bool ?? false
      let limit = min(max(arguments["limit"] as? Int ?? 40, 1), 100)
      let tasks = library.items(in: projectID, stage: stage, completed: includeCompleted).prefix(
        limit)
      return ["tasks": tasks.map { taskJSON($0) }]
    case "read_task":
      let projectID = try uuid("project_id", arguments)
      let taskID = try uuid("task_id", arguments)
      guard let task = library.tasks.first(where: { $0.id == taskID && $0.projectID == projectID })
      else { throw BoardError.missing }
      return taskJSON(task, detailed: true)
    case "create_task":
      let projectID = try uuid("project_id", arguments)
      guard library.projects.contains(where: { $0.id == projectID }) else {
        throw BoardError.missing
      }
      let operationID = try uuid("operation_id", arguments)
      let title = try string("title", arguments, max: 300)
      let notes = try optionalString("notes", arguments, max: 8_000) ?? ""
      let stage = try parseStage(arguments["stage"] as? String) ?? .inbox
      var task = WorkItem(projectID: projectID, title: title, stage: stage)
      task.id = operationID
      task.notes = notes
      let result = try await commit(
        .createTask(task), operationID: operationID, arguments: arguments)
      return taskJSON(try requiredTask(task.id, in: result))
    case "begin_task":
      let projectID = try uuid("project_id", arguments)
      let taskID = try uuid("task_id", arguments)
      guard let task = library.tasks.first(where: { $0.id == taskID && $0.projectID == projectID })
      else { throw BoardError.missing }
      let operationID = try uuid("operation_id", arguments)
      var run = AgentRun(task: task, kind: .task)
      run.id = operationID
      run.source = .codexDesktop
      run.status = .running
      run.summary = "Work started in Codex Desktop."
      let result = try await commit(
        .beginExternalRun(run), operationID: operationID, arguments: arguments)
      return [
        "run_id": run.id.uuidString.lowercased(),
        "task": taskJSON(try requiredTask(taskID, in: result)),
      ]
    case "move_task":
      let projectID = try uuid("project_id", arguments)
      let taskID = try uuid("task_id", arguments)
      guard library.tasks.contains(where: { $0.id == taskID && $0.projectID == projectID }) else {
        throw BoardError.missing
      }
      let revision = try integer("expected_revision", arguments)
      let stage = try stageFilter(arguments["stage"]).unwrapStage()
      let operationID = try uuid("operation_id", arguments)
      let result = try await commit(
        .move(taskID, stage, expectedRevision: revision), operationID: operationID,
        arguments: arguments)
      return taskJSON(try requiredTask(taskID, in: result))
    case "attach_task_plan":
      let projectID = try uuid("project_id", arguments)
      let taskID = try uuid("task_id", arguments)
      guard let project = library.projects.first(where: { $0.id == projectID }),
        let task = library.tasks.first(where: { $0.id == taskID && $0.projectID == projectID })
      else { throw BoardError.missing }
      let revision = try integer("expected_revision", arguments)
      let relativePath = try string("plan_path", arguments, max: 2_000)
      let operationID = try uuid("operation_id", arguments)
      let url = try PlanFileStore.resolve(
        projectDirectory: project.directory, relativePath: relativePath)
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular,
        let contents = try? Data(contentsOf: url),
        let text = String(data: contents, encoding: .utf8),
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw BoardError.invalid("plan_path must identify a readable, nonempty Markdown file.")
      }
      var updated = task
      updated.planPath = relativePath
      let result = try await commit(
        .editTask(updated, expectedRevision: revision), operationID: operationID,
        arguments: arguments)
      return taskJSON(try requiredTask(taskID, in: result), detailed: true)
    case "report_task_update":
      let projectID = try uuid("project_id", arguments)
      let taskID = try uuid("task_id", arguments)
      let runID = try uuid("run_id", arguments)
      guard
        let run = library.runs.first(where: {
          $0.id == runID && $0.taskID == taskID && $0.projectID == projectID
            && $0.source == .codexDesktop
        })
      else { throw BoardError.missing }
      guard library.tasks.contains(where: { $0.id == taskID && $0.projectID == projectID }) else {
        throw BoardError.missing
      }
      let revision = try integer("expected_revision", arguments)
      let message = try string("message", arguments, max: 2_000)
      let operationID = try uuid("operation_id", arguments)
      let status = try externalStatus(arguments["status"] as? String, finishing: false)
      let result = try await commit(
        .reportExternalRun(run.id, message, status, expectedTaskRevision: revision),
        operationID: operationID, arguments: arguments)
      return [
        "run_id": runID.uuidString.lowercased(),
        "task": taskJSON(try requiredTask(taskID, in: result), detailed: true),
      ]
    case "finish_task":
      let projectID = try uuid("project_id", arguments)
      let taskID = try uuid("task_id", arguments)
      let runID = try uuid("run_id", arguments)
      guard
        let run = library.runs.first(where: {
          $0.id == runID && $0.taskID == taskID && $0.projectID == projectID
            && $0.source == .codexDesktop
        })
      else { throw BoardError.missing }
      guard library.tasks.contains(where: { $0.id == taskID && $0.projectID == projectID }) else {
        throw BoardError.missing
      }
      let revision = try integer("expected_revision", arguments)
      let message = try string("message", arguments, max: 2_000)
      let operationID = try uuid("operation_id", arguments)
      let status = try externalStatus(arguments["status"] as? String, finishing: true)
      let result = try await commit(
        .reportExternalRun(run.id, message, status, expectedTaskRevision: revision),
        operationID: operationID, arguments: arguments)
      return [
        "run_id": runID.uuidString.lowercased(),
        "task": taskJSON(try requiredTask(taskID, in: result), detailed: true),
      ]
    default: throw BoardError.invalid("Unknown StageChase tool ‘\(name)’.")
    }
  }

  private func commit(_ mutation: Mutation, operationID: UUID, arguments: [String: Any])
    async throws -> Library
  {
    let canonical = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
    let digest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    let result = try await repository.applyMCP(
      mutation, operationID: operationID, fingerprint: digest)
    onLibraryChanged?(result.library)
    return result.library
  }

  private func taskJSON(_ task: WorkItem, detailed: Bool = false) -> [String: Any] {
    var result: [String: Any] = [
      "id": task.id.uuidString.lowercased(), "project_id": task.projectID.uuidString.lowercased(),
      "title": task.title, "stage": task.stage.rawValue, "completed": task.completed,
      "revision": task.revision,
    ]
    if detailed {
      result["notes"] = task.notes
      result["plan_path"] = task.planPath as Any? ?? NSNull()
      result["updated_at"] = ISO8601DateFormatter().string(from: task.updatedAt)
      result["latest_codex_update"] = task.latestCodexUpdate as Any? ?? NSNull()
      result["latest_codex_update_at"] =
        task.latestCodexUpdateAt.map {
          ISO8601DateFormatter().string(from: $0)
        } as Any? ?? NSNull()
    }
    return result
  }

  private func requiredTask(_ id: UUID, in library: Library) throws -> WorkItem {
    guard let task = library.tasks.first(where: { $0.id == id }) else {
      throw BoardError.invalid(
        "The task was removed after this operation. Refresh the project and retry only if still needed."
      )
    }
    return task
  }

  private func uuid(_ key: String, _ arguments: [String: Any]) throws -> UUID {
    guard let value = arguments[key] as? String, let uuid = UUID(uuidString: value) else {
      throw BoardError.invalid("\(key) must be a UUID.")
    }
    return uuid
  }
  private func string(_ key: String, _ arguments: [String: Any], max: Int) throws -> String {
    guard let value = arguments[key] as? String else {
      throw BoardError.invalid("\(key) is required.")
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= max else {
      throw BoardError.invalid("\(key) must contain 1 to \(max) characters.")
    }
    return trimmed
  }
  private func optionalString(_ key: String, _ arguments: [String: Any], max: Int) throws -> String?
  {
    guard let value = arguments[key] as? String else { return nil }
    guard value.count <= max else { throw BoardError.invalid("\(key) exceeds \(max) characters.") }
    return value
  }
  private func integer(_ key: String, _ arguments: [String: Any]) throws -> Int {
    guard let value = arguments[key] as? Int else {
      throw BoardError.invalid("\(key) must be an integer.")
    }
    return value
  }
  private func externalStatus(_ raw: String?, finishing: Bool) throws -> RunStatus {
    let allowed: [RunStatus] =
      finishing ? [.succeeded, .failed, .cancelled] : [.running, .needsInput]
    guard let raw, let status = RunStatus(rawValue: raw), allowed.contains(status) else {
      throw BoardError.invalid(
        "status must be one of: \(allowed.map(\.rawValue).joined(separator: ", ")).")
    }
    return status
  }
  private func stageFilter(_ value: Any?) throws -> WorkflowStage? {
    guard let value else { return nil }
    guard let raw = value as? String, let stage = WorkflowStage(rawValue: raw) else {
      throw BoardError.invalid(
        "stage must be one of: \(WorkflowStage.allCases.map(\.rawValue).joined(separator: ", ")).")
    }
    return stage
  }
  private func parseStage(_ raw: String?) throws -> WorkflowStage? { try stageFilter(raw) }
}

extension Optional where Wrapped == WorkflowStage {
  fileprivate func unwrapStage() throws -> WorkflowStage {
    guard let self else { throw BoardError.invalid("stage is required.") }
    return self
  }
}

extension MCPServer {
  static let tools: [[String: Any]] = [
    tool(
      "list_projects", "List StageChase projects and stable IDs.",
      ["type": "object", "properties": [:], "additionalProperties": false]),
    tool(
      "list_tasks", "List tasks in one project, optionally filtering by workflow stage.",
      [
        "type": "object",
        "properties": [
          "project_id": uuidSchema, "stage": stageSchema, "include_completed": ["type": "boolean"],
          "limit": ["type": "integer", "minimum": 1, "maximum": 100],
        ], "required": ["project_id"], "additionalProperties": false,
      ]),
    tool(
      "read_task", "Read one task and verify it belongs to the project.",
      [
        "type": "object", "properties": ["project_id": uuidSchema, "task_id": uuidSchema],
        "required": ["project_id", "task_id"], "additionalProperties": false,
      ]),
    tool(
      "begin_task",
      "Record that work began in the already-open Codex Desktop session. This never starts a session or turn.",
      [
        "type": "object",
        "properties": [
          "project_id": uuidSchema, "task_id": uuidSchema, "operation_id": uuidSchema,
        ],
        "required": ["project_id", "task_id", "operation_id"], "additionalProperties": false,
      ]),
    tool(
      "create_task",
      "Create an Inbox task in a project. Supply a fresh operation_id UUID for each new task.",
      [
        "type": "object",
        "properties": [
          "project_id": uuidSchema, "operation_id": uuidSchema,
          "title": ["type": "string", "maxLength": 300],
          "notes": ["type": "string", "maxLength": 8000], "stage": stageSchema,
        ], "required": ["project_id", "operation_id", "title"], "additionalProperties": false,
      ]),
    tool(
      "move_task",
      "Move a task between the five existing stages. Requires its current revision; this does not start Codex.",
      [
        "type": "object",
        "properties": [
          "project_id": uuidSchema, "task_id": uuidSchema, "operation_id": uuidSchema,
          "expected_revision": ["type": "integer"], "stage": stageSchema,
        ], "required": ["project_id", "task_id", "operation_id", "expected_revision", "stage"],
        "additionalProperties": false,
      ]),
    tool(
      "attach_task_plan",
      "Attach an existing readable, nonempty project-relative Markdown plan. Requires its current task revision. Does not move, complete, or start Codex.",
      [
        "type": "object",
        "properties": [
          "project_id": uuidSchema, "task_id": uuidSchema, "operation_id": uuidSchema,
          "expected_revision": ["type": "integer"],
          "plan_path": ["type": "string", "minLength": 1, "maxLength": 2000],
        ],
        "required": ["project_id", "task_id", "operation_id", "expected_revision", "plan_path"],
        "additionalProperties": false,
      ]),
    tool(
      "report_task_update",
      "Save a concise latest update from the Codex session. This changes task revision but not its stage or completion flag.",
      [
        "type": "object",
        "properties": [
          "project_id": uuidSchema, "task_id": uuidSchema, "run_id": uuidSchema,
          "operation_id": uuidSchema,
          "expected_revision": ["type": "integer"],
          "message": ["type": "string", "minLength": 1, "maxLength": 2000],
          "status": ["type": "string", "enum": ["running", "needsInput"]],
        ],
        "required": [
          "project_id", "task_id", "run_id", "operation_id", "expected_revision", "message",
          "status",
        ],
        "additionalProperties": false,
      ]),
    tool(
      "finish_task",
      "Record the outcome and latest concise message from an external Codex Desktop session. Does not move or complete the task.",
      [
        "type": "object",
        "properties": [
          "project_id": uuidSchema, "task_id": uuidSchema, "run_id": uuidSchema,
          "operation_id": uuidSchema, "expected_revision": ["type": "integer"],
          "message": ["type": "string", "minLength": 1, "maxLength": 2000],
          "status": ["type": "string", "enum": ["succeeded", "failed", "cancelled"]],
        ],
        "required": [
          "project_id", "task_id", "run_id", "operation_id", "expected_revision", "message",
          "status",
        ],
        "additionalProperties": false,
      ]),
  ]
  fileprivate static var uuidSchema: [String: Any] { ["type": "string", "format": "uuid"] }
  fileprivate static var stageSchema: [String: Any] {
    ["type": "string", "enum": WorkflowStage.allCases.map(\.rawValue)]
  }
  fileprivate static func tool(_ name: String, _ description: String, _ schema: [String: Any])
    -> [String: Any]
  {
    [
      "name": name, "description": description, "inputSchema": schema,
      "annotations": [
        "readOnlyHint": ["list_projects", "list_tasks", "read_task"].contains(name),
        "destructiveHint": false, "openWorldHint": false,
      ],
    ]
  }
  fileprivate static func rpcResult(_ id: Any?, result: Any) -> Data {
    var value: [String: Any] = ["jsonrpc": "2.0", "result": result]
    if let id { value["id"] = id }
    return (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
      ?? Data("{}".utf8)
  }
  fileprivate static func rpcError(_ id: Any?, code: Int, message: String) -> Data {
    var value: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
    if let id { value["id"] = id }
    return (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
      ?? Data("{}".utf8)
  }
  fileprivate static func httpRequest(_ data: Data) -> (String, String, Data)? {
    guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
      let header = String(data: data[..<headerEnd.lowerBound], encoding: .utf8)
    else { return nil }
    let lines = header.components(separatedBy: "\r\n")
    guard let first = lines.first else { return nil }
    let parts = first.split(separator: " ")
    guard parts.count >= 2 else { return nil }
    let length =
      lines.dropFirst().first(where: { $0.lowercased().hasPrefix("content-length:") })
      .flatMap {
        Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "")
      } ?? 0
    let bodyStart = headerEnd.upperBound
    guard data.count >= bodyStart + length else { return nil }
    return (String(parts[0]), String(parts[1]), data.subdata(in: bodyStart..<(bodyStart + length)))
  }
  fileprivate static func httpResponse(_ response: (Int, Data)) -> Data {
    let (status, body) = response
    let reason =
      status == 200
      ? "OK"
      : status == 202
        ? "Accepted"
        : status == 404
          ? "Not Found"
          : status == 405
            ? "Method Not Allowed" : status == 413 ? "Payload Too Large" : "Bad Request"
    let head =
      "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: null\r\n\r\n"
    return Data(head.utf8) + body
  }
}
