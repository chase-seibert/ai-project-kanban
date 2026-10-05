import CoreFoundation
import Foundation

public enum CodexQuotaKind: String, Codable, Equatable, Sendable {
  case session
  case weekly
  case sparkSession
  case sparkWeekly
}

public struct CodexQuotaWindow: Codable, Equatable, Sendable, Identifiable {
  public var kind: CodexQuotaKind
  public var usedPercent: Double
  public var resetsAt: Date?
  public var id: CodexQuotaKind { kind }
  public var remainingPercent: Double { 100 - min(max(usedPercent, 0), 100) }

  public init(kind: CodexQuotaKind, usedPercent: Double, resetsAt: Date?) {
    self.kind = kind
    self.usedPercent = usedPercent
    self.resetsAt = resetsAt
  }
}

public enum CodexQuotaStatus: String, Equatable, Sendable {
  public static let redUpperBoundRemainingPercent = 30.000_001
  public static let greenLowerBoundRemainingPercent = 64.999_999

  case red
  case yellow
  case green

  public var emoji: String {
    switch self {
    case .red: "🔴"
    case .yellow: "🟡"
    case .green: "🟢"
    }
  }

  public static func fromRemainingPercent(
    _ percent: Double,
    expectedRemainingPercent: Double? = nil
  ) -> Self {
    let boundaries = remainingPercentBoundaries(
      expectedRemainingPercent: expectedRemainingPercent)
    if percent <= boundaries.redUpperBound { return .red }
    if percent >= boundaries.greenLowerBound { return .green }
    return .yellow
  }

  public static func remainingPercentBoundaries(
    expectedRemainingPercent: Double?
  ) -> (redUpperBound: Double, greenLowerBound: Double) {
    let paceScale: Double
    if let expectedRemainingPercent, expectedRemainingPercent > 0 {
      paceScale = expectedRemainingPercent / 100
    } else {
      paceScale = 1
    }
    return (
      redUpperBoundRemainingPercent * paceScale,
      greenLowerBoundRemainingPercent * paceScale
    )
  }
}

public struct CodexQuotaBarPresentation: Equatable, Sendable {
  public var remainingFraction: Double
  public var paceMarkerFraction: Double?
  public var redBoundaryFraction: Double
  public var greenBoundaryFraction: Double

  public init(window: CodexQuotaWindow, now: Date) {
    let expectedRemainingPercent: Double?
    if window.kind == .weekly || window.kind == .sparkWeekly,
      let resetAt = window.resetsAt
    {
      expectedRemainingPercent =
        CodexWeeklyPacing(resetAt: resetAt, now: now)
        .expectedRemainingPercent
    } else {
      expectedRemainingPercent = nil
    }

    remainingFraction = min(max(window.remainingPercent / 100, 0), 1)
    paceMarkerFraction = expectedRemainingPercent.map {
      min(max($0 / 100, 0), 1)
    }
    let boundaries = CodexQuotaStatus.remainingPercentBoundaries(
      expectedRemainingPercent: expectedRemainingPercent)
    redBoundaryFraction = min(max(boundaries.redUpperBound / 100, 0), 1)
    greenBoundaryFraction = min(max(boundaries.greenLowerBound / 100, 0), 1)
  }
}

public struct CodexUsageSnapshot: Codable, Equatable, Sendable {
  public var planName: String?
  public var windows: [CodexQuotaWindow]
  public var remainingCredits: Int?
  public var fetchedAt: Date
  public var flexCreditUSDValue: Double? {
    remainingCredits.map { Double($0) * CodexUsageMapper.creditUSDRate }
  }

  public init(
    planName: String?, windows: [CodexQuotaWindow], remainingCredits: Int?, fetchedAt: Date
  ) {
    self.planName = planName
    self.windows = windows
    self.remainingCredits = remainingCredits
    self.fetchedAt = fetchedAt
  }
}

struct CodexWeeklyPacing: Equatable, Sendable {
  static let windowDuration: TimeInterval = 7 * 24 * 60 * 60
  var expectedUsedPercent: Double
  var expectedRemainingPercent: Double { 100 - expectedUsedPercent }
  var text: String {
    "On pace, you would have \(Int(expectedRemainingPercent.rounded()))% left by now"
  }

  init(resetAt: Date, now: Date) {
    let start = resetAt.addingTimeInterval(-Self.windowDuration)
    let elapsed = now.timeIntervalSince(start)
    expectedUsedPercent = min(max(elapsed / Self.windowDuration, 0), 1) * 100
  }
}

enum CodexUsageMappingError: Error, Equatable {
  case invalidResponse
}

enum CodexUsageMapper {
  static let creditUSDRate = 0.04

