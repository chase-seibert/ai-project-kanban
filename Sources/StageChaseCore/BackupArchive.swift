import Foundation

/// Versioned backup container: library JSON followed by separately framed raw asset files.
/// JSON-only library backups remain readable by decode(_:).
public enum BackupArchive {
  private static let magic = Data("STCHBACKUP\0".utf8)
  private static let version: UInt32 = 1
  public static let maximumArchiveBytes = 128 * 1_024 * 1_024

  public struct Contents: Sendable {
    public var library: Library
    public var assets: [UUID: Data]
  }

  public static func encode(_ library: Library, baseURL: URL? = nil) throws -> Data {
    try library.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let metadata = try encoder.encode(library)
    let attachments = library.tasks.flatMap(\.attachments)
    guard Set(attachments.map(\.id)).count == attachments.count else {
      throw BoardError.invalid("The backup contains duplicate image IDs.")
    }
    var files: [(UUID, Data)] = []
    for attachment in attachments {
      let bytes = try TaskAttachmentFiles.read(attachment, baseURL: baseURL)
      guard bytes.count <= maximumArchiveBytes - outputSize(metadata: metadata, files: files) else {
        throw BoardError.invalid("The backup is larger than the 128 MB archive limit.")
      }
      files.append((attachment.id, bytes))
    }
    var output = magic
    append(version, to: &output)
    append(UInt64(metadata.count), to: &output)
    output.append(metadata)
    append(UInt32(files.count), to: &output)
    for (id, bytes) in files {
      output.append(contentsOf: id.uuidString.lowercased().utf8)
      append(UInt64(bytes.count), to: &output)
      output.append(bytes)
    }
    guard output.count <= maximumArchiveBytes else {
      throw BoardError.invalid("The backup is larger than the 128 MB archive limit.")
    }
    return output
  }

  public static func decode(_ data: Data) throws -> Contents {
    guard data.count <= maximumArchiveBytes else {
      throw BoardError.invalid("The backup is larger than the 128 MB archive limit.")
    }
    guard data.starts(with: magic) else {
      let library = try JSONDecoder().decode(Library.self, from: data)
      guard library.tasks.allSatisfy({ $0.attachments.isEmpty }) else {
        throw BoardError.invalid("This JSON backup references images that are not included.")
      }
      return Contents(library: library, assets: [:])
    }
    var cursor = magic.count
    let archiveVersion: UInt32 = try read(UInt32.self, data: data, cursor: &cursor)
    guard archiveVersion == version else {
      throw BoardError.invalid("This StageChase backup version is not supported.")
    }
    let metadataLength: UInt64 = try read(UInt64.self, data: data, cursor: &cursor)
    guard metadataLength > 0, metadataLength <= UInt64(data.count - cursor) else {
      throw BoardError.invalid("The backup metadata is incomplete.")
    }
    let metadata = data.subdata(in: cursor..<(cursor + Int(metadataLength)))
    cursor += Int(metadataLength)
    let library = try JSONDecoder().decode(Library.self, from: metadata)
    try library.validate()
    let count: UInt32 = try read(UInt32.self, data: data, cursor: &cursor)
    guard count <= UInt32(library.tasks.reduce(0) { $0 + $1.attachments.count }) else {
      throw BoardError.invalid("The backup contains unassociated image files.")
    }
    var assets: [UUID: Data] = [:]
    for _ in 0..<count {
      guard cursor + 36 <= data.count,
        let id = UUID(uuidString: String(decoding: data[cursor..<(cursor + 36)], as: UTF8.self))
      else { throw BoardError.invalid("The backup contains an invalid image ID.") }
      cursor += 36
      let length: UInt64 = try read(UInt64.self, data: data, cursor: &cursor)
      guard length > 0, length <= UInt64(TaskAttachmentFiles.maximumBytes),
        length <= UInt64(data.count - cursor), assets[id] == nil
      else { throw BoardError.invalid("The backup image is invalid or incomplete.") }
      assets[id] = data.subdata(in: cursor..<(cursor + Int(length)))
      cursor += Int(length)
    }
    guard cursor == data.count else { throw BoardError.invalid("The backup has trailing data.") }
    let attachments = library.tasks.flatMap(\.attachments)
    guard Set(assets.keys) == Set(attachments.map(\.id)) else {
      throw BoardError.invalid("The backup image files do not match their task metadata.")
    }
    for attachment in attachments {
      let bytes = assets[attachment.id]!
      try TaskAttachmentFiles.validate(bytes, matches: attachment)
    }
    return Contents(library: library, assets: assets)
  }

  private static func outputSize(metadata: Data, files: [(UUID, Data)]) -> Int {
    magic.count + 4 + 8 + metadata.count + 4
      + files.reduce(0) { $0 + 36 + 8 + $1.1.count }
  }

  private static func append(_ value: UInt32, to data: inout Data) {
    var value = value.bigEndian
    data.append(Data(bytes: &value, count: MemoryLayout<UInt32>.size))
  }

  private static func append(_ value: UInt64, to data: inout Data) {
    var value = value.bigEndian
    data.append(Data(bytes: &value, count: MemoryLayout<UInt64>.size))
  }

  private static func read<T: FixedWidthInteger>(
    _ type: T.Type, data: Data, cursor: inout Int
  ) throws -> T {
    let size = MemoryLayout<T>.size
    guard cursor + size <= data.count else { throw BoardError.invalid("The backup is incomplete.") }
    let value = data[cursor..<(cursor + size)].reduce(T(0)) { ($0 << 8) | T($1) }
    cursor += size
    return value
  }
}
