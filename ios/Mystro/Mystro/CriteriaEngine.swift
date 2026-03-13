import Foundation
import CoreLocation

// MARK: - CriteriaEngine
// Single source of truth for accept/reject rules. Uses FilterConfig for thresholds.

struct CriteriaEngine {
  /// Evaluates offer against filter config for the given app (service-scoped). Uses DynamicRuleEngine for adaptive thresholds.
  static func evaluate(_ offer: OfferData, appBundleId: String) -> RideDecision {
    let service = FilterConfig.service(from: appBundleId)
    let effective = DynamicRuleEngine.shared.effectiveThresholds(idleMinutes: ProdDaemon.idleMinutesForCriteria, service: service)
    let minPrice = effective.minPrice
    let minPricePerMile = effective.minPricePerMile
    let maxPickupDistance = effective.maxPickupDistance

    if offer.price < minPrice { return .reject(reason: .belowMinPrice) }
    if offer.miles <= 0 { return .reject(reason: .belowMinPricePerMile) }
    if offer.price / offer.miles < minPricePerMile { return .reject(reason: .belowMinPricePerMile) }
    if offer.shared { return .reject(reason: .sharedRide) }
    if offer.stops > 1 { return .reject(reason: .tooManyStops) }

    if let rate = offer.estimatedHourlyRate, rate < FilterConfig.minHourlyRate(service: service) {
      return .reject(reason: .belowMinHourlyRate)
    }
    if let pickupMi = offer.pickupDistanceMiles, pickupMi > maxPickupDistance {
      return .reject(reason: .pickupTooFar)
    }
    if let rating = offer.passengerRating, rating < FilterConfig.minPassengerRating(service: service) {
      return .reject(reason: .lowPassengerRating)
    }
    if let surge = offer.surgeMultiplier, surge < FilterConfig.minSurgeMultiplier(service: service) {
      return .reject(reason: .belowSurgeThreshold)
    }
    if let rt = offer.rideType, FilterConfig.blockedRideTypes(service: service).contains(rt) {
      return .reject(reason: .blockedRideType)
    }

    let hour = Calendar.current.component(.hour, from: Date())
    let start = FilterConfig.activeHoursStart(service: service)
    let end = FilterConfig.activeHoursEnd(service: service)
    if start > end {
      if hour < start && hour > end { return .reject(reason: .timeRestriction) }
    } else {
      if hour < start || hour > end { return .reject(reason: .timeRestriction) }
    }

    if GeofenceManager.shared.shouldRejectByGeofence(pickupCoordinate: offer.pickupLocation) {
      return .reject(reason: .outsideGeofence)
    }

    let minQuality = FilterConfig.minRideQualityScore(service: service)
    if minQuality > 0 {
      let (score, _) = RidePredictor.shared.predict(offer: offer)
      if score < minQuality { return .reject(reason: .belowRideQuality) }
    }

    return .accept(reason: .meetsCriteria)
  }
}
