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
    return parseImage(cgImage, screenScale: image?.scale ?? UIScreen.main.scale)
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

  private func parseImage(_ image: CGImage, screenScale: CGFloat) -> OfferData? {
    var result: OfferData?
    let request = VNRecognizeTextRequest { request, error in
      guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else { return }
      let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
      result = self.parseText(text, screenScale: screenScale)
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

  private func parseText(_ text: String, screenScale: CGFloat) -> OfferData? {
    guard let price = Self.parsePrice(text) else { return nil }
    let miles = Self.parseMiles(text) ?? 1
    let shared = text.lowercased().contains("shared")
    let stops = Self.parseStops(text) ?? 1
    let bounds = UIScreen.main.bounds
    let acceptPoint = CGPoint(x: bounds.midX, y: bounds.maxY - 80)
    let rejectPoint = CGPoint(x: bounds.minX + 60, y: bounds.maxY - 80)
    return OfferData(
      price: price,
      miles: miles > 0 ? miles : 1,
      shared: shared,
      stops: stops,
      acceptPoint: acceptPoint,
      rejectPoint: rejectPoint
    )
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
