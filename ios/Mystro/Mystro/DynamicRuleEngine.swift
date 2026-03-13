import Foundation
import UIKit

// MARK: - DynamicRuleEngine
// Adjusts filter thresholds dynamically based on time, battery, idle duration.

final class DynamicRuleEngine {

  static let shared = DynamicRuleEngine()

  private init() {}

  /// Effective min $/mile for current context (rush hour = stricter).
  func effectiveMinPricePerMile(base: Double) -> Double {
    let hour = Calendar.current.component(.hour, from: Date())
    let isRushHour = (7...9).contains(hour) || (16...19).contains(hour)
    if isRushHour { return base * 1.1 }
    return base
  }

  /// True if current time is in rush hour (7–9a, 4–7p); use for UI indicator.
  var isCurrentlyRushHour: Bool {
    let hour = Calendar.current.component(.hour, from: Date())
    return (7...9).contains(hour) || (16...19).contains(hour)
  }

  /// Short description for dashboard badge when rush hour is active.
  var rushHourDescription: String { "Rush hour: min $/mile +10%" }

  /// Effective min trip price (relax after long idle).
  func effectiveMinPrice(base: Double, idleMinutes: Double) -> Double {
    if idleMinutes > 30 { return base * 0.9 }
    return base
  }

  /// Effective max pickup distance (relax when battery low to end sooner).
  func effectiveMaxPickupDistance(base: Double) -> Double {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    if level >= 0 && level < 0.2 { return base * 1.2 }
    return base
  }

  /// Apply dynamic adjustments to a copy of FilterConfig-like values for evaluation.
  struct EffectiveThresholds {
    var minPrice: Double
    var minPricePerMile: Double
    var maxPickupDistance: Double
  }

  func effectiveThresholds(idleMinutes: Double = 0, service: String = "uber") -> EffectiveThresholds {
    EffectiveThresholds(
      minPrice: effectiveMinPrice(base: FilterConfig.minPrice(service: service), idleMinutes: idleMinutes),
      minPricePerMile: effectiveMinPricePerMile(base: FilterConfig.minPricePerMile(service: service)),
      maxPickupDistance: effectiveMaxPickupDistance(base: FilterConfig.maxPickupDistance(service: service))
    )
  }
}
