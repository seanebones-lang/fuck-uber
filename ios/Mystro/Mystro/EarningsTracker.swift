import Foundation

// MARK: - EarningsTracker
// Real-time session/daily/weekly earnings from HistoryStore.

struct SessionEarnings {
  var total: Double
  var uberTotal: Double
  var lyftTotal: Double
  var tripCount: Int
  var startDate: Date
  var hourlyRate: Double {
    let hours = max(0.001, Date().timeIntervalSince(startDate) / 3600)
    return total / hours
  }
}

struct DailyEarnings {
  var total: Double
  var tripCount: Int
  var date: Date
}

final class EarningsTracker {

  static let shared = EarningsTracker()

  private static let keyDailyGoal = "destro.dailyGoal"

  var sessionStart: Date?

  /// Daily earnings goal in dollars. Persisted; default 200.
  var dailyGoal: Double {
    get {
      let v = UserDefaults.standard.double(forKey: Self.keyDailyGoal)
      return v > 0 ? v : 200.0
    }
    set { UserDefaults.standard.set(max(0, newValue), forKey: Self.keyDailyGoal) }
  }

  private init() {}

  /// Current session earnings (since sessionStart or last reset).
  func sessionEarnings() -> SessionEarnings {
    let start = sessionStart ?? Date()
    let entries = HistoryStore.load().filter { $0.date >= start && $0.decision == "accept" }
    var total = 0.0
    var uber = 0.0
    var lyft = 0.0
    for e in entries {
      total += e.price
      if e.app.lowercased().contains("uber") { uber += e.price }
      else if e.app.lowercased().contains("lyft") { lyft += e.price }
    }
    return SessionEarnings(total: total, uberTotal: uber, lyftTotal: lyft, tripCount: entries.count, startDate: start)
  }

  /// Today's earnings (calendar day).
  func todayEarnings() -> DailyEarnings {
    let cal = Calendar.current
    let startOfToday = cal.startOfDay(for: Date())
    let entries = HistoryStore.load().filter { $0.date >= startOfToday && $0.decision == "accept" }
    let total = entries.reduce(0.0) { $0 + $1.price }
    return DailyEarnings(total: total, tripCount: entries.count, date: startOfToday)
  }

  /// Start a new session (e.g. when user taps GO).
  func startSession() {
    sessionStart = Date()
  }

  /// End session (e.g. when user taps STOP).
  func endSession() {
    sessionStart = nil
  }

  /// Progress toward daily goal (0...1 or more).
  func dailyGoalProgress() -> Double {
    let today = todayEarnings().total
    guard dailyGoal > 0 else { return 1 }
    return today / dailyGoal
  }
}
