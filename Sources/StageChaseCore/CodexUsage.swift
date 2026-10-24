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

public struct CodexWeeklyUsageSample: Codable, Equatable, Sendable {
  public var observedAt: Date
  public var remainingPercent: Double
  public var scheduledResetAt: Date?

  public init(observedAt: Date, remainingPercent: Double, scheduledResetAt: Date?) {
    self.observedAt = observedAt
    self.remainingPercent = min(max(remainingPercent, 0), 100)
    self.scheduledResetAt = scheduledResetAt
  }
}

public enum CodexWeeklyRefillClassification: String, Codable, Equatable, Sendable {
  case scheduled
  case unscheduled
  case ambiguous
}

public enum CodexWeeklyScheduledResetState: String, Codable, Equatable, Sendable {
  case upcoming
  case observed
  case notObserved
  case ambiguous
}

public struct CodexWeeklyScheduledReset: Codable, Equatable, Sendable, Identifiable {
  public var expectedAt: Date
  public var state: CodexWeeklyScheduledResetState
  public var id: Date { expectedAt }

  public init(expectedAt: Date, state: CodexWeeklyScheduledResetState) {
    self.expectedAt = expectedAt
    self.state = state
  }
}

public struct CodexWeeklyRefillEvent: Codable, Equatable, Sendable, Identifiable {
  public var observedAfter: Date
  public var observedBy: Date
  public var previousRemainingPercent: Double
  public var newRemainingPercent: Double
  public var scheduledResetAt: Date?
  public var classification: CodexWeeklyRefillClassification
  public var id: Date { observedBy }

  public init(
    observedAfter: Date, observedBy: Date, previousRemainingPercent: Double,
    newRemainingPercent: Double, scheduledResetAt: Date?,
    classification: CodexWeeklyRefillClassification
  ) {
    self.observedAfter = observedAfter
    self.observedBy = observedBy
    self.previousRemainingPercent = previousRemainingPercent
    self.newRemainingPercent = newRemainingPercent
    self.scheduledResetAt = scheduledResetAt
    self.classification = classification
  }
}

public struct CodexWeeklyRefillEstimate: Codable, Equatable, Sendable {
  public var earliest: Date
  public var latest: Date
  public var basedOnEvents: Int

  public init(earliest: Date, latest: Date, basedOnEvents: Int) {
    self.earliest = earliest
    self.latest = latest
    self.basedOnEvents = basedOnEvents
  }
}

public struct CodexWeeklyResetPattern: Codable, Equatable, Sendable {
  public var averageIntervalDays: Double
  public var earlyResetCount: Int
  public var averageDaysEarly: Double?
  public var nextReset: Date

  public init(
    averageIntervalDays: Double, earlyResetCount: Int, averageDaysEarly: Double?, nextReset: Date
  ) {
    self.averageIntervalDays = averageIntervalDays
    self.earlyResetCount = earlyResetCount
    self.averageDaysEarly = averageDaysEarly
    self.nextReset = nextReset
  }
}

/// Mac-local observations. This bounded raw history is never part of a sync payload.
public struct CodexWeeklyUsageHistory: Codable, Equatable, Sendable {
  public static let currentVersion = 1
  public static let retention: TimeInterval = 548 * 24 * 60 * 60
  public static let recentCadence: TimeInterval = 7 * 24 * 60 * 60
  public static let coarseCadence: TimeInterval = 60 * 60
  public static let maximumSamples = 20_000
  public static let materialRefillIncrease = 25.0
  public static let scheduleClassificationWindow: TimeInterval = 2 * 60 * 60

  public var version: Int
  public var samples: [CodexWeeklyUsageSample]
  public var refills: [CodexWeeklyRefillEvent]
  public var scheduledResets: [CodexWeeklyScheduledReset]

  public init(
    version: Int = currentVersion, samples: [CodexWeeklyUsageSample] = [],
    refills: [CodexWeeklyRefillEvent] = [], scheduledResets: [CodexWeeklyScheduledReset] = []
  ) {
    self.version = version
    self.samples = samples
    self.refills = refills
    self.scheduledResets = scheduledResets
  }

  public mutating func record(_ sample: CodexWeeklyUsageSample) {
    guard version == Self.currentVersion else { return }
    var newRefill: CodexWeeklyRefillEvent?
    if let previous = samples.last, sample.observedAt > previous.observedAt {
      if sample.remainingPercent - previous.remainingPercent >= Self.materialRefillIncrease {
        let result = Self.classify(
          after: previous.observedAt, by: sample.observedAt,
          previousSchedule: previous.scheduledResetAt, currentSchedule: sample.scheduledResetAt)
        let refill = CodexWeeklyRefillEvent(
          observedAfter: previous.observedAt, observedBy: sample.observedAt,
          previousRemainingPercent: previous.remainingPercent,
          newRemainingPercent: sample.remainingPercent, scheduledResetAt: result.schedule,
          classification: result.classification)
        newRefill = refill
        refills.append(refill)
      }
      samples.append(sample)
      updateScheduledResets(for: sample, observedRefill: newRefill)
      compact(now: sample.observedAt)
    } else if samples.isEmpty {
      samples.append(sample)
      updateScheduledResets(for: sample, observedRefill: nil)
    }
  }