  private enum WindowKind { case session, weekly }
  private struct Candidate {
    var object: [String: Any]
    var usedPercent: Double?
    var fallback: WindowKind
  }

  static func map(body data: Data, headers: [String: String] = [:], now: Date) throws
    -> CodexUsageSnapshot
  {
    guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let limits = body["rate_limit"] as? [String: Any]
    else { throw CodexUsageMappingError.invalidResponse }

    let normalizedHeaders = Dictionary(
      headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    var windows = classify(
      limits,
      output: (.session, .weekly),
      headerPercent: (
        number(normalizedHeaders["x-codex-primary-used-percent"]),
        number(normalizedHeaders["x-codex-secondary-used-percent"])
      ),
      now: now
    )
    if let entries = body["additional_rate_limits"] as? [[String: Any]],
      let spark = entries.first(where: isSpark),
      let limits = spark["rate_limit"] as? [String: Any]
    {
      windows += classify(
        limits, output: (.sparkSession, .sparkWeekly), headerPercent: (nil, nil), now: now)
    }
    guard !windows.isEmpty else { throw CodexUsageMappingError.invalidResponse }

    let remainingCredits: Int?
    if let credits = body["credits"] as? [String: Any], let balance = number(credits["balance"]) {
      remainingCredits = clampedWholeCredits(balance)
    } else if (body["credits"] as? [String: Any])?["has_credits"] as? Bool == false {
      remainingCredits = 0
    } else {
      remainingCredits = number(normalizedHeaders["x-codex-credits-balance"]).map(
        clampedWholeCredits)
    }
    return CodexUsageSnapshot(
      planName: planName(body["plan_type"]), windows: windows,
      remainingCredits: remainingCredits, fetchedAt: now)
  }

  static func planName(_ value: Any?) -> String? {
    guard let raw = value as? String else { return nil }
    let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }
    switch cleaned.lowercased() {
    case "prolite": return "Pro 5x"
    case "pro": return "Pro 20x"
    default:
      return cleaned.replacingOccurrences(of: "_", with: " ").split(separator: " ")
        .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }
  }

  private static func classify(
    _ limits: [String: Any], output: (CodexQuotaKind, CodexQuotaKind),
    headerPercent: (Double?, Double?), now: Date
  ) -> [CodexQuotaWindow] {
    let candidates = [
      candidate(limits["primary_window"], header: headerPercent.0, fallback: .session),
      candidate(limits["secondary_window"], header: headerPercent.1, fallback: .weekly),
    ].compactMap { $0 }
    var result: [CodexQuotaWindow] = []
    for (kind, outputKind) in [(WindowKind.session, output.0), (.weekly, output.1)] {
      let candidate =
        candidates.first { exactKind($0.object) == kind }
        ?? candidates.first { exactKind($0.object) == nil && $0.fallback == kind }
      guard let candidate, let used = candidate.usedPercent else { continue }
      result.append(
        CodexQuotaWindow(
          kind: outputKind, usedPercent: used,
          resetsAt: resetDate(candidate.object, now: now)))
    }
    return result
  }

  private static func candidate(_ raw: Any?, header: Double?, fallback: WindowKind) -> Candidate? {
    let object = raw as? [String: Any] ?? (header == nil ? nil : [:])
    guard let object else { return nil }
    return Candidate(
      object: object, usedPercent: number(object["used_percent"]) ?? header, fallback: fallback)
  }

  private static func exactKind(_ window: [String: Any]) -> WindowKind? {
    guard let seconds = number(window["limit_window_seconds"]) else { return nil }
    switch Int(seconds.rounded()) {
    case 18_000: return WindowKind.session
    case 604_800: return WindowKind.weekly
    default: return nil
    }
  }

  private static func resetDate(_ window: [String: Any], now: Date) -> Date? {
    if let value = number(window["reset_at"]) { return Date(timeIntervalSince1970: value) }
    if let value = number(window["reset_after_seconds"]) { return now.addingTimeInterval(value) }
    return nil
  }

  private static func isSpark(_ entry: [String: Any]) -> Bool {
    [entry["limit_name"], entry["metered_feature"]].compactMap { $0 as? String }
      .contains { $0.localizedCaseInsensitiveContains("spark") }
  }

  private static func number(_ value: Any?) -> Double? {
    if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      number.doubleValue.isFinite
    {
      return number.doubleValue
    }
    if let string = value as? String, let parsed = Double(string), parsed.isFinite { return parsed }
    return nil
  }

  private static func clampedWholeCredits(_ value: Double) -> Int {
    let whole = value.rounded(.down)
    return whole <= 0 ? 0 : whole >= Double(Int.max) ? Int.max : Int(whole)
  }
}
