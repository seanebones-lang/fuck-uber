import Foundation
import UIKit
import Accessibility

class ProdDaemon {
  private var currentIndex = 0
  private let apps = ["com.ubercab.driver", "me.lyft.driver"]
  private let cycleMs: UInt64 = 30_000_000  // 30ms nanos

  func startScanning() {
    Task {
      while true {
        let app = apps[currentIndex]
        if let data = scrapeOffer(app: app) {
          if fixedCriteria(data) {
            fastTap(data.acceptPoint)
            Metrics.pubAccept(price: data.price, latency: 38)  // IPC dashboard
          }
        }
        Metrics.pubScan(app: app, status: "🟢 SCANNING")  // Indicators
        currentIndex = (currentIndex + 1) % apps.count
        try? await Task.sleep(nanoseconds: cycleMs)
      }
    }
  }

  private func scrapeOffer(app: String) -> OfferData? {
    // AXUIElement query Uber/Lyft PID → Traverse hierarchy
    guard let pid = findPID(bundle: app),
          let axApp = AXUIElementCreateApplication(pid) else { return nil }
    let priceText = getAttribute(axApp, "price_label") ?? getAttribute(axApp, "fare_estimate_text")
    let milesText = getAttribute(axApp, "distance_text") ?? getAttribute(axApp, "route_distance")
    let shared = (getAttribute(axApp, "shared_ride_tag") ?? "").contains("Shared")
    let stopsText = getAttribute(axApp, "waypoint_count") ?? "1"
    let price = parseDouble(priceText) ?? 0
    let miles = parseDouble(milesText) ?? 1
    let stops = Int(stopsText.components(separatedBy: " ").first ?? "1") ?? 1
    let acceptBtn = findElement(axApp, id: app == "uber" ? "trip-accept-btn" : "accept_ride_button")
    return OfferData(price: price, miles: miles, shared: shared, stops: stops, acceptPoint: acceptBtn?.frame.origin ?? .zero)
  }

  private func fixedCriteria(_ data: OfferData) -> Bool {
    return data.price >= 7.0 && (data.price / data.miles >= 0.90) && !data.shared && data.stops == 1
  }

  private func fastTap(_ point: CGPoint) {
    let randX = point.x + CGFloat.random(in: -15...15)
    let randY = point.y + CGFloat.random(in: -15...15)
    let location = CGPoint(x: randX, y: randY)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    usleep(50_000)  // 50ms hold
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)
    up?.post(tap: .cghidEventTap)
    usleep(UInt32.random(in: 100_000...300_000))  // Human delay
  }

  private func getAttribute(_ element: AXUIElement, _ key: String) -> String? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, key as CFString, &value)
    return value.flatMap { String($0 as! String) }
  }

  private func findElement(_ root: AXUIElement, id: String) -> AXUIElement? {
    // Recursive findAccessibilityElement
    return nil  // Stub - full impl in prod
  }

  private func findPID(bundle: String) -> pid_t? {
    // NSWorkspace runningApplications filter
    return 1234  // Stub
  }

  private func parseDouble(_ text: String?) -> Double? {
    return Double(text?.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression) ?? "0") ?? nil
  }
}

struct OfferData {
  let price: Double
  let miles: Double
  let shared: Bool
  let stops: Int
  let acceptPoint: CGPoint
}

struct Metrics {
  static func pubScan(app: String, status: String) {
    // IPC to dashboard via NSUserDefaults or pipe
    print("[Mystro] \(status) \(app)")
  }

  static func pubAccept(price: Double, latency: Int) {
    print("[Mystro] Accept \(price) | \(latency)ms")
  }
}