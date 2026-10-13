#if os(macOS)
  import Foundation
  import Observation
  import Security
  import Darwin

  private struct CodexLogin: Codable, Equatable, Sendable {
    var tokens: Tokens?
    var lastRefresh: String?
    var apiKey: String?

    struct Tokens: Codable, Equatable, Sendable {
      var accessToken: String?
      var refreshToken: String?
      var idToken: String?
      var accountID: String?
      enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountID = "account_id"
      }
    }
    enum CodingKeys: String, CodingKey {
      case tokens
      case lastRefresh = "last_refresh"
      case apiKey = "OPENAI_API_KEY"
    }
  }

  private struct CodexLoginState: Equatable, Sendable {
    enum Source: Equatable, Sendable {
      case file(String)
      case keychain
    }
    var login: CodexLogin
    var source: Source
  }

  protocol CodexUsageFileAccess: Sendable {
    func exists(_ path: String) -> Bool
    func read(_ path: String) throws -> String
    func write(_ path: String, text: String) throws
  }

  struct LocalCodexUsageFileAccess: CodexUsageFileAccess {
    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: expand(path)) }
    func read(_ path: String) throws -> String {
      try String(contentsOfFile: expand(path), encoding: .utf8)
    }
    func write(_ path: String, text: String) throws {
      let expanded = expand(path)
      let url = URL(fileURLWithPath: expanded)
      let parent = url.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
      let temporary = parent.appendingPathComponent(
        ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
      let descriptor = temporary.path.withCString {
        Darwin.open(
          $0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(S_IRUSR | S_IWUSR))
      }
      guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      var openDescriptor = true
      var temporaryExists = true
      defer {
        if openDescriptor { _ = Darwin.close(descriptor) }
        if temporaryExists { temporary.path.withCString { _ = Darwin.unlink($0) } }
      }
      let data = Data(text.utf8)
      try data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        var offset = 0
        while offset < buffer.count {
          let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
          if count < 0 && errno == EINTR { continue }
          guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
          offset += count
        }
      }
      guard Darwin.fsync(descriptor) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      let closeResult = Darwin.close(descriptor)
      openDescriptor = false
      guard closeResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      let renameResult = temporary.path.withCString { source in
        expanded.withCString { destination in Darwin.rename(source, destination) }
      }
      guard renameResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      temporaryExists = false
    }
    private func expand(_ path: String) -> String {
      (path as NSString).expandingTildeInPath
    }
  }

  protocol CodexUsageKeychainAccess: Sendable {
    func read() throws -> String?
    func write(_ text: String) throws
  }

  struct SystemCodexUsageKeychainAccess: CodexUsageKeychainAccess {
    static let service = "Codex Auth"
    func read() throws -> String? {
      var query = baseQuery
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess else { throw CodexUsageError.keychainUnavailable }
      guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
        throw CodexUsageError.invalidLogin
      }
      return value
    }
    func write(_ text: String) throws {
      let attributes = [kSecValueData as String: Data(text.utf8)] as CFDictionary
      let status = SecItemUpdate(baseQuery as CFDictionary, attributes)
      if status == errSecItemNotFound {
        var query = baseQuery
        query[kSecValueData as String] = Data(text.utf8)
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CodexUsageError.credentialSave }
      } else if status != errSecSuccess {
        throw CodexUsageError.credentialSave
      }
    }
    private var baseQuery: [String: Any] {
      [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service]
    }
  }

  private struct CodexAuthStore: Sendable {
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var files: any CodexUsageFileAccess = LocalCodexUsageFileAccess()
    var keychain: any CodexUsageKeychainAccess = SystemCodexUsageKeychainAccess()

    func candidates() -> [CodexLoginState] {
      let fileStates = paths().compactMap { path -> CodexLoginState? in
        guard files.exists(path), let text = try? files.read(path), let login = Self.decode(text),
          Self.hasAuth(login)
        else { return nil }
        return CodexLoginState(login: login, source: .file(path))
      }
      var states = fileStates
      if let text = try? keychain.read(), let login = Self.decode(text), Self.hasAuth(login) {
        states.append(CodexLoginState(login: login, source: .keychain))
      }
      return states
    }

    func reload(_ state: CodexLoginState) -> CodexLoginState? {
      let text: String?
      switch state.source {
      case .file(let path): text = try? files.read(path)
      case .keychain: text = try? keychain.read()
      }
      guard let text, let login = Self.decode(text) else { return nil }
      return CodexLoginState(login: login, source: state.source)
    }

    func save(_ state: CodexLoginState, ifUnchanged expected: CodexLoginState) throws -> Bool {
      guard reload(state) == expected else { return false }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let text = String(decoding: try encoder.encode(state.login), as: UTF8.self)
      switch state.source {
      case .file(let path): try files.write(path, text: text)
      case .keychain: try keychain.write(text)
      }
      return true
    }

    static func decode(_ text: String) -> CodexLogin? {
      if let value = try? JSONDecoder().decode(CodexLogin.self, from: Data(text.utf8)) {
        return value
      }
      var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex.removeFirst(2) }
      guard hex.count.isMultiple(of: 2), !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else {
        return nil
      }
      var bytes: [UInt8] = []
      var index = hex.startIndex
      while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
        bytes.append(byte)
        index = next
      }
      return try? JSONDecoder().decode(CodexLogin.self, from: Data(bytes))
    }

    private func paths() -> [String] {
      if let home = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !home.isEmpty
      {
        return [
          "\(home.replacingOccurrences(of: "/+$", with: "", options: .regularExpression))/auth.json"
        ]
      }
      return ["~/.config/codex/auth.json", "~/.codex/auth.json"]
    }
    private static func hasAuth(_ login: CodexLogin) -> Bool {
      !(login.tokens?.accessToken?.isEmpty ?? true) || !(login.apiKey?.isEmpty ?? true)
    }
  }

  private enum CodexUsageError: Error, LocalizedError, Sendable {
    case missingLogin, apiKeyOnly, expired
    case rateLimited(Date?)
    case network, invalidLogin
    case invalidResponse, credentialSave, keychainUnavailable, invalidHistory
    var errorDescription: String? {
      switch self {
      case .missingLogin: "Codex is not signed in on this Mac. Sign in with the Codex app or CLI."
      case .apiKeyOnly: "Codex usage is unavailable for API-key-only login."
      case .expired: "Codex login expired. Sign in again with the Codex app or CLI."
      case .rateLimited(let date):
        if let date {
          "Codex usage is rate limited. Try again \(date.formatted(date: .omitted, time: .shortened))."
        } else {
          "Codex usage is rate limited. Try again later."
        }
      case .network: "Codex usage could not be reached. Check the network and retry."
      case .invalidLogin: "The local Codex login could not be read."
      case .invalidResponse: "Codex returned unreadable usage data."
      case .credentialSave:
        "Codex refreshed its login, but the updated credentials could not be saved."
      case .keychainUnavailable: "StageChase could not read the local Codex Keychain item."
      case .invalidHistory:
        "Local Codex refill history could not be saved or read safely; the estimate is unavailable."
      }
    }
  }

  struct CodexHTTPResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data
    func header(_ name: String) -> String? {
      headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
  }

  private protocol CodexUsageTransport: Sendable {
    func send(_ request: URLRequest) async throws -> CodexHTTPResponse
  }

  actor URLSessionCodexUsageTransport: CodexUsageTransport {
    private let session: URLSession
    init() {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.urlCache = nil
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      configuration.timeoutIntervalForRequest = 20
      configuration.timeoutIntervalForResource = 30
      session = URLSession(configuration: configuration)
    }
    func send(_ request: URLRequest) async throws -> CodexHTTPResponse {
      let (data, response) = try await session.data(for: request)
      guard let response = response as? HTTPURLResponse else { throw CodexUsageError.network }
      var headers: [String: String] = [:]
      for (name, value) in response.allHeaderFields {
        if let name = name as? String { headers[name] = String(describing: value) }
      }
      return CodexHTTPResponse(status: response.statusCode, headers: headers, body: data)
    }
  }

  private actor CodexUsageProvider {
    static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let auth: CodexAuthStore
    private let transport: any CodexUsageTransport
    init(
      auth: CodexAuthStore = CodexAuthStore(),
      transport: any CodexUsageTransport = URLSessionCodexUsageTransport()
    ) {
      self.auth = auth
      self.transport = transport
    }

    func fetch() async throws -> CodexUsageSnapshot {
      let candidates = auth.candidates()
      guard !candidates.isEmpty else {
        if auth.apiKeyOnlyLoginExists { throw CodexUsageError.apiKeyOnly }
        throw CodexUsageError.missingLogin
      }
      var lastFailure: Error = CodexUsageError.missingLogin
      for initial in candidates {
        do { return try await probe(initial) } catch let error as CodexUsageError {
          lastFailure = error
          if case .apiKeyOnly = error { throw error }
          if case .expired = error { continue }
          throw error
        }
      }
      throw lastFailure
    }

    private func probe(_ initial: CodexLoginState) async throws -> CodexUsageSnapshot {
      var state = initial
      guard var access = nonEmpty(state.login.tokens?.accessToken) else {
        if nonEmpty(state.login.apiKey) != nil { throw CodexUsageError.apiKeyOnly }
        throw CodexUsageError.missingLogin
      }
      if needsRefresh(state.login), let live = auth.reload(state),
        let token = nonEmpty(live.login.tokens?.accessToken)
      {
        state = live
        access = token
      }
      if needsRefresh(state.login), let refresh = nonEmpty(state.login.tokens?.refreshToken) {
        access = try await refreshToken(refresh, state: &state)
      }
      var response = try await usage(access, state: state)
      if response.status == 401 || response.status == 403 {
        guard let refresh = nonEmpty(state.login.tokens?.refreshToken) else {
          throw CodexUsageError.expired
        }
        access = try await refreshToken(refresh, state: &state)
        response = try await usage(access, state: state)
        if response.status == 401 || response.status == 403 { throw CodexUsageError.expired }
      }
      if response.status == 429 { throw CodexUsageError.rateLimited(retryDate(response)) }
      guard (200..<300).contains(response.status) else {
        if response.status >= 500 { throw CodexUsageError.network }
        throw CodexUsageError.invalidResponse
      }
      do {
        return try CodexUsageMapper.map(body: response.body, headers: response.headers, now: .now)
      } catch { throw CodexUsageError.invalidResponse }
    }

    private func usage(_ token: String, state: CodexLoginState) async throws -> CodexHTTPResponse {
      var request = URLRequest(url: Self.usageURL)
      request.httpMethod = "GET"
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("StageChase/1.0", forHTTPHeaderField: "User-Agent")
      if let account = state.login.tokens?.accountID, !account.isEmpty {
        request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
      }
      do { return try await transport.send(request) } catch { throw CodexUsageError.network }
    }

    private func refreshToken(_ refresh: String, state: inout CodexLoginState) async throws
      -> String
    {
      let expected = state
      var request = URLRequest(url: Self.refreshURL)
      request.httpMethod = "POST"
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      request.httpBody =
        "grant_type=refresh_token&client_id=\(Self.clientID)&refresh_token=\(formEncode(refresh))"
        .data(using: .utf8)
      let response: CodexHTTPResponse
      do { response = try await transport.send(request) } catch { throw CodexUsageError.network }
      guard (200..<300).contains(response.status),
        let body = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
        let access = body["access_token"] as? String, !access.isEmpty
      else {
        throw response.status == 400 || response.status == 401
          ? CodexUsageError.expired : CodexUsageError.invalidResponse
      }
      state.login.tokens?.accessToken = access
      if let value = body["refresh_token"] as? String { state.login.tokens?.refreshToken = value }
      if let value = body["id_token"] as? String { state.login.tokens?.idToken = value }
      state.login.lastRefresh = ISO8601DateFormatter().string(from: .now)
      do {
        guard try auth.save(state, ifUnchanged: expected) else {
          throw CodexUsageError.credentialSave
        }
      } catch { throw CodexUsageError.credentialSave }
      return access
    }

    private func needsRefresh(_ login: CodexLogin) -> Bool {
      if let token = login.tokens?.accessToken, let expiration = jwtExpiration(token) {
        return expiration.timeIntervalSinceNow <= 5 * 60
      }
      if let raw = login.lastRefresh, let date = ISO8601DateFormatter().date(from: raw) {
        return Date.now.timeIntervalSince(date) > 8 * 24 * 60 * 60
      }
      return false
    }
    private func jwtExpiration(_ token: String) -> Date? {
      let parts = token.split(separator: ".")
      guard parts.count > 1 else { return nil }
      var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
        of: "_", with: "/")
      payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
      guard let data = Data(base64Encoded: payload),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let seconds = object["exp"] as? Double
      else { return nil }
      return Date(timeIntervalSince1970: seconds)
    }
    private func retryDate(_ response: CodexHTTPResponse) -> Date? {
      guard let value = response.header("Retry-After") else { return nil }
      if let seconds = Double(value) { return Date.now.addingTimeInterval(max(seconds, 0)) }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
      return formatter.date(from: value)
    }
    private func formEncode(_ value: String) -> String {
      value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
    private func nonEmpty(_ value: String?) -> String? {
      guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
      else { return nil }
      return value
    }
  }

  extension CodexAuthStore {
    fileprivate var apiKeyOnlyLoginExists: Bool {
      candidatesForAPIKey().contains { $0 }
    }
    fileprivate func candidatesForAPIKey() -> [Bool] {
      let paths: [String]
      if let home = environment["CODEX_HOME"], !home.isEmpty {
        paths = ["\(home)/auth.json"]
      } else {
        paths = ["~/.config/codex/auth.json", "~/.codex/auth.json"]
      }
      return paths.compactMap { path in
        guard let text = try? files.read(path), let login = Self.decode(text) else { return nil }
        return login.tokens?.accessToken?.isEmpty != false && login.apiKey?.isEmpty == false
      }
    }
  }

  @MainActor @Observable final class CodexUsageService {
    private(set) var snapshot: CodexUsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var status = "Usage has not been checked yet."
    private(set) var isStale = false
    private(set) var refreshedAt: Date?
    @ObservationIgnored private let provider = CodexUsageProvider()
    @ObservationIgnored private let historyFiles: any CodexUsageFileAccess =
      LocalCodexUsageFileAccess()
    @ObservationIgnored private var weeklyHistory: CodexWeeklyUsageHistory?
    @ObservationIgnored private var weeklyHistoryLoaded = false
    @ObservationIgnored private var historyUnavailable = false
    var onSnapshot: ((CodexUsageSnapshot) -> Void)?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var pollingID: UUID?

    func start() {
      guard pollingTask == nil else { return }
      let identifier = UUID()
      pollingID = identifier
      pollingTask = Task { [weak self] in
        guard let self else { return }
        defer {
          if pollingID == identifier {
            pollingID = nil
            pollingTask = nil
          }
        }
        await refresh()
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(300)) } catch { break }
          if !Task.isCancelled { await refresh() }
        }
      }
    }
    func stop() {
      pollingID = nil
      pollingTask?.cancel()
      pollingTask = nil
    }
    func refresh() async {
      guard !isRefreshing else { return }
      isRefreshing = true
      defer { isRefreshing = false }
      do {
        var value = try await provider.fetch()
        addLocalHistory(to: &value)
        snapshot = value
        onSnapshot?(value)
        refreshedAt = snapshot?.fetchedAt
        let refreshed =
          "Updated \((refreshedAt ?? .now).formatted(date: .omitted, time: .shortened))"
        status = historyUnavailable ? "\(refreshed) · local history unavailable" : refreshed
        isStale = false
      } catch let error as LocalizedError {
        status = error.errorDescription ?? "Codex usage could not be updated."
        isStale = snapshot != nil
      } catch {
        status = "Codex usage could not be updated."
        isStale = snapshot != nil
      }
    }

    private func addLocalHistory(to snapshot: inout CodexUsageSnapshot) {
      do {
        var history = try loadWeeklyHistory()
        guard let weekly = snapshot.windows.first(where: { $0.kind == .weekly }) else { return }
        history.record(
          CodexWeeklyUsageSample(
            observedAt: snapshot.fetchedAt, remainingPercent: weekly.remainingPercent,
            scheduledResetAt: weekly.resetsAt))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(history)
        guard let text = String(data: data, encoding: .utf8) else {
          throw CodexUsageError.invalidHistory
        }
        try historyFiles.write(Self.weeklyHistoryPath, text: text)
        weeklyHistory = history
        historyUnavailable = false
        snapshot.recentWeeklyRefills = history.latestRefills
        snapshot.recentScheduledWeeklyResets = history.latestScheduledResets
        snapshot.nextUnscheduledWeeklyRefill = history.nextUnscheduledRefillEstimate(
          now: snapshot.fetchedAt)
      } catch {
        historyUnavailable = true
        snapshot.recentWeeklyRefills = nil
        snapshot.recentScheduledWeeklyResets = nil
        snapshot.nextUnscheduledWeeklyRefill = nil
      }
    }

    private func loadWeeklyHistory() throws -> CodexWeeklyUsageHistory {
      if let weeklyHistory { return weeklyHistory }
      if !weeklyHistoryLoaded {
        weeklyHistoryLoaded = true
        if historyFiles.exists(Self.weeklyHistoryPath) {
          guard let text = try? historyFiles.read(Self.weeklyHistoryPath),
            let data = text.data(using: .utf8),
            let history = try? JSONDecoder().decode(CodexWeeklyUsageHistory.self, from: data),
            history.version == CodexWeeklyUsageHistory.currentVersion
          else {
            weeklyHistoryLoaded = false
            throw CodexUsageError.invalidHistory
          }
          weeklyHistory = history
        } else {
          weeklyHistory = CodexWeeklyUsageHistory()
        }
      }
      guard let weeklyHistory else { throw CodexUsageError.invalidHistory }
      return weeklyHistory
    }

    private static var weeklyHistoryPath: String {
      let support = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
      return support.appendingPathComponent("StageChase", isDirectory: true)
        .appendingPathComponent("codex-weekly-usage-history-v1.json").path
    }
  }
#endif