  public var latestRefills: [CodexWeeklyRefillEvent] { Array(refills.suffix(3).reversed()) }
  public var latestScheduledResets: [CodexWeeklyScheduledReset] {
    Array(scheduledResets.suffix(3).reversed())
  }

  public func nextUnscheduledRefillEstimate(now: Date) -> CodexWeeklyRefillEstimate? {
    let events = refills.filter { $0.classification == .unscheduled }
    guard events.count >= 3, let last = events.last else { return nil }
    let eventWidths = events.map { $0.observedBy.timeIntervalSince($0.observedAfter) }
    guard eventWidths.allSatisfy({ $0 <= 24 * 60 * 60 }) else { return nil }
    let midpoints = events.map {
      $0.observedAfter.addingTimeInterval($0.observedBy.timeIntervalSince($0.observedAfter) / 2)
    }
    let intervals = zip(midpoints, midpoints.dropFirst()).map { $1.timeIntervalSince($0) }
    guard intervals.count >= 2 else { return nil }
    let cadence = Self.median(intervals)
    let shortestCadence: TimeInterval = 3 * 24 * 60 * 60
    let longestCadence: TimeInterval = 60 * 24 * 60 * 60
    guard cadence >= shortestCadence, cadence <= longestCadence else { return nil }
    let deviations = intervals.map { abs($0 - cadence) }
    let medianDeviation = Self.median(deviations)
    guard medianDeviation / cadence <= 0.25 else { return nil }
    guard now.timeIntervalSince(last.observedBy) <= cadence * 1.5 else { return nil }
    let nextMidpoint = midpoints[midpoints.count - 1].addingTimeInterval(cadence)
    let uncertainty = max(12 * 60 * 60, Self.median(eventWidths) / 2 + medianDeviation * 1.5)
    return CodexWeeklyRefillEstimate(
      earliest: nextMidpoint.addingTimeInterval(-uncertainty),
      latest: nextMidpoint.addingTimeInterval(uncertainty), basedOnEvents: events.count)
  }

  public func recentResetPattern(now: Date) -> CodexWeeklyResetPattern? {
    let window: TimeInterval = 60 * 24 * 60 * 60
    let cutoff = now.addingTimeInterval(-window)
    let events = refills.filter {
      $0.observedBy >= cutoff && $0.classification != .scheduled
    }
    guard events.count >= 2 else { return nil }
    let midpoints = events.map {
      $0.observedAfter.addingTimeInterval($0.observedBy.timeIntervalSince($0.observedAfter) / 2)
    }
    let intervals = zip(midpoints, midpoints.dropFirst()).map { $1.timeIntervalSince($0) }
    guard !intervals.isEmpty else { return nil }
    let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
    let earlyByDays = events.compactMap { event -> Double? in
      guard let scheduled = event.scheduledResetAt else { return nil }
      let midpoint = event.observedAfter.addingTimeInterval(
        event.observedBy.timeIntervalSince(event.observedAfter) / 2)
      let daysEarly = scheduled.timeIntervalSince(midpoint) / (24 * 60 * 60)
      return daysEarly >= 1 ? daysEarly : nil
    }
    return CodexWeeklyResetPattern(
      averageIntervalDays: averageInterval / (24 * 60 * 60),
      earlyResetCount: earlyByDays.count,
      averageDaysEarly: earlyByDays.isEmpty
        ? nil : earlyByDays.reduce(0, +) / Double(earlyByDays.count),
      nextReset: midpoints[midpoints.count - 1].addingTimeInterval(averageInterval))
  }

  private mutating func compact(now: Date) {
    let cutoff = now.addingTimeInterval(-Self.retention)
    samples.removeAll { $0.observedAt < cutoff }
    refills.removeAll { $0.observedBy < cutoff }
    scheduledResets.removeAll { $0.expectedAt < cutoff }
    guard samples.count > Self.maximumSamples else { return }

    let refillBoundaries = Set(refills.flatMap { [$0.observedAfter, $0.observedBy] })
    let recentCutoff = now.addingTimeInterval(-Self.recentCadence)
    var latestInHour: [Int: CodexWeeklyUsageSample] = [:]
    var keep: [CodexWeeklyUsageSample] = []
    for sample in samples {
      if sample.observedAt >= recentCutoff || refillBoundaries.contains(sample.observedAt) {
        keep.append(sample)
      } else {
        latestInHour[Int(sample.observedAt.timeIntervalSince1970 / Self.coarseCadence)] = sample
      }
    }
    samples = (keep + latestInHour.values).sorted { $0.observedAt < $1.observedAt }
    if samples.count > Self.maximumSamples {
      let protected = Set(refillBoundaries)
      let removable = samples.filter {
        $0.observedAt < recentCutoff && !protected.contains($0.observedAt)
      }
      let removeCount = min(samples.count - Self.maximumSamples, removable.count)
      let removeDates = Set(removable.prefix(removeCount).map(\.observedAt))
      samples.removeAll { removeDates.contains($0.observedAt) }
    }
  }

