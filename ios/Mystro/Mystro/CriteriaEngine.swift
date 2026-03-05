import Foundation

// MARK: - CriteriaEngine
// Single source of truth for accept/reject rules. Uses FilterConfig for thresholds.

struct CriteriaEngine {
  /// Evaluates offer against current filter config; returns accept or reject with reason.
  static func evaluate(_ offer: OfferData) -> RideDecision {
    let minPrice = FilterConfig.minPrice
    let minPricePerMile = FilterConfig.minPricePerMile

    if offer.price < minPrice { return .reject(reason: .belowMinPrice) }
    if offer.miles <= 0 { return .reject(reason: .belowMinPricePerMile) }
    if offer.price / offer.miles < minPricePerMile { return .reject(reason: .belowMinPricePerMile) }
    if offer.shared { return .reject(reason: .sharedRide) }
    if offer.stops != 1 { return .reject(reason: .tooManyStops) }

    return .accept(reason: .meetsCriteria)
  }
}
