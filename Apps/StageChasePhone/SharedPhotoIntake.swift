import Foundation
import ImageIO

struct SharedPhotoProject: Codable, Identifiable, Hashable {
  let id: UUID
  let name: String
}

struct SharedPhotoRequest: Codable, Identifiable {
  let id: UUID
  let projectID: UUID
  let title: String
  let description: String
  let displayName: String
  let mediaType: String
}

enum SharedPhotoIntake {
  static let appGroup = "group.com.cseibert.StageChase"
  static let projectsKey = "sharedPhotoProjects"

  static func rootURL(fileManager: FileManager = .default) throws -> URL {
    guard let container = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: appGroup)
    else { throw intakeError("Shared photo intake is unavailable on this device.") }
    let root = container.appendingPathComponent("SharedPhotoIntake-v1", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  static func stage(
    image: Data, projectID: UUID, title: String, description: String, displayName: String,
    mediaType: String
  ) throws -> SharedPhotoRequest {
    try validate(image, mediaType: mediaType)
    let request = SharedPhotoRequest(
      id: UUID(), projectID: projectID,
      title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)),
      description: String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20_000)),
      displayName: String(displayName.prefix(180)), mediaType: mediaType)
    guard !request.title.isEmpty else { throw intakeError("Give this task a title.") }
    let root = try rootURL()
    let imageURL = imageURL(for: request.id, root: root)
    try image.write(to: imageURL, options: .atomic)
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: imageURL.path)
    #endif
    let manifest = try JSONEncoder().encode(request)
    try manifest.write(to: manifestURL(for: request.id, root: root), options: .atomic)
    return request
  }

  static func validateForShare(image: Data, mediaType: String) throws {
    try validate(image, mediaType: mediaType)
  }

  static func pendingRequests() throws -> [(SharedPhotoRequest, Data)] {
    let root = try rootURL()
    let urls = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
    let requests = try urls.compactMap { url in
      let request = try JSONDecoder().decode(SharedPhotoRequest.self, from: Data(contentsOf: url))
      let image = try Data(contentsOf: imageURL(for: request.id, root: root), options: .mappedIfSafe)
      return (request, image)
    }
    let retainedIDs = Set(urls.map { $0.deletingPathExtension().lastPathComponent })
    for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    where url.pathExtension == "image" && !retainedIDs.contains(url.deletingPathExtension().lastPathComponent) {
      try? FileManager.default.removeItem(at: url)
    }
    return requests
  }

  static func remove(_ requestID: UUID) throws {
    let root = try rootURL()
    for url in [manifestURL(for: requestID, root: root), imageURL(for: requestID, root: root)] {
      if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
  }

  private static func manifestURL(for id: UUID, root: URL) -> URL {
    root.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("json")
  }

  private static func imageURL(for id: UUID, root: URL) -> URL {
    root.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("image")
  }

  private static func validate(_ data: Data, mediaType: String) throws {
    let signatureMatches: Bool
    switch mediaType {
    case "image/jpeg": signatureMatches = data.starts(with: [0xff, 0xd8, 0xff])
    case "image/png": signatureMatches = data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    case "image/heic":
      signatureMatches = data.count > 12
        && String(data: data[4..<12], encoding: .ascii)?.contains("ftyp") == true
    default: signatureMatches = false
    }
    guard TaskAttachmentMediaTypes.allowed.contains(mediaType), data.count > 0,
      data.count <= TaskAttachmentMediaTypes.maximumBytes, signatureMatches,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) == 1,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= TaskAttachmentMediaTypes.maximumDimension,
      height <= TaskAttachmentMediaTypes.maximumDimension,
      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    else { throw intakeError("Choose a readable JPEG, PNG, or HEIC image under 4 MB.") }
  }

  private static func intakeError(_ message: String) -> NSError {
    NSError(domain: "SharedPhotoIntake", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

private enum TaskAttachmentMediaTypes {
  static let allowed: Set<String> = ["image/jpeg", "image/png", "image/heic"]
  static let maximumBytes = 4 * 1_024 * 1_024
  static let maximumDimension = 8_192
}
