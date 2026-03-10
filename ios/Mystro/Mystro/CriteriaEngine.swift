import Foundation
import CoreLocation

// MARK: - CriteriaEngine
// Single source of truth for accept/reject rules. Uses FilterConfig for thresholds.

struct CriteriaEngine {
  /// Evaluates offer against current filter config; uses DynamicRuleEngine for adaptive min price, $/mile, max pickup.
  static func evaluate(_ offer: OfferData) -> RideDecision {
    let effective = DynamicRuleEngine.shared.effectiveThresholds(idleMinutes: ProdDaemon.idleMinutesForCriteria)
    let minPrice = effective.minPrice
    let minPricePerMile = effective.minPricePerMile
    let maxPickupDistance = effective.maxPickupDistance

    if offer.price < minPrice { return .reject(reason: .belowMinPrice) }
    if offer.miles <= 0 { return .reject(reason: .belowMinPricePerMile) }
    if offer.price / offer.miles < minPricePerMile { return .reject(reason: .belowMinPricePerMile) }
    if offer.shared { return .reject(reason: .sharedRide) }
    if offer.stops > 1 { return .reject(reason: .tooManyStops) }

    if let rate = offer.estimatedHourlyRate, rate < FilterConfig.minHourlyRate {
      return .reject(reason: .belowMinHourlyRate)
    }
    if let pickupMi = offer.pickupDistanceMiles, pickupMi > maxPickupDistance {
      return .reject(reason: .pickupTooFar)
    }
    if let rating = offer.passengerRating, rating < FilterConfig.minPassengerRating {
      return .reject(reason: .lowPassengerRating)
    }
    if let surge = offer.surgeMultiplier, surge < FilterConfig.minSurgeMultiplier {
      return .reject(reason: .belowSurgeThreshold)
    }
    if let rt = offer.rideType, FilterConfig.blockedRideTypes.contains(rt) {
      return .reject(reason: .blockedRideType)
    }

    let hour = Calendar.current.component(.hour, from: Date())
    let start = FilterConfig.activeHoursStart
    let end = FilterConfig.activeHoursEnd
    if start > end {
      if hour < start && hour > end { return .reject(reason: .timeRestriction) }
    } else {
      if hour < start || hour > end { return .reject(reason: .timeRestriction) }
    }

    if GeofenceManager.shared.shouldRejectByGeofence(pickupCoordinate: offer.pickupLocation) {
      return .reject(reason: .outsideGeofence)
    }

    return .accept(reason: .meetsCriteria)
  }
}
