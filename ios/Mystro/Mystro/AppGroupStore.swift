import Foundation
import WidgetKit

// MARK: - AppGroupStore
// Writes daemon status and session earnings to the app group for the widget.
// Requires App Group capability (group.com.destro.app) on main app and widget extension.
// If the suite is unavailable (e.g. Simulator without proper provisioning), we cache nil
// and no-op writes / return safe defaults for reads to avoid repeated CFPrefs errors.

enum AppGroupStore {
  private static let suiteName = "group.com.destro.app"
  private static let statusKey = "destro.scan.status"
  private static let lastAppKey = "destro.scan.lastApp"
  private static let earningsKey = "destro.scan.sessionEarnings"
  private static let conflictStateKey = "destro.scan.conflictState"

  /// Cached suite; created once. Nil if app group is unavailable (avoids repeated CFPrefs access).
  private static let _defaults: UserDefaults? = {
    UserDefaults(suiteName: suiteName)
  }()

  static var defaults: UserDefaults? { _defaults }

  static func writeStatus(_ status: String, lastApp: String = "—") {
    defaults?.set(status, forKey: statusKey)
    defaults?.set(lastApp, forKey: lastAppKey)
    if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
  }

  static func writeSessionEarnings(_ amount: Double) {
    defaults?.set(amount, forKey: earningsKey)
    if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
  }

  static func writeConflictState(_ state: String) {
    defaults?.set(state, forKey: conflictStateKey)
  }

  static func readStatus() -> (status: String, lastApp: String) {
    let s = defaults?.string(forKey: statusKey) ?? "🔴 Idle"
    let a = defaults?.string(forKey: lastAppKey) ?? "—"
    return (s, a)
  }
}
