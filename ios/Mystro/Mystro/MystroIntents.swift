import AppIntents
import Foundation
import UIKit

// MARK: - Destro Intents (Siri / Shortcuts)

@available(iOS 16.0, *)
struct GoOnlineIntent: AppIntent {
  static var title: LocalizedStringResource = "Go online"
  static var description = IntentDescription("Start Destro scanning (Uber/Lyft).")

  func perform() async throws -> some IntentResult {
    let daemon = await DaemonHolder.shared.daemon
    guard let daemon else { return .result() }
    daemon.enabledBundleIds = ["com.ubercab.driver", "me.lyft.driver"]
    daemon.startScanning()
    EarningsTracker.shared.startSession()
    UserDefaults.standard.set(true, forKey: "destro.wasScanning")
    UserDefaults.standard.set(true, forKey: "destro.hasGoneOnlineOnce")
    if #available(iOS 16.1, *) { startDestroLiveActivity() }
    GeofenceManager.shared.startUpdatingLocation()
    NotificationCenter.default.post(name: .destroDaemonDidStartScanning, object: nil)
    return .result()
  }
}

@available(iOS 16.0, *)
struct GoOfflineIntent: AppIntent {
  static var title: LocalizedStringResource = "Go offline"
  static var description = IntentDescription("Stop Destro scanning.")

  func perform() async throws -> some IntentResult {
    let daemon = await DaemonHolder.shared.daemon
    guard let daemon else { return .result() }
    daemon.stopScanning()
    EarningsTracker.shared.endSession()
    UserDefaults.standard.set(false, forKey: "destro.wasScanning")
    if #available(iOS 16.1, *) { endDestroLiveActivity() }
    GeofenceManager.shared.stopUpdatingLocation()
    NotificationCenter.default.post(name: .destroDaemonDidBecomeIdle, object: nil)
    return .result()
  }
}

@available(iOS 16.0, *)
struct GetEarningsIntent: AppIntent {
  static var title: LocalizedStringResource = "What are my earnings?"
  static var description = IntentDescription("Returns today's and session earnings.")

  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let today = EarningsTracker.shared.todayEarnings()
    let session = EarningsTracker.shared.sessionEarnings()
    let text = "Today: $\(String(format: "%.2f", today.total)) (\(today.tripCount) trips). Session: $\(String(format: "%.2f", session.total)) (\(String(format: "%.1f", session.hourlyRate))/hr."
    return .result(value: text)
  }
}

@available(iOS 16.0, *)
struct SetMinimumPriceIntent: AppIntent {
  static var title: LocalizedStringResource = "Set minimum trip price"
  static var description = IntentDescription("Set Destro minimum trip price in dollars.")

  @Parameter(title: "Minimum ($)")
  var minimum: Double?

  func perform() async throws -> some IntentResult {
    if let v = minimum, v > 0 {
      FilterConfig.minPrice = v
    }
    return .result()
  }
}

@available(iOS 16.0, *)
struct SetMinPricePerMileIntent: AppIntent {
  static var title: LocalizedStringResource = "Set minimum $/mile"
  static var description = IntentDescription("Set Destro minimum dollars per mile.")

  @Parameter(title: "Minimum $/mile")
  var minPerMile: Double?

  func perform() async throws -> some IntentResult {
    if let v = minPerMile, v >= 0 {
      FilterConfig.minPricePerMile = v
    }
    return .result()
  }
}

@available(iOS 16.0, *)
struct SetMaxPickupIntent: AppIntent {
  static var title: LocalizedStringResource = "Set max pickup distance"
  static var description = IntentDescription("Set Destro maximum pickup distance in miles.")

  @Parameter(title: "Max pickup (miles)")
  var maxPickup: Double?

  func perform() async throws -> some IntentResult {
    if let v = maxPickup, v >= 0 {
      FilterConfig.maxPickupDistance = v
    }
    return .result()
  }
}

@available(iOS 16.0, *)
struct GoOnlineServiceIntent: AppIntent {
  static var title: LocalizedStringResource = "Go online (Uber or Lyft only)"
  static var description = IntentDescription("Start Destro scanning on Uber only, Lyft only, or both.")

  @Parameter(title: "Service")
  var service: DestroServiceAppEnum?

  func perform() async throws -> some IntentResult {
    let daemon = await DaemonHolder.shared.daemon
    guard let daemon else { return .result() }
    let ids: [String]
    switch service ?? .both {
    case .uber: ids = ["com.ubercab.driver"]
    case .lyft: ids = ["me.lyft.driver"]
    case .both: ids = ["com.ubercab.driver", "me.lyft.driver"]
    }
    daemon.enabledBundleIds = ids
    daemon.startScanning()
    EarningsTracker.shared.startSession()
    UserDefaults.standard.set(true, forKey: "destro.wasScanning")
    UserDefaults.standard.set(true, forKey: "destro.hasGoneOnlineOnce")
    if #available(iOS 16.1, *) { startDestroLiveActivity() }
    GeofenceManager.shared.startUpdatingLocation()
    NotificationCenter.default.post(name: .destroDaemonDidStartScanning, object: nil)
    return .result()
  }
}

@available(iOS 16.0, *)
enum DestroServiceAppEnum: String, AppEnum {
  case uber = "Uber"
  case lyft = "Lyft"
  case both = "Both"
  static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Service") }
  static var caseDisplayRepresentations: [DestroServiceAppEnum: DisplayRepresentation] {
    [.uber: DisplayRepresentation(title: "Uber only"), .lyft: DisplayRepresentation(title: "Lyft only"), .both: DisplayRepresentation(title: "Both")]
  }
}

@available(iOS 16.0, *)
struct DestroShortcuts: AppShortcutsProvider {
  @AppShortcutsBuilder
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: GoOnlineIntent(), phrases: ["Go online with \(.applicationName)", "Start \(.applicationName)"], shortTitle: "Go online", systemImageName: "play.circle")
    AppShortcut(intent: GoOnlineServiceIntent(), phrases: ["Go online on Uber with \(.applicationName)", "Go online on Lyft with \(.applicationName)"], shortTitle: "Go online (service)", systemImageName: "play.circle.fill")
    AppShortcut(intent: GoOfflineIntent(), phrases: ["Go offline with \(.applicationName)", "Stop \(.applicationName)"], shortTitle: "Go offline", systemImageName: "stop.circle")
    AppShortcut(intent: GetEarningsIntent(), phrases: ["What are my earnings in \(.applicationName)", "Earnings \(.applicationName)"], shortTitle: "Earnings", systemImageName: "dollarsign.circle")
    AppShortcut(intent: SetMinimumPriceIntent(), phrases: ["Set minimum in \(.applicationName)"], shortTitle: "Set minimum", systemImageName: "dollarsign")
    AppShortcut(intent: SetMinPricePerMileIntent(), phrases: ["Set minimum per mile in \(.applicationName)"], shortTitle: "Set $/mile", systemImageName: "dollarsign")
    AppShortcut(intent: SetMaxPickupIntent(), phrases: ["Set max pickup in \(.applicationName)"], shortTitle: "Set max pickup", systemImageName: "location")
  }
}
