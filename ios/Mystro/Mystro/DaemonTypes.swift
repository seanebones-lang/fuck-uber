import Foundation
import UIKit

// MARK: - Daemon State

enum DaemonState: Equatable {
  case idle
  case scanning
  case decisioning(app: String)
  case cooldown
  case error(String)
}

// MARK: - Offer Data

struct OfferData {
  let price: Double
  let miles: Double
  let shared: Bool
  let stops: Int
  let acceptPoint: CGPoint
  /// Reject button center for auto-reject tap when available from offer source.
  let rejectPoint: CGPoint?
}

// MARK: - Decision Reason Codes

enum DecisionReason: String, Codable {
  case meetsCriteria = "meets_criteria"
  case belowMinPrice = "below_min_price"
  case belowMinPricePerMile = "below_min_price_per_mile"
  case sharedRide = "shared_ride"
  case tooManyStops = "too_many_stops"
  case autoAcceptDisabled = "auto_accept_disabled"
  case autoRejectMatch = "auto_reject_match"
  case noOffer = "no_offer"
}

enum RideDecision: Equatable {
  case accept(reason: DecisionReason)
  case reject(reason: DecisionReason)
}

// MARK: - OfferSource

/// Pluggable source of ride offers. Default implementation returns nil (no cross-app read on non-jailbroken iOS).
protocol OfferSource: AnyObject {
  func fetchOffer(appBundleId: String) -> OfferData?
}

/// Default: no UI read; returns nil. Replace with Accessibility-based implementation when available.
final class NilOfferSource: OfferSource {
  func fetchOffer(appBundleId: String) -> OfferData? { nil }
}

// MARK: - ActionExecutor

/// Pluggable executor for accept/reject taps. Default is no-op for non-jailbroken iOS.
protocol ActionExecutor: AnyObject {
  func executeAccept(at point: CGPoint, appBundleId: String)
  func executeReject(at point: CGPoint, appBundleId: String)
}

/// Default: no tap simulation. Replace with Accessibility or other injector when available.
final class NoOpActionExecutor: ActionExecutor {
  func executeAccept(at point: CGPoint, appBundleId: String) {}
  func executeReject(at point: CGPoint, appBundleId: String) {}
}
