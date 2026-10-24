import SwiftUI
import WidgetKit

private let usageSuite = "group.com.cseibert.StageChase"
private let usageKey = "codexUsageSnapshot-v1"

private struct UsageEntry: TimelineEntry {
  var date: Date
  var snapshot: CodexUsageSnapshot?
}

private struct UsageProvider: TimelineProvider {
  func placeholder(in context: Context) -> UsageEntry {
    UsageEntry(date: .now, snapshot: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
    completion(currentEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
    let entry = currentEntry()
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
  }

  private func currentEntry() -> UsageEntry {
    let snapshot = UserDefaults(suiteName: usageSuite)?.data(forKey: usageKey)
      .flatMap { try? JSONDecoder().decode(CodexUsageSnapshot.self, from: $0) }
    return UsageEntry(date: .now, snapshot: snapshot)
  }
}

private struct UsageWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: UsageEntry

  var body: some View {
    if family == .accessoryCircular {
      circular.containerBackground(for: .widget) { AccessoryWidgetBackground() }
    } else if family == .accessoryRectangular {
      rectangular.containerBackground(for: .widget) { AccessoryWidgetBackground() }
    } else {
      homeScreen
    }
  }

  private var weekly: CodexQuotaWindow? {
    entry.snapshot?.windows.first { $0.kind == .weekly }
  }

  private var session: CodexQuotaWindow? {
    entry.snapshot?.windows.first { $0.kind == .session }
  }

  private var circular: some View {
    Gauge(value: weekly?.remainingPercent ?? 0, in: 0...100) {
      Text("Codex")
    } currentValueLabel: {
      Text(weekly.map { "\(Int($0.remainingPercent.rounded()))" } ?? "—")
    }
    .gaugeStyle(.accessoryCircular)
    .accessibilityLabel(
      weekly.map { "Codex, \(Int($0.remainingPercent.rounded())) percent weekly capacity left" }
        ?? "Codex usage unavailable")
  }

  private var rectangular: some View {
    VStack(alignment: .leading, spacing: 3) {
      Label("Codex", systemImage: "sparkle")
        .font(.headline)
      if let weekly {
        Text("Weekly · \(Int(weekly.remainingPercent.rounded()))% left")
        if let session { Text("Session · \(Int(session.remainingPercent.rounded()))% left") }
      } else {
        Text("Open StageChase to sync usage")
      }
      if let reset = weekly?.resetsAt {
        Text(
          "Reset \(reset.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))"
        )
        if family == .systemMedium {
          Text(CodexWeeklyPacing(resetAt: reset, now: .now).text)
        }
      }
      refillHistory
    }
    .font(.caption)
  }

  private var homeScreen: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Codex", systemImage: "sparkle").font(.headline)
        Spacer(minLength: 0)
        if let plan = entry.snapshot?.planName {
          Text(plan).font(.caption2).foregroundStyle(.secondary)
        }
      }
      if let weekly {
        quota("Weekly", window: weekly)
        if let reset = weekly.resetsAt {
          Text(
            "Reset \(reset.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))"
          )
          .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
      } else {
        Text("Open StageChase to sync usage").font(.caption).foregroundStyle(.secondary)
      }
      if let session { quota("Session", window: session) }
      if family == .systemMedium {
        if let reset = weekly?.resetsAt {
          Text(CodexWeeklyPacing(resetAt: reset, now: .now).text)
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        refillHistory
      }
      if let credits = entry.snapshot?.remainingCredits {
        let value = entry.snapshot?.flexCreditUSDValue ?? 0
        Text("Flex · \(credits) · \(value.formatted(.currency(code: "USD")))")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }

  private func quota(_ label: String, window: CodexQuotaWindow) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(label).font(.caption)
        Spacer()
        Text("\(Int(window.remainingPercent.rounded()))% left")
          .font(.caption.weight(.semibold)).monospacedDigit()
      }
      ProgressView(value: window.remainingPercent, total: 100)
        .tint(window.remainingPercent < 20 ? .orange : .indigo)
    }
  }

  @ViewBuilder private var refillHistory: some View {
    if let pattern = entry.snapshot?.recentWeeklyResetPattern {
      Text(
        "Last 60 days: reset every \(pattern.averageIntervalDays.formatted(.number.precision(.fractionLength(0...1)))) days on average."
      )
      .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
      if pattern.earlyResetCount > 0, let daysEarly = pattern.averageDaysEarly {
        Text("Early \(pattern.earlyResetCount) times, about \(daysEarly.formatted(.number.precision(.fractionLength(0...1)))) days ahead.")
          .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
      }
      Text("Next, if repeated: \(pattern.nextReset.formatted(date: .complete, time: .omitted))")
        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
    }
  }
}

@main
struct StageChaseUsageWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "StageChaseCodexUsage", provider: UsageProvider()) { entry in
      UsageWidgetView(entry: entry)
    }
    .configurationDisplayName("Codex usage")
    .description("See your remaining Codex session and weekly capacity.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular,
    ])
  }
}