  private mutating func updateScheduledResets(
    for sample: CodexWeeklyUsageSample, observedRefill: CodexWeeklyRefillEvent?
  ) {
    if let expectedAt = sample.scheduledResetAt,
      !scheduledResets.contains(where: { $0.expectedAt == expectedAt })
    {
      scheduledResets.append(
        CodexWeeklyScheduledReset(
          expectedAt: expectedAt,
          state: sample.observedAt
            > expectedAt.addingTimeInterval(Self.scheduleClassificationWindow)
            ? .notObserved : .upcoming))
    }
    for index in scheduledResets.indices where scheduledResets[index].state == .upcoming {
      if sample.observedAt
        > scheduledResets[index].expectedAt.addingTimeInterval(
          Self.scheduleClassificationWindow)
      {
        scheduledResets[index].state = .notObserved
      }
    }
    guard let observedRefill, let schedule = observedRefill.scheduledResetAt,
      let index = scheduledResets.firstIndex(where: { $0.expectedAt == schedule })
    else { return }
    switch observedRefill.classification {
    case .scheduled: scheduledResets[index].state = .observed
    case .ambiguous: scheduledResets[index].state = .ambiguous
    case .unscheduled: break
    }
  }

  private static func classify(
    after: Date, by: Date, previousSchedule: Date?, currentSchedule: Date?
  ) -> (classification: CodexWeeklyRefillClassification, schedule: Date?) {
    let schedules = Array(Set([previousSchedule, currentSchedule].compactMap { $0 })).sorted()
    guard by.timeIntervalSince(after) <= 12 * 60 * 60 else { return (.ambiguous, schedules.first) }
    if let scheduled = schedules.first(where: { (after...by).contains($0) }) {
      return (.scheduled, scheduled)
    }
    let lower = after.addingTimeInterval(-scheduleClassificationWindow)
    let upper = by.addingTimeInterval(scheduleClassificationWindow)
    if let scheduled = schedules.first(where: { (lower...upper).contains($0) }) {
      return (.ambiguous, scheduled)
    }
    if previousSchedule != currentSchedule {
      return (.ambiguous, currentSchedule ?? previousSchedule)
    }
    return (.unscheduled, currentSchedule ?? previousSchedule)
  }

  private static func median(_ values: [TimeInterval]) -> TimeInterval {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
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
    if percent >= boundaries.greenLowerBound { return .green }
    if percent <= boundaries.redUpperBound { return .red }
    return .yellow
  }

  public static func remainingPercentBoundaries(
    expectedRemainingPercent: Double?
  ) -> (redUpperBound: Double, greenLowerBound: Double) {
    if let expectedRemainingPercent {
      let pace = min(max(expectedRemainingPercent, 0), 100)
      let greenLowerBound = max(pace - 10, 0)
      // Keep the session's red proportion, measured against the weekly pace.
      // Near reset, cap red at green so the weekly bands cannot cross.
      let redUpperBound = min(redUpperBoundRemainingPercent * pace / 100, greenLowerBound)
      return (redUpperBound, greenLowerBound)
    }
    return (
      redUpperBoundRemainingPercent,
      greenLowerBoundRemainingPercent
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
  public var recentWeeklyRefills: [CodexWeeklyRefillEvent]?
  public var recentScheduledWeeklyResets: [CodexWeeklyScheduledReset]?
  public var nextUnscheduledWeeklyRefill: CodexWeeklyRefillEstimate?
  public var recentWeeklyResetPattern: CodexWeeklyResetPattern?
  public var flexCreditUSDValue: Double? {
    remainingCredits.map { Double($0) * CodexUsageMapper.creditUSDRate }
  }

  public init(
    planName: String?, windows: [CodexQuotaWindow], remainingCredits: Int?, fetchedAt: Date,
    recentWeeklyRefills: [CodexWeeklyRefillEvent]? = nil,
    recentScheduledWeeklyResets: [CodexWeeklyScheduledReset]? = nil,
    nextUnscheduledWeeklyRefill: CodexWeeklyRefillEstimate? = nil,
    recentWeeklyResetPattern: CodexWeeklyResetPattern? = nil
  ) {
    self.planName = planName
    self.windows = windows
    self.remainingCredits = remainingCredits
    self.fetchedAt = fetchedAt
    self.recentWeeklyRefills = recentWeeklyRefills
    self.recentScheduledWeeklyResets = recentScheduledWeeklyResets
    self.nextUnscheduledWeeklyRefill = nextUnscheduledWeeklyRefill
    self.recentWeeklyResetPattern = recentWeeklyResetPattern
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
