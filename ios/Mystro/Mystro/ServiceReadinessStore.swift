import Foundation

// MARK: - ServiceReadiness
// Lifecycle for manual sign-in: unlinked → linked (user opened app) → ready (optional; use when we have confirmation).

enum ServiceReadiness: String, Codable, CaseIterable {
  case unlinked
  case linked
  case ready
  case degraded
}

// MARK: - ServiceReadinessStore
// Persisted per-service readiness. Used to gate GO and show status on cards.

enum ServiceReadinessStore {
  private static func key(bundleId: String) -> String {
    "mystro.readiness.\(bundleId)"
  }

  static func get(bundleId: String) -> ServiceReadiness {
    guard let raw = UserDefaults.standard.string(forKey: key(bundleId: bundleId)),
          let r = ServiceReadiness(rawValue: raw) else { return .unlinked }
    return r
  }

  static func set(_ readiness: ServiceReadiness, bundleId: String) {
    UserDefaults.standard.set(readiness.rawValue, forKey: key(bundleId: bundleId))
  }

  /// Call when user taps "Open Uber/Lyft" to open the driver app — mark as linked.
  static func markLinked(bundleId: String) {
    set(.linked, bundleId: bundleId)
  }

  /// True if we can consider this service available for scanning (linked or better).
  static func isAvailableForScan(bundleId: String) -> Bool {
    switch get(bundleId: bundleId) {
    case .unlinked: return false
    case .linked, .ready, .degraded: return true
    }
  }
}
