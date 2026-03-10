import Foundation
import CoreLocation
import CoreML

// MARK: - RidePredictor
// On-device ride quality scoring. Uses CoreML model when RidePredictorModel.mlmodel is added to the target; otherwise heuristic.
// Model inputs (optional): price, miles, surge, timeOfDay (0–23), pickupZoneHash. Outputs: qualityScore (0–1), predictedEarnings.

final class RidePredictor {

  static let shared = RidePredictor()

  private static let modelName = "RidePredictorModel"

  private var cachedModel: MLModel?

  private init() {}

  /// Returns a quality score 0...1 and predicted earnings. Uses CoreML if model is present.
  func predict(offer: OfferData) -> (score: Double, predictedEarnings: Double) {
    if let (score, earnings) = predictWithModel(offer) {
      return (score, earnings)
    }
    return heuristicPredict(offer: offer)
  }

  /// CoreML path: load compiled model from bundle and run prediction.
  private func predictWithModel(_ offer: OfferData) -> (score: Double, predictedEarnings: Double)? {
    guard let model = loadModel() else { return nil }
    let hour = Double(Calendar.current.component(.hour, from: Date()))
    let surge = offer.surgeMultiplier ?? 1.0
    let zoneHash = pickupZoneHash(offer.pickupLocation)
    let inputs: [String: Any] = [
      "price": offer.price,
      "miles": offer.miles,
      "surge": surge,
      "timeOfDay": hour,
      "pickupZoneHash": zoneHash
    ]
    guard let provider = try? MLDictionaryFeatureProvider(dictionary: inputs),
          let out = try? model.prediction(from: provider) else { return nil }
    let score = out.featureValue(for: "qualityScore")?.doubleValue ?? 0.5
    let earnings = out.featureValue(for: "predictedEarnings")?.doubleValue ?? offer.price * surge
    return (max(0, min(1, score)), max(0, earnings))
  }

  private func loadModel() -> MLModel? {
    if let m = cachedModel { return m }
    guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc")
      ?? Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodel") else { return nil }
    let config = MLModelConfiguration()
    do {
      let model = try MLModel(contentsOf: url, configuration: config)
      cachedModel = model
      return model
    } catch {
      print("[Destro] RidePredictor failed to load model: \(error.localizedDescription)")
      return nil
    }
  }

  /// Simple hash for zone (so model can learn area-specific quality). 0 if no pickup.
  private func pickupZoneHash(_ coord: CLLocationCoordinate2D?) -> Double {
    guard let c = coord else { return 0 }
    let lat = Int(round(c.latitude * 100))
    let lon = Int(round(c.longitude * 100))
    return Double((lat * 31 &+ lon) & 0xFFFF)
  }

  /// Fallback when no model or prediction fails.
  private func heuristicPredict(offer: OfferData) -> (score: Double, predictedEarnings: Double) {
    let dollarsPerMile = offer.miles > 0 ? offer.price / offer.miles : 0
    let surge = offer.surgeMultiplier ?? 1.0
    let rawScore = min(1.0, dollarsPerMile / 2.0 * surge)
    let score = max(0, rawScore)
    let predicted = offer.price * surge
    return (score, predicted)
  }

  /// ETA to pickup in minutes (placeholder; use MKDirections in a real implementation).
  func estimatedMinutesToPickup(pickup: CLLocationCoordinate2D?, from current: CLLocation?) -> Double? {
    guard let p = pickup, let c = current else { return nil }
    let dest = CLLocation(latitude: p.latitude, longitude: p.longitude)
    let distanceMeters = c.distance(from: dest)
    let metersPerMinute = 500.0
    return distanceMeters / metersPerMinute
  }
}
