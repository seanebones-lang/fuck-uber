import WidgetKit
import SwiftUI

private let appGroup = "group.com.mystro.app"
private let statusKey = "mystro.scan.status"
private let lastAppKey = "mystro.scan.lastApp"

// MARK: - Timeline

struct MystroEntry: TimelineEntry {
  let date: Date
  let status: String
  let lastApp: String
}

struct MystroProvider: TimelineProvider {
  func placeholder(in context: Context) -> MystroEntry {
    MystroEntry(date: Date(), status: "🟢 SCANNING", lastApp: "—")
  }

  func getSnapshot(in context: Context, completion: @escaping (MystroEntry) -> Void) {
    let entry = currentEntry()
    completion(entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<MystroEntry>) -> Void) {
    let entry = currentEntry()
    let next = Date().addingTimeInterval(30)
    let timeline = Timeline(entries: [entry], policy: .after(next))
    completion(timeline)
  }

  private func currentEntry() -> MystroEntry {
    let defaults = UserDefaults(suiteName: appGroup)
    let status = defaults?.string(forKey: statusKey) ?? "🔴 Idle"
    let lastApp = defaults?.string(forKey: lastAppKey) ?? "—"
    return MystroEntry(date: Date(), status: status, lastApp: lastApp)
  }
}

// MARK: - Views

struct MystroWidgetView: View {
  var entry: MystroEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Mystro")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(entry.status)
        .font(.subheadline)
        .fontWeight(.medium)
      Text(entry.lastApp)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

// MARK: - Widget

struct MystroWidget: Widget {
  let kind = "MystroWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: MystroProvider()) { entry in
      MystroWidgetView(entry: entry)
    }
    .configurationDisplayName("Mystro")
    .description("Scan status: 🟢 Active or 🔴 Idle.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct MystroWidgetBundle: WidgetBundle {
  var body: some Widget {
    MystroWidget()
  }
}

#Preview(as: .systemSmall) {
  MystroWidget()
} timeline: {
  MystroEntry(date: .now, status: "🟢 SCANNING", lastApp: "com.ubercab.driver")
}
