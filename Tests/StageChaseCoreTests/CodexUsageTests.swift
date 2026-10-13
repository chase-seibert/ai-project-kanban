import Foundation
import Testing

@testable import StageChaseCore

@Test func codexUsageMapsWindowsResetPlanSparkAndWholeFlexCredits() throws {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let response = Data(
    #"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":25,"limit_window_seconds":18000,"reset_at":1800001000},"secondary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_at":1800604800}},"additional_rate_limits":[{"limit_name":"spark","rate_limit":{"primary_window":{"used_percent":12},"secondary_window":{"used_percent":30}}}],"credits":{"balance":3.9}}"#
      .utf8
  )

  let snapshot = try CodexUsageMapper.map(body: response, now: now)

  #expect(snapshot.planName == "Pro 20x")
  #expect(snapshot.windows.map(\.kind) == [.session, .weekly, .sparkSession, .sparkWeekly])
  #expect(snapshot.windows[0].remainingPercent == 75)
  #expect(snapshot.windows[1].resetsAt == Date(timeIntervalSince1970: 1_800_604_800))
  #expect(snapshot.remainingCredits == 3)
  #expect(snapshot.flexCreditUSDValue == 0.12)
  #expect(snapshot.fetchedAt == now)
}

@Test func codexFlexCreditsAreOmittedUnlessReportedAndCanReportZero() throws {
  let withNoCredits = Data(#"{"rate_limit":{"primary_window":{"used_percent":0}}}"#.utf8)
  let explicitZero = Data(
    #"{"rate_limit":{"primary_window":{"used_percent":0}},"credits":{"has_credits":false}}"#.utf8)

  #expect(try CodexUsageMapper.map(body: withNoCredits, now: .now).remainingCredits == nil)
  #expect(try CodexUsageMapper.map(body: explicitZero, now: .now).remainingCredits == 0)
}

@Test func codexWeeklyPacingUsesResetAnchoredWindowAndClampsAtEdges() {
  let reset = Date(timeIntervalSince1970: 1_800_604_800)
  let start = reset.addingTimeInterval(-CodexWeeklyPacing.windowDuration)
  let halfway = CodexWeeklyPacing(resetAt: reset, now: start.addingTimeInterval(3.5 * 24 * 60 * 60))
  let before = CodexWeeklyPacing(resetAt: reset, now: start.addingTimeInterval(-1))
  let after = CodexWeeklyPacing(resetAt: reset, now: reset.addingTimeInterval(1))

  #expect(halfway.expectedRemainingPercent == 50)
  #expect(halfway.text == "On pace, you would have 50% left by now")
  #expect(before.expectedUsedPercent == 0)
  #expect(after.expectedUsedPercent == 100)
}

@Test func codexQuotaTrafficLightUsesReferenceBoundariesAndWeeklyPacing() {
  #expect(CodexQuotaStatus.fromRemainingPercent(30) == .red)
  #expect(CodexQuotaStatus.fromRemainingPercent(31) == .yellow)
  #expect(CodexQuotaStatus.fromRemainingPercent(65) == .green)
  #expect(CodexQuotaStatus.red.emoji == "🔴")

  #expect(CodexQuotaStatus.fromRemainingPercent(16, expectedRemainingPercent: 50) == .yellow)
  #expect(CodexQuotaStatus.fromRemainingPercent(32.5, expectedRemainingPercent: 50) == .yellow)
}

@Test func codexQuotaBarSegmentsRemainingCapacityAndMarksWeeklyPace() {
  let reset = Date(timeIntervalSince1970: 1_800_604_800)
  let now = reset.addingTimeInterval(-CodexWeeklyPacing.windowDuration / 2)
  let weekly = CodexQuotaBarPresentation(
    window: CodexQuotaWindow(kind: .weekly, usedPercent: 40, resetsAt: reset), now: now)
  let session = CodexQuotaBarPresentation(
    window: CodexQuotaWindow(kind: .session, usedPercent: 80, resetsAt: nil), now: now)

  #expect(weekly.remainingFraction == 0.6)
  #expect(weekly.paceMarkerFraction == 0.5)
  #expect(abs(weekly.redBoundaryFraction - 0.15) < 0.000001)
  #expect(abs(weekly.greenBoundaryFraction - 0.4) < 0.000001)
  #expect(session.remainingFraction == 0.2)
  #expect(session.paceMarkerFraction == nil)
}

@Test func codexUsageRejectsMalformedOrPartialResponseWithoutQuotaWindows() {
  #expect(throws: CodexUsageMappingError.invalidResponse) {
    try CodexUsageMapper.map(body: Data(#"{"plan_type":"pro"}"#.utf8), now: .now)
  }
}

@Test func codexUsageSnapshotRoundTripsForPhoneAndWidgetSharing() throws {
  let snapshot = CodexUsageSnapshot(
    planName: "Pro 20x",
    windows: [
      CodexQuotaWindow(
        kind: .weekly, usedPercent: 37,
        resetsAt: Date(timeIntervalSince1970: 2_000_000_000))
    ],
    remainingCredits: 12,
    fetchedAt: Date(timeIntervalSince1970: 1_900_000_000))

  let data = try JSONEncoder().encode(snapshot)

  #expect(try JSONDecoder().decode(CodexUsageSnapshot.self, from: data) == snapshot)
}

@Test func codexUsageSnapshotDecodesBeforeOptionalRefillFieldsExisted() throws {
  let data = Data(
    #"{"windows":[{"kind":"weekly","usedPercent":20,"resetsAt":null}],"fetchedAt":600000000}"#.utf8)
  let snapshot = try JSONDecoder().decode(CodexUsageSnapshot.self, from: data)
  #expect(snapshot.recentWeeklyRefills == nil)
  #expect(snapshot.nextUnscheduledWeeklyRefill == nil)
}

@Test func weeklyHistoryRecordsOnlyMaterialRefillsAndClassifiesAgainstSchedule() {
  let start = Date(timeIntervalSince1970: 2_000_000_000)
  let scheduled = start.addingTimeInterval(2 * 24 * 60 * 60)
  var history = CodexWeeklyUsageHistory()
  history.record(.init(observedAt: start, remainingPercent: 60, scheduledResetAt: scheduled))
  history.record(
    .init(
      observedAt: start.addingTimeInterval(300), remainingPercent: 50, scheduledResetAt: scheduled))
  history.record(
    .init(
      observedAt: scheduled.addingTimeInterval(-300), remainingPercent: 48,
      scheduledResetAt: scheduled))
  history.record(
    .init(
      observedAt: scheduled.addingTimeInterval(300), remainingPercent: 100,
      scheduledResetAt: scheduled))

  #expect(history.refills.count == 1)
  #expect(history.refills[0].classification == .scheduled)
  #expect(history.refills[0].observedAfter == scheduled.addingTimeInterval(-300))
  #expect(history.refills[0].observedBy == scheduled.addingTimeInterval(300))
  #expect(history.latestScheduledResets.first?.state == .observed)
}

@Test func weeklyHistoryMarksScheduleAdjacentRefillsAmbiguousAndNormalSpendingIsNotARefill() {
  let start = Date(timeIntervalSince1970: 2_000_000_000)
  let scheduled = start.addingTimeInterval(24 * 60 * 60)
  var history = CodexWeeklyUsageHistory()
  history.record(.init(observedAt: start, remainingPercent: 70, scheduledResetAt: scheduled))
  history.record(
    .init(
      observedAt: start.addingTimeInterval(300), remainingPercent: 40, scheduledResetAt: scheduled))
  history.record(
    .init(
      observedAt: scheduled.addingTimeInterval(-3 * 60 * 60), remainingPercent: 38,
      scheduledResetAt: scheduled))
  history.record(
    .init(
      observedAt: scheduled.addingTimeInterval(-2 * 60 * 60), remainingPercent: 80,
      scheduledResetAt: scheduled))

  #expect(history.refills.count == 1)
  #expect(history.refills[0].classification == .ambiguous)
  #expect(history.latestScheduledResets.first?.state == .ambiguous)
}

@Test func weeklyHistoryKeepsExpectedScheduleWhenNoRefillWasObserved() {
  let scheduled = Date(timeIntervalSince1970: 2_000_000_000)
  var history = CodexWeeklyUsageHistory()
  history.record(
    .init(
      observedAt: scheduled.addingTimeInterval(-24 * 60 * 60), remainingPercent: 40,
      scheduledResetAt: scheduled))
  history.record(
    .init(
      observedAt: scheduled.addingTimeInterval(3 * 60 * 60), remainingPercent: 39,
      scheduledResetAt: scheduled))

  #expect(history.latestScheduledResets.first?.expectedAt == scheduled)
  #expect(history.latestScheduledResets.first?.state == .notObserved)
}

@Test func weeklyHistoryEstimatesConsistentUnscheduledCadenceWithInterval() {
  let origin = Date(timeIntervalSince1970: 2_000_000_000)
  let cadence: TimeInterval = 10 * 24 * 60 * 60
  var history = CodexWeeklyUsageHistory()
  for index in 0..<3 {
    let refill = origin.addingTimeInterval(Double(index) * cadence)
    history.record(
      .init(
        observedAt: refill.addingTimeInterval(-1800), remainingPercent: 20, scheduledResetAt: nil))
    history.record(.init(observedAt: refill, remainingPercent: 90, scheduledResetAt: nil))
  }

  let estimate = history.nextUnscheduledRefillEstimate(now: origin.addingTimeInterval(2 * cadence))
  #expect(estimate?.basedOnEvents == 3)
  let nextRefillIntervalMidpoint = origin.addingTimeInterval(3 * cadence - 15 * 60)
  #expect(estimate?.earliest == nextRefillIntervalMidpoint.addingTimeInterval(-12 * 60 * 60))
  #expect(estimate?.latest == nextRefillIntervalMidpoint.addingTimeInterval(12 * 60 * 60))
  #expect(history.nextUnscheduledRefillEstimate(now: origin.addingTimeInterval(5 * cadence)) == nil)
}

@Test func syncSnapshotCarriesCodexUsageWithoutLibraryMutation() throws {
  let usage = CodexUsageSnapshot(
    planName: "Pro 20x",
    windows: [CodexQuotaWindow(kind: .weekly, usedPercent: 37, resetsAt: nil)],
    remainingCredits: nil, fetchedAt: Date(timeIntervalSince1970: 1_900_000_000))
  let library = Library()
  let snapshot = SyncSnapshot(
    libraryID: UUID(), sequence: 4, library: library, codexUsage: usage)

  let roundTrip = try JSONDecoder.syncDecoder.decode(
    SyncSnapshot.self, from: JSONEncoder.syncEncoder.encode(snapshot))

  #expect(roundTrip.codexUsage == usage)
  #expect(try roundTrip.replica().projects.isEmpty)
}

@Test func syncUsageRefreshResponseRoundTripsSeparatelyFromLibrarySnapshot() throws {
  let usage = CodexUsageSnapshot(
    planName: "Pro 20x",
    windows: [CodexQuotaWindow(kind: .weekly, usedPercent: 37, resetsAt: nil)],
    remainingCredits: nil, fetchedAt: Date(timeIntervalSince1970: 1_900_000_000))
  let encoded = try JSONEncoder.syncEncoder.encode(SyncServerResponse.usage(usage))
  let decoded = try JSONDecoder.syncDecoder.decode(SyncServerResponse.self, from: encoded)

  guard case .usage(let received) = decoded else {
    Issue.record("Expected a usage-only sync response.")
    return
  }
  #expect(received == usage)
}
