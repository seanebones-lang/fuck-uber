import Foundation
import UIKit

// MARK: - AccessibilityOfferSource
// Uses private Accessibility APIs (AXUIElement*) to read the target app's UI hierarchy.
// Requires PID for the driver app in UserDefaults key "destro.pid.<bundleId>" on jailbroken iOS.

final class AccessibilityOfferSource: OfferSource {

  private let pidProvider: (String) -> pid_t?

  init(pidProvider: @escaping (String) -> pid_t? = AccessibilityOfferSource.defaultPidProvider) {
    self.pidProvider = pidProvider
  }

  private static func defaultPidProvider(bundleId: String) -> pid_t? {
    ServiceReadinessStore.storedPID(bundleId: bundleId)
  }

  func fetchOffer(appBundleId: String) -> OfferData? {
    guard let pid = pidProvider(appBundleId) else { return nil }
    return AXOfferParser.parse(pid: pid, bundleId: appBundleId)
  }
}

// MARK: - AX Parser (Private API Loader)

private enum AXOfferParser {

  private static let kAXRoleAttribute = "AXRole" as CFString
  private static let kAXTitleAttribute = "AXTitle" as CFString
  private static let kAXValueAttribute = "AXValue" as CFString
  private static let kAXFrameAttribute = "AXFrame" as CFString
  private static let kAXChildrenAttribute = "AXChildren" as CFString
  private static let kAXRoleButton = "AXButton" as CFString

