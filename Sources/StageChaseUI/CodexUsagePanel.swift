import SwiftUI

struct CodexUsageSummary: View {
  var snapshot: CodexUsageSnapshot?
  var status: String
  var isStale = false
  var isRefreshing = false
  var onRefresh: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "sparkle").foregroundStyle(.indigo)
        Text("Codex usage").stageFont(.headline, weight: .semibold)
        if let plan = snapshot?.planName {
          Text(plan).stageFont(.caption, weight: .medium).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
        Spacer(minLength: 4)
      }
      if let snapshot {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 14) {
            ForEach(snapshot.windows) { window in
              quota(window, now: .now).frame(maxWidth: .infinity, alignment: .leading)
            }
            creditSummary(snapshot)
          }

          VStack(alignment: .leading, spacing: 10) {
            ForEach(snapshot.windows) { window in
              quota(window, now: .now)
            }
            creditSummary(snapshot)
          }
        }
        weeklyHistory(snapshot)
        if isStale {
          Label("Showing the last successful reading", systemImage: "exclamationmark.triangle.fill")
            .stageFont(.caption).foregroundStyle(.orange)
        }
      } else {
        Text("No usage data yet.").stageFont(.subheadline).foregroundStyle(.secondary)
      }
      #if os(macOS)
        refreshFooter
      #else
        Text(status).stageFont(.caption).foregroundStyle(isStale ? .orange : .secondary)
          .lineLimit(1)
      #endif
    }
    .padding(12)
    .background(Palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("codex-usage-panel")
  }

  @ViewBuilder private func creditSummary(_ snapshot: CodexUsageSnapshot) -> some View {
    if let credits = snapshot.remainingCredits {
      let value = snapshot.flexCreditUSDValue ?? 0
      VStack(alignment: .leading, spacing: 5) {
        Text("Flex credits").stageFont(.caption, weight: .medium).foregroundStyle(.secondary)
        Text("\(credits) left · \(value.formatted(.currency(code: "USD")))")
          .stageFont(.subheadline, weight: .semibold)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder private func quota(_ window: CodexQuotaWindow, now: Date) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline) {
        Text(title(for: window.kind)).stageFont(.caption, weight: .medium).foregroundStyle(
          .secondary)
        Spacer(minLength: 4)
        Text("\(Int(window.remainingPercent.rounded()))% left")
          .stageFont(.subheadline, weight: .semibold)
      }
      CodexQuotaBar(window: window, now: now)
        .accessibilityHidden(true)
      if let reset = window.resetsAt {
        if window.kind == .weekly || window.kind == .sparkWeekly {
          Text("Scheduled reset: \(reset.formatted(date: .complete, time: .shortened))")
            .stageFont(.caption2).foregroundStyle(.tertiary).lineLimit(2)
        } else {
          Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
            .stageFont(.caption2).foregroundStyle(.tertiary)
        }
      }
      if window.kind == .weekly || window.kind == .sparkWeekly, let reset = window.resetsAt {
        Text(CodexWeeklyPacing(resetAt: reset, now: now).text)
          .stageFont(.caption2).foregroundStyle(.secondary).lineLimit(2)
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private func weeklyHistory(_ snapshot: CodexUsageSnapshot) -> some View {
    if snapshot.windows.contains(where: { $0.kind == .weekly }),
      let pattern = snapshot.recentWeeklyResetPattern
    {
      Text("Possible reset: \(pattern.nextReset.formatted(.dateTime.weekday(.wide).month(.wide).day())).")
        .stageFont(.caption2).foregroundStyle(.secondary).lineLimit(2)
    }
  }

  #if os(macOS)
    private var refreshFooter: some View {
      HStack(spacing: 7) {
        Spacer(minLength: 4)
        Text(status)
          .stageFont(.caption)
          .foregroundStyle(isStale ? .orange : .secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(status)
        if let onRefresh {
          Button(action: onRefresh) {
            if isRefreshing {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "arrow.clockwise")
            }
          }
          .buttonStyle(.borderless)
          .disabled(isRefreshing)
          .help("Refresh Codex usage")
          .accessibilityLabel("Refresh Codex usage")
        }
      }
    }
  #endif

  private func title(for kind: CodexQuotaKind) -> String {
    switch kind {
    case .session: "Session"
    case .weekly: "Weekly"
    case .sparkSession: "Spark session"
    case .sparkWeekly: "Spark weekly"
    }
  }
}

private struct CodexQuotaBar: View {
  var window: CodexQuotaWindow
  var now: Date

  var body: some View {
    GeometryReader { geometry in
      let presentation = CodexQuotaBarPresentation(window: window, now: now)
      let width = geometry.size.width
      ZStack(alignment: .leading) {
        Capsule().fill(.quaternary)
        HStack(spacing: 0) {
          Color.red.frame(width: width * presentation.redBoundaryFraction)
          Color.yellow.frame(
            width: width * (presentation.greenBoundaryFraction - presentation.redBoundaryFraction))
          Color.green.frame(width: width * (1 - presentation.greenBoundaryFraction))
        }
        .frame(width: width, alignment: .leading)
        .frame(width: width * presentation.remainingFraction, alignment: .leading)
        .clipShape(Capsule())

        if let marker = presentation.paceMarkerFraction {
          Path { path in
            let x = width * marker
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
          }
          .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        }
      }
    }
    .frame(height: 9)
  }
}

#if os(macOS)
  struct CodexUsagePanel: View {
    @Environment(AppModel.self) private var model
    private var service: CodexUsageService { model.codexUsageService }

    var body: some View {
      CodexUsageSummary(
        snapshot: service.snapshot, status: service.status, isStale: service.isStale,
        isRefreshing: service.isRefreshing,
        onRefresh: { Task { await service.refresh() } })
    }
  }

  struct CodexUsageMenuBarLabel: View {
    var service: CodexUsageService

    var body: some View {
      HStack(spacing: 3) {
        if let snapshot = service.snapshot {
          let windows = menuWindows(snapshot)
          Text(combinedStatus(for: windows, now: .now).emoji)
          ForEach(windows) { window in
            Text("\(Int(window.remainingPercent.rounded()))%")
              .monospacedDigit()
          }
          if service.isStale { Text("⚠︎") }
        } else {
          Image(systemName: "chart.bar.xaxis")
        }
      }
      .font(.system(size: 12, weight: .medium))
      .fixedSize()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel)
      .help(accessibilityLabel)
    }

    private var accessibilityLabel: String {
      guard let snapshot = service.snapshot else {
        return "Codex usage, \(service.status)"
      }
      let now = Date.now
      let windows = menuWindows(snapshot)
      let overall = combinedStatus(for: windows, now: now).rawValue
      let metrics = windows.map { window in
        let pace = expectedRemainingPercent(for: window, now: now)
        let light = CodexQuotaStatus.fromRemainingPercent(
          window.remainingPercent, expectedRemainingPercent: pace
        ).rawValue
        return
          "\(window.kind), \(Int(window.remainingPercent.rounded())) percent remaining, \(light)"
      }
      let stale = service.isStale ? ", showing stale usage" : ""
      return "Codex usage, overall \(overall), \(metrics.joined(separator: ", "))\(stale)"
    }

    private func combinedStatus(for windows: [CodexQuotaWindow], now: Date) -> CodexQuotaStatus {
      let statuses = windows.map { window in
        CodexQuotaStatus.fromRemainingPercent(
          window.remainingPercent,
          expectedRemainingPercent: expectedRemainingPercent(for: window, now: now))
      }
      if statuses.contains(.red) { return .red }
      if statuses.contains(.yellow) { return .yellow }
      return .green
    }

    private func menuWindows(_ snapshot: CodexUsageSnapshot) -> [CodexQuotaWindow] {
      let primary = snapshot.windows.filter { $0.kind == .session || $0.kind == .weekly }
      return primary.isEmpty ? Array(snapshot.windows.prefix(1)) : primary
    }

    private func expectedRemainingPercent(for window: CodexQuotaWindow, now: Date) -> Double? {
      guard window.kind == .weekly || window.kind == .sparkWeekly,
        let reset = window.resetsAt
      else { return nil }
      return CodexWeeklyPacing(resetAt: reset, now: now).expectedRemainingPercent
    }
  }

  struct CodexUsageMenuBarPanel: View {
    var service: CodexUsageService

    var body: some View {
      CodexUsageSummary(
        snapshot: service.snapshot,
        status: service.status,
        isStale: service.isStale,
        isRefreshing: service.isRefreshing,
        onRefresh: { Task { await service.refresh() } }
      )
      .padding(12)
      .frame(width: 370)
    }
  }
#endif
