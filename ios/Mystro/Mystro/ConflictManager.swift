import Foundation

// MARK: - ConflictState

enum ConflictState: Equatable {
  case idle
  case rideActive(app: String)
  case transitioning
}

// MARK: - ConflictManager
// When a ride is accepted on one app, takes the other app offline. On ride completion, brings other app back online.

final class ConflictManager {

  static let uberBundleId = "com.ubercab.driver"
  static let lyftBundleId = "me.lyft.driver"

  private(set) var state: ConflictState = .idle {
    didSet {
      if state != oldValue {
        onStateChange?(state)
      }
    }
  }

  var onStateChange: ((ConflictState) -> Void)?

  private let appSwitcher = AppSwitcher.shared

  /// Call when user/daemon accepts a ride on the given app. Takes the other app offline.
  func rideAccepted(appBundleId: String) {
    state = .rideActive(app: appBundleId)
    let other = otherBundleId(than: appBundleId)
    if !other.isEmpty {
      _ = appSwitcher.sendToBackground(bundleId: other)
    }
  }

  /// Call when ride is completed (detected via polling or accessibility). Brings other app back online.
  func rideCompleted(wasActiveAppBundleId: String) {
    state = .transitioning
    let other = otherBundleId(than: wasActiveAppBundleId)
    if !other.isEmpty {
      _ = appSwitcher.bringToForeground(bundleId: other)
    }
    state = .idle
  }

  /// Manual reset to idle (e.g. user cancelled or trip never started).
  func reset() {
    state = .idle
  }

  private func otherBundleId(than bundleId: String) -> String {
    if bundleId.contains("uber") { return ConflictManager.lyftBundleId }
    if bundleId.contains("lyft") { return ConflictManager.uberBundleId }
    return ""
  }
}
