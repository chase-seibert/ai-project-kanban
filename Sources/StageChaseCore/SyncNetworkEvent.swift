import Foundation

/// Metadata for one framed synchronization exchange. Never contains message payloads or keys.
public struct SyncNetworkEvent: Codable, Identifiable, Sendable {
  public var id: UUID
  public var date: Date
  public var direction: String
  public var remoteAddress: String?
  public var operation: String
  public var requestBytes: Int
  public var responseBytes: Int?
  public var outcome: String
  public var detail: String
  public var elapsedMilliseconds: Int?

  public init(
    date: Date = .now, direction: String, remoteAddress: String? = nil, operation: String,
    requestBytes: Int,
    responseBytes: Int?, outcome: String, detail: String, elapsedMilliseconds: Int?
  ) {
    id = UUID()
    self.date = date
    self.direction = direction
    self.remoteAddress = remoteAddress
    self.operation = operation
    self.requestBytes = requestBytes
    self.responseBytes = responseBytes
    self.outcome = outcome
    self.detail = detail
    self.elapsedMilliseconds = elapsedMilliseconds
  }
}

public enum SyncNetworkEventJournal {
  public static let maximumEvents = 200

  public static func load(from url: URL) throws -> [SyncNetworkEvent] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    return Array(
      try JSONDecoder.syncDecoder.decode([SyncNetworkEvent].self, from: data).prefix(maximumEvents))
  }

  @discardableResult
  public static func append(
    _ event: SyncNetworkEvent, to events: [SyncNetworkEvent], at url: URL,
    protectForPhone: Bool = false
  ) throws -> [SyncNetworkEvent] {
    let updated = Array(([event] + events).prefix(maximumEvents))
    try save(updated, at: url, protectForPhone: protectForPhone)
    return updated
  }

  public static func save(
    _ events: [SyncNetworkEvent], at url: URL, protectForPhone: Bool = false
  ) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder.syncEncoder.encode(Array(events.prefix(maximumEvents)))
      .write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    #if os(iOS)
      if protectForPhone {
        try FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
          ofItemAtPath: url.path)
      }
    #endif
  }
}
