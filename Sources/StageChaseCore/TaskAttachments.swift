import CryptoKit
import Foundation
import ImageIO

public enum TaskAttachmentTransferState: String, Codable, Hashable, Sendable {
  case pendingUpload
  case available
}

/// Metadata stored with a task. Image bytes remain in TaskAttachmentFiles.
public struct TaskAttachment: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID
  public var displayName: String
  public var mediaType: String
  public var byteCount: Int
  public var sha256: String
  public var transferState: TaskAttachmentTransferState
  public var createdAt: Date

  public init(
    id: UUID = UUID(), displayName: String, mediaType: String, byteCount: Int, sha256: String,
    transferState: TaskAttachmentTransferState, createdAt: Date = .now
  ) {
    self.id = id
    self.displayName = String(displayName.prefix(180))
    self.mediaType = mediaType
    self.byteCount = byteCount
    self.sha256 = sha256.lowercased()
    self.transferState = transferState
    self.createdAt = createdAt
  }
}

/// Separate, atomically written image files. Only IDs and metadata belong in task/sync JSON.
public enum TaskAttachmentFiles {
  public static let maximumBytes = 4 * 1_024 * 1_024
  public static let maximumCount = 12
  public static let maximumDimension = 8_192
  public static let allowedTypes: Set<String> = ["image/jpeg", "image/png", "image/heic"]

  public static func rootURL(
    fileManager: FileManager = .default, baseURL: URL? = nil
  ) throws -> URL {
    let base =
      try baseURL
      ?? fileManager.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("StageChase", isDirectory: true)
    let root = base.appendingPathComponent("TaskAttachments-v1", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  public static func fileURL(for id: UUID, baseURL: URL? = nil) throws -> URL {
    try rootURL(baseURL: baseURL).appendingPathComponent(id.uuidString.lowercased())
      .appendingPathExtension("image")
  }

  @discardableResult
  public static func save(
    _ data: Data, id: UUID, displayName: String, mediaType: String,
    baseURL: URL? = nil
  ) throws -> TaskAttachment {
    try validate(data, mediaType: mediaType)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let url = try fileURL(for: id, baseURL: baseURL)
    try data.write(to: url, options: .atomic)
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: url.path)
    #endif
    return TaskAttachment(
      id: id, displayName: displayName, mediaType: mediaType, byteCount: data.count,
      sha256: digest, transferState: .available)
  }

  public static func validate(_ data: Data, mediaType: String) throws {
    guard allowedTypes.contains(mediaType), data.count > 0, data.count <= maximumBytes,
      hasImageSignature(data, mediaType: mediaType),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) == 1,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= maximumDimension, height <= maximumDimension,
      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    else { throw BoardError.invalid("Choose a valid JPEG, PNG, or HEIC image under 4 MB.") }
  }

  public static func validate(_ data: Data, matches attachment: TaskAttachment) throws {
    try validate(data, mediaType: attachment.mediaType)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard data.count == attachment.byteCount, digest == attachment.sha256 else {
      throw BoardError.invalid("A backup image does not match its recorded size or checksum.")
    }
  }

  public static func read(
    _ attachment: TaskAttachment, baseURL: URL? = nil
  ) throws -> Data {
    let data = try Data(
      contentsOf: fileURL(for: attachment.id, baseURL: baseURL), options: .mappedIfSafe)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard data.count == attachment.byteCount, digest == attachment.sha256,
      allowedTypes.contains(attachment.mediaType),
      hasImageSignature(data, mediaType: attachment.mediaType)
    else {
      throw BoardError.invalid("The attached image is incomplete or failed its integrity check.")
    }
    return data
  }

  public static func remove(_ id: UUID, baseURL: URL? = nil) throws {
    let url = try fileURL(for: id, baseURL: baseURL)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private static func hasImageSignature(_ data: Data, mediaType: String) -> Bool {
    switch mediaType {
    case "image/png": data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    case "image/jpeg": data.starts(with: [0xff, 0xd8, 0xff])
    case "image/heic":
      data.count > 12 && data[4..<12].contains { $0 == 0x66 }
        && String(data: data[4..<12], encoding: .ascii)?.contains("ftyp") == true
    default: false
    }
  }
}
