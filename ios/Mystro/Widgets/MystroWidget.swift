import WidgetKit
import SwiftUI

private let appGroup = "group.com.destro.app"
private let statusKey = "destro.scan.status"
private let lastAppKey = "destro.scan.lastApp"
private let earningsKey = "destro.scan.sessionEarnings"

// MARK: - Timeline

struct DestroEntry: TimelineEntry {
  let date: Date
  let status: String
  let lastApp: String
  let sessionEarnings: Double
}

struct DestroProvider: TimelineProvider {
  /// Cached app-group suite; created once per widget process to avoid repeated CFPrefs access.
  fileprivate static let suiteDefaults = UserDefaults(suiteName: appGroup)

  func placeholder(in context: Context) -> DestroEntry {
    DestroEntry(date: Date(), status: "🟢 SCANNING", lastApp: "—", sessionEarnings: 0)
  }

  func getSnapshot(in context: Context, completion: @escaping (DestroEntry) -> Void) {
    let entry = currentEntry()
    completion(entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DestroEntry>) -> Void) {
    let entry = currentEntry()
    let next = Date().addingTimeInterval(30)
    let timeline = Timeline(entries: [entry], policy: .after(next))
    completion(timeline)
  }

  private func currentEntry() -> DestroEntry {
    let defaults = DestroProvider.suiteDefaults
    let status = defaults?.string(forKey: statusKey) ?? "🔴 Idle"
    let lastApp = defaults?.string(forKey: lastAppKey) ?? "—"
    let earnings = defaults?.double(forKey: earningsKey) ?? 0
    return DestroEntry(date: Date(), status: status, lastApp: lastApp, sessionEarnings: earnings)
  }
}

// MARK: - Views

private struct DestroStatusBlock: View {
  let entry: DestroEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Destro")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(entry.status)
        .font(.subheadline.weight(.medium))
      Text(entry.lastApp)
        .font(.caption2)
        .foregroundStyle(.tertiary)
      if entry.sessionEarnings > 0 {
        Text(String(format: "Session: $%.2f", entry.sessionEarnings))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

struct DestroWidgetView: View {
  var entry: DestroEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    Group {
      switch family {
      case .accessoryCircular:
        ZStack {
          VStack(spacing: 0) {
            Text(entry.status.prefix(1))
              .font(.title2.bold())
            if entry.sessionEarnings > 0 {
              Text(String(format: "$%.0f", entry.sessionEarnings))
                .font(.caption2)
                .multilineTextAlignment(.center)
            }
          }
        }
      case .accessoryRectangular:
        DestroStatusBlock(entry: entry)
      case .accessoryInline:
        Text("\(entry.status) \(entry.lastApp) · $\(String(format: "%.0f", entry.sessionEarnings))")
          .font(.caption)
      default:
        DestroStatusBlock(entry: entry)
      }
    }
    .modifier(ContainerBackgroundModifier())
  }
}

// iOS 17+ requires containerBackground(for: .widget); avoid warning and wrong background.
private struct ContainerBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(for: .widget) {
        Color(.systemBackground)
      }
    } else {
      content
    }
  }
}

// MARK: - Widget

struct DestroWidget: Widget {
  let kind = "DestroWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: DestroProvider()) { entry in
      DestroWidgetView(entry: entry)
    }
    .configurationDisplayName("Destro")
    .description("Scan status: 🟢 Active or 🔴 Idle.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge,
      .accessoryCircular, .accessoryRectangular, .accessoryInline
    ])
  }
}

@main
struct DestroWidgetBundle: WidgetBundle {
  var body: some Widget {
    DestroWidget()
  }
}

#Preview(as: .systemSmall) {
  DestroWidget()
} timeline: {
  DestroEntry(date: .now, status: "🟢 SCANNING", lastApp: "com.ubercab.driver", sessionEarnings: 42.50)
}
