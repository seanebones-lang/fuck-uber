import Foundation
import UIKit
import CoreLocation

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
  let pickupLocation: CLLocationCoordinate2D?
  let dropoffLocation: CLLocationCoordinate2D?
  let estimatedMinutes: Double?
  let passengerRating: Double?
  let surgeMultiplier: Double?
  let rideType: RideType?
  let pickupDistanceMiles: Double?
  let estimatedHourlyRate: Double?

  init(
    price: Double,
    miles: Double,
    shared: Bool,
    stops: Int,
    acceptPoint: CGPoint,
    rejectPoint: CGPoint?,
    pickupLocation: CLLocationCoordinate2D? = nil,
    dropoffLocation: CLLocationCoordinate2D? = nil,
    estimatedMinutes: Double? = nil,
    passengerRating: Double? = nil,
    surgeMultiplier: Double? = nil,
    rideType: RideType? = nil,
    pickupDistanceMiles: Double? = nil,
    estimatedHourlyRate: Double? = nil
  ) {
    self.price = price
    self.miles = miles
    self.shared = shared
    self.stops = stops
    self.acceptPoint = acceptPoint
    self.rejectPoint = rejectPoint
    self.pickupLocation = pickupLocation
    self.dropoffLocation = dropoffLocation
    self.estimatedMinutes = estimatedMinutes
    self.passengerRating = passengerRating
    self.surgeMultiplier = surgeMultiplier
    self.rideType = rideType
    self.pickupDistanceMiles = pickupDistanceMiles
    self.estimatedHourlyRate = estimatedHourlyRate
  }
}

// MARK: - Ride Type

enum RideType: String, Codable, CaseIterable {
  case uberX
  case uberXL
  case uberBlack
  case lyftStandard = "lyft_standard"
  case lyftXL = "lyft_xl"
  case lyftLux = "lyft_lux"
  case other

  var displayName: String {
    switch self {
    case .uberX: return "UberX"
    case .uberXL: return "Uber XL"
    case .uberBlack: return "Uber Black"
    case .lyftStandard: return "Lyft Standard"
    case .lyftXL: return "Lyft XL"
    case .lyftLux: return "Lyft Lux"
    case .other: return "Other"
    }
  }
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
  case belowMinHourlyRate = "below_min_hourly_rate"
  case pickupTooFar = "pickup_too_far"
  case outsideGeofence = "outside_geofence"
  case timeRestriction = "time_restriction"
  case lowPassengerRating = "low_passenger_rating"
  case belowSurgeThreshold = "below_surge_threshold"
  case blockedRideType = "blocked_ride_type"
  case belowRideQuality = "below_ride_quality"
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

/// Tries primary source first; if nil, tries fallback (e.g. Accessibility then Vision OCR).
final class FallbackOfferSource: OfferSource {
  private let primary: OfferSource
  private let fallback: OfferSource

  init(primary: OfferSource, fallback: OfferSource) {
    self.primary = primary
    self.fallback = fallback
  }

  func fetchOffer(appBundleId: String) -> OfferData? {
    primary.fetchOffer(appBundleId: appBundleId) ?? fallback.fetchOffer(appBundleId: appBundleId)
  }
}

/// After 3 consecutive nils from primary, uses only fallback for 10 cycles (error recovery).
final class AdaptiveFallbackOfferSource: OfferSource {
  private let primary: OfferSource
  private let fallback: OfferSource
  private var consecutiveNilCount = 0
  private var fallbackOnlyCyclesLeft = 0
  private let fallbackOnlyCycleCount = 10
  private let consecutiveNilThreshold = 3

  init(primary: OfferSource, fallback: OfferSource) {
    self.primary = primary
    self.fallback = fallback
  }

  func fetchOffer(appBundleId: String) -> OfferData? {
    if fallbackOnlyCyclesLeft > 0 {
      fallbackOnlyCyclesLeft -= 1
      return fallback.fetchOffer(appBundleId: appBundleId)
    }
    if let offer = primary.fetchOffer(appBundleId: appBundleId) {
      consecutiveNilCount = 0
      return offer
    }
    consecutiveNilCount += 1
    if consecutiveNilCount >= consecutiveNilThreshold {
      fallbackOnlyCyclesLeft = fallbackOnlyCycleCount
      consecutiveNilCount = 0
      return fallback.fetchOffer(appBundleId: appBundleId)
    }
    return fallback.fetchOffer(appBundleId: appBundleId)
  }
}

// MARK: - ActionExecutor

/// Pluggable executor for accept/reject taps. Default is no-op for non-jailbroken iOS.
protocol ActionExecutor: AnyObject {
  /// Returns true if the tap was successfully injected.
  func executeAccept(at point: CGPoint, appBundleId: String) -> Bool
  func executeReject(at point: CGPoint, appBundleId: String) -> Bool
}

/// Default: no tap simulation. Replace with Accessibility or other injector when available.
final class NoOpActionExecutor: ActionExecutor {
  func executeAccept(at point: CGPoint, appBundleId: String) -> Bool { false }
  func executeReject(at point: CGPoint, appBundleId: String) -> Bool { false }
}

/// Tries primary (e.g. AX press) first; if it returns false, tries fallback (e.g. HID inject). Ensures accept/reject works when AX is available.
final class FallbackActionExecutor: ActionExecutor {
  private let primary: ActionExecutor
  private let fallback: ActionExecutor

  init(primary: ActionExecutor, fallback: ActionExecutor) {
    self.primary = primary
    self.fallback = fallback
  }

  func executeAccept(at point: CGPoint, appBundleId: String) -> Bool {
    primary.executeAccept(at: point, appBundleId: appBundleId)
      || fallback.executeAccept(at: point, appBundleId: appBundleId)
  }

  func executeReject(at point: CGPoint, appBundleId: String) -> Bool {
    primary.executeReject(at: point, appBundleId: appBundleId)
      || fallback.executeReject(at: point, appBundleId: appBundleId)
  }
}