  static func parse(pid: pid_t, bundleId: String) -> OfferData? {
    guard AXLoader.shared.load(), let appElement = AXLoader.shared.createApplication(pid) else { return nil }
    let ax = AXLoader.shared
    defer { ax.release(appElement) }

    var price: Double?
    var miles: Double = 1
    var shared = false
    var stops = 1
    var acceptPoint: CGPoint = .zero
    var rejectPoint: CGPoint?
    var surgeMultiplier: Double?
    var passengerRating: Double?
    var rideType: RideType?
    var pickupDistanceMiles: Double?
    var collectedText: [String] = []

    let screenScale = UIScreen.main.scale
    func traverse(_ element: AXUIElementRef) {
      if let title = ax.copyAttributeString(element, kAXTitleAttribute) {
        let t = title as String
        collectedText.append(t)
        if price == nil, let p = parsePrice(t) { price = p }
        if let m = parseMiles(t) { miles = m }
        if t.lowercased().contains("shared") { shared = true }
        if let s = parseStops(t) { stops = s }
        if surgeMultiplier == nil, let s = parseSurge(t) { surgeMultiplier = s }
        if passengerRating == nil, let r = parseRating(t) { passengerRating = r }
        if pickupDistanceMiles == nil, let d = parsePickupDistance(t) { pickupDistanceMiles = d }
      }
      if let value = ax.copyAttributeString(element, kAXValueAttribute) {
        let t = value as String
        collectedText.append(t)
        if price == nil, let p = parsePrice(t) { price = p }
        if let m = parseMiles(t) { miles = m }
        if surgeMultiplier == nil, let s = parseSurge(t) { surgeMultiplier = s }
        if passengerRating == nil, let r = parseRating(t) { passengerRating = r }
        if pickupDistanceMiles == nil, let d = parsePickupDistance(t) { pickupDistanceMiles = d }
      }
      if let role = ax.copyAttributeString(element, kAXRoleAttribute), (role as String) == "AXButton" {
        if let frame = ax.copyAttributeFrame(element) {
          let center = CGPoint(x: frame.midX / screenScale, y: frame.midY / screenScale)
          let label = (ax.copyAttributeString(element, kAXTitleAttribute) as String?) ?? ""
          if label.lowercased().contains("accept") {
            acceptPoint = center
          } else if label.lowercased().contains("decline") || label.lowercased().contains("reject") {
            rejectPoint = center
          }
        }
      }
      if let children = ax.copyAttributeArray(element, kAXChildrenAttribute) {
        for child in children {
          traverse(child)
        }
      }
    }

    traverse(appElement)

    guard let p = price, p > 0 else { return nil }
    // Fallback accept point (typical bottom-center for Uber/Lyft) when AXFrame unavailable (e.g. Misaka26 partial AX)
    if acceptPoint == .zero {
      let bounds = UIScreen.main.bounds
      acceptPoint = CGPoint(x: bounds.midX, y: bounds.maxY - 80)
    }

    if rideType == nil {
      rideType = parseRideType(from: collectedText.joined(separator: " "), bundleId: bundleId)
    }
    let estMiles = miles > 0 ? miles : 1
    let estimatedHourlyRate: Double? = (estMiles > 0 && p > 0) ? (p / (estMiles / 30.0)) : nil

    return OfferData(
      price: p,
      miles: estMiles,
      shared: shared,
      stops: stops,
      acceptPoint: acceptPoint,
      rejectPoint: rejectPoint,
      pickupLocation: nil,
      dropoffLocation: nil,
      estimatedMinutes: nil,
      passengerRating: passengerRating,
      surgeMultiplier: surgeMultiplier,
      rideType: rideType,
      pickupDistanceMiles: pickupDistanceMiles,
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

// MARK: - AX Loader (dlopen Private Framework)

private typealias AXUIElementRef = OpaquePointer

private final class AXLoader {
  static let shared = AXLoader()

  private var handle: UnsafeMutableRawPointer?
  private var _createApplication: ((pid_t) -> AXUIElementRef?)?
  private var _copyAttributeValue: ((AXUIElementRef, CFString) -> CFTypeRef?)?
  private var _release: ((AXUIElementRef) -> Void)?

  private init() {}

  func load() -> Bool {
    if handle != nil { return true }
    let path = "/System/Library/PrivateFrameworks/Accessibility.framework/Accessibility"
    guard let h = dlopen(path, RTLD_NOW) else { return false }
    handle = h

    typealias CreateApp = @convention(c) (pid_t) -> AXUIElementRef?
    typealias CopyAttr = @convention(c) (AXUIElementRef, CFString, UnsafeMutablePointer<CFTypeRef?>) -> Int32
    typealias Release = @convention(c) (AXUIElementRef) -> Void

    guard let createApp = dlsym(h, "AXUIElementCreateApplication") else { return false }
    _createApplication = { pid in
      let f = unsafeBitCast(createApp, to: CreateApp.self)
      return f(pid)
    }

    guard let copyAttrPtr = dlsym(h, "AXUIElementCopyAttributeValue") else { return false }
    let copyAttrFn = unsafeBitCast(copyAttrPtr, to: CopyAttr.self)
    _copyAttributeValue = { elem, attr in
      var result: CFTypeRef?
      guard copyAttrFn(elem, attr, &result) == 0, let ref = result else { return nil }
      return ref
    }

    guard let rel = dlsym(h, "AXUIElementRelease") else { return false }
    _release = { elem in
      let f = unsafeBitCast(rel, to: Release.self)
      f(elem)
    }

    return true
  }

  func createApplication(_ pid: pid_t) -> AXUIElementRef? {
    _createApplication?(pid)
  }

  func release(_ element: AXUIElementRef) {
    _release?(element)
  }

  func copyAttributeString(_ element: AXUIElementRef, _ attr: CFString) -> String? {
    guard let value = _copyAttributeValue?(element, attr) else { return nil }
    return (value as? NSString).map { $0 as String }
  }

  func copyAttributeFrame(_ element: AXUIElementRef) -> CGRect? {
    guard let value = _copyAttributeValue?(element, "AXFrame" as CFString) else { return nil }
    guard CFGetTypeID(value as CFTypeRef) == CFDictionaryGetTypeID() else { return nil }
    let dict = unsafeBitCast(value, to: CFDictionary.self)
    let d = dict as NSDictionary
    guard let x = d["x"] as? CGFloat, let y = d["y"] as? CGFloat,
          let w = d["width"] as? CGFloat, let h = d["height"] as? CGFloat else { return nil }
    return CGRect(x: x, y: y, width: w, height: h)
  }

  func copyAttributeArray(_ element: AXUIElementRef, _ attr: CFString) -> [AXUIElementRef]? {
    guard let value = _copyAttributeValue?(element, attr) else { return nil }
    guard CFGetTypeID(value as CFTypeRef) == CFArrayGetTypeID() else { return nil }
    let arr = unsafeBitCast(value, to: CFArray.self)
    var result: [AXUIElementRef] = []
    for i in 0..<CFArrayGetCount(arr) {
      guard let ptr = CFArrayGetValueAtIndex(arr, i) else { continue }
      let ref = ptr.assumingMemoryBound(to: AXUIElementRef.self).pointee
      result.append(ref)
    }
    return result
  }
}
