import Foundation
import UIKit
import Vision

// MARK: - VisionOfferSource
// Fallback OfferSource using Vision framework OCR. Works when:
// - Misaka26/exposed private API provides screen capture (IOSurface, UIGetScreenImage, etc.), or
// - Our app is in foreground and we snapshot our own window (e.g. overlay mode).
// Parses Uber/Lyft offer card text via VNRecognizeTextRequest and regex.

final class VisionOfferSource: OfferSource {

  /// Optional: inject screen image. If nil, attempts private capture (jailbreak/Misaka26).
  var screenCaptureProvider: (() -> UIImage?)?

  init(screenCaptureProvider: (() -> UIImage?)? = nil) {
    self.screenCaptureProvider = screenCaptureProvider
  }

  func fetchOffer(appBundleId: String) -> OfferData? {
    let image: UIImage?
    if let provider = screenCaptureProvider {
      image = provider()
    } else {
      image = captureScreenPrivate()
    }
    guard let cgImage = image?.cgImage else { return nil }
    return parseImage(cgImage, screenScale: image?.scale ?? UIScreen.main.scale, bundleId: appBundleId)
  }

  /// Attempt private API screen capture (Misaka26 / jailbreak). Returns nil on stock iOS.
  private func captureScreenPrivate() -> UIImage? {
    typealias UIGetScreenImageFn = @convention(c) () -> UnsafeMutableRawPointer?
    let handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW)
      ?? dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_NOW)
    guard let h = handle,
          let sym = dlsym(h, "UIGetScreenImage") else { return nil }
    let fn = unsafeBitCast(sym, to: UIGetScreenImageFn.self)
    guard let ptr = fn() else { return nil }
    let cgImage = Unmanaged<CGImage>.fromOpaque(ptr).takeUnretainedValue()
    return UIImage(cgImage: cgImage)
  }

  private func parseImage(_ image: CGImage, screenScale: CGFloat, bundleId: String) -> OfferData? {
    var result: OfferData?
    let request = VNRecognizeTextRequest { request, error in
      guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else { return }
      let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
      result = self.parseText(text, screenScale: screenScale, bundleId: bundleId)
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      print("[Destro] VisionOfferSource OCR perform failed: \(error.localizedDescription)")
    }
    return result
  }

  private func parseText(_ text: String, screenScale: CGFloat, bundleId: String) -> OfferData? {
    guard let price = Self.parsePrice(text) else { return nil }
    let miles = Self.parseMiles(text) ?? 1
    let shared = text.lowercased().contains("shared")
    let stops = Self.parseStops(text) ?? 1
    let surge = Self.parseSurge(text)
    let rating = Self.parseRating(text)
    let pickupMi = Self.parsePickupDistance(text)
    let rideType = Self.parseRideType(from: text, bundleId: bundleId)
    let estMiles = miles > 0 ? miles : 1
    let estimatedHourlyRate: Double? = (estMiles > 0 && price > 0) ? (price / (estMiles / 30.0)) : nil
    let bounds = UIScreen.main.bounds
    let acceptPoint = CGPoint(x: bounds.midX, y: bounds.maxY - 80)
    let rejectPoint = CGPoint(x: bounds.minX + 60, y: bounds.maxY - 80)
    return OfferData(
      price: price,
      miles: estMiles,
      shared: shared,
      stops: stops,
      acceptPoint: acceptPoint,
      rejectPoint: rejectPoint,
      pickupLocation: nil,
      dropoffLocation: nil,
      estimatedMinutes: nil,
      passengerRating: rating,
      surgeMultiplier: surge,
      rideType: rideType,
      pickupDistanceMiles: pickupMi,
      estimatedHourlyRate: estimatedHourlyRate
    )
  }

  private static func parseSurge(_ text: String) -> Double? {
    let pattern = #"(\d+(?:\.\d+)?)\s*[x×]"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return Double(text[range])
  }

  private static func parseRating(_ text: String) -> Double? {
    let pattern = #"(?:rating|rider)?\s*(\d+(?:\.\d+)?)\s*(?:rating|stars?)?"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text),
          let v = Double(text[range]), v >= 1, v <= 5 else { return nil }
    return v
  }

  private static func parsePickupDistance(_ text: String) -> Double? {
    let pattern = #"(\d+(?:\.\d+)?)\s*mi(?:les)?\s*(?:away|to\s*pickup|to\s*passenger)?"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return Double(text[range])
  }

  private static func parseRideType(from text: String, bundleId: String) -> RideType? {
    let lower = text.lowercased()
    if bundleId.contains("uber") {
      if lower.contains("uber black") || lower.contains("black") { return .uberBlack }
      if lower.contains("uber xl") || lower.contains("uberxl") || lower.contains(" xl ") { return .uberXL }
      if lower.contains("uberx") || lower.contains("uber x") { return .uberX }
    }
    if bundleId.contains("lyft") {
      if lower.contains("lyft lux") || lower.contains("lux") { return .lyftLux }
      if lower.contains("lyft xl") || lower.contains("lyftxl") { return .lyftXL }
      if lower.contains("lyft standard") || lower.contains("standard") { return .lyftStandard }
    }
    return nil
  }

  private static func parsePrice(_ text: String) -> Double? {
    let pattern = #"\$\s*(\d+(?:\.\d+)?)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return Double(text[range])
  }

  private static func parseMiles(_ text: String) -> Double? {
    let pattern = #"(\d+(?:\.\d+)?)\s*mi"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return Double(text[range])
  }

  private static func parseStops(_ text: String) -> Int? {
    let pattern = #"(\d+)\s*stops?"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return Int(text[range])
  }
}
