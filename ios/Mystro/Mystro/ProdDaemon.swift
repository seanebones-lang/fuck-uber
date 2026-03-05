import Foundation
import UIKit

// MARK: - Constants

private enum Config {
  static let cycleMs: UInt64 = 30_000_000  // 30ms
  static let minPrice: Double = 7.0
  static let minPricePerMile: Double = 0.90
  static let tapHoldUs: UInt32 = 50_000
  static let tapDelayUsMin: UInt32 = 100_000
  static let tapDelayUsMax: UInt32 = 300_000
  static let tapJitter: ClosedRange<CGFloat> = -15...15
}

private enum AppKind {
  case uber
  case lyft

  var acceptButtonID: String {
    switch self {
    case .uber: return "trip-accept-btn"
    case .lyft: return "accept_ride_button"
    }
  }

  static func from(bundleId: String) -> AppKind {
    bundleId.contains("uber") ? .uber : .lyft
  }
}

// MARK: - ProdDaemon
// iOS-only. Run loop for enabled services; start/stop via GO button. Plug in scrape/tap when you have Accessibility client.

class ProdDaemon {
  private var scanTask: Task<Void, Never>?
  private var currentIndex = 0
  private let allApps = ["com.ubercab.driver", "me.lyft.driver"]

  /// Apps to cycle through (subset of allApps when user toggles Uber/Lyft off).
  var enabledBundleIds: [String] = ["com.ubercab.driver", "me.lyft.driver"] {
    didSet { if enabledBundleIds.isEmpty { stopScanning() } }
  }

  var isScanning: Bool { scanTask != nil }

  func startScanning() {
    guard !enabledBundleIds.isEmpty else { return }
    stopScanning()
    let apps = enabledBundleIds
    scanTask = Task { [weak self] in
      guard let self else { return }
      do {
        Metrics.pubScan(app: "system", status: "🟢 SCANNING started")
        while !Task.isCancelled {
          let app = apps[self.currentIndex % apps.count]
          if let data = self.scrapeOffer(app: app) {
            if self.fixedCriteria(data) {
              self.fastTap(data.acceptPoint)
              Metrics.pubAccept(app: app, price: data.price, latency: 38)
            }
          }
          Metrics.pubScan(app: app, status: "🟢 SCANNING")
          self.currentIndex += 1
          try await Task.sleep(nanoseconds: Config.cycleMs)
        }
      } catch {
        print("[Mystro] daemon stopped: \(error)")
      }
      self.scanTask = nil
    }
  }

  func stopScanning() {
    scanTask?.cancel()
    scanTask = nil
  }

  /// On iOS we can't read another app's UI with public API. Return offer when you have an iOS scrape (e.g. Accessibility client).
  private func scrapeOffer(app: String) -> OfferData? {
    _ = findPID(bundle: app)  // optional: use PID if you have it (e.g. from Accessibility or config)
    return nil
  }

  private func fixedCriteria(_ data: OfferData) -> Bool {
    let minP = FilterConfig.minPrice
    let minPerMile = FilterConfig.minPricePerMile
    return data.price >= minP
      && (data.miles > 0 && data.price / data.miles >= minPerMile)
      && !data.shared
      && data.stops == 1
  }

  /// On iOS, tap simulation would use whatever API your Accessibility/client provides.
  private func fastTap(_ point: CGPoint) {
    guard FilterConfig.autoAccept else { return }
    _ = point
  }

  /// PID for driver app. iOS can't enumerate other apps' PIDs; set mystro.pid.<bundle> in UserDefaults if you have it from elsewhere.
  private func findPID(bundle: String) -> pid_t? {
    let key = "mystro.pid.\(bundle)"
    let stored = UserDefaults.standard.object(forKey: key) as? Int32
    return stored.flatMap { pid_t(exactly: $0) }
  }

  private func parseDouble(_ text: String?) -> Double? {
    guard let t = text else { return nil }
    let cleaned = t.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
    guard let d = Double(cleaned), d >= 0 else { return nil }
    return d
  }
}

// MARK: - Models

struct OfferData {
  let price: Double
  let miles: Double
  let shared: Bool
  let stops: Int
  let acceptPoint: CGPoint
}

struct Metrics {
  static func pubScan(app: String, status: String) {
    print("[Mystro] \(status) \(app)")
  }

  static func pubAccept(app: String, price: Double, latency: Int) {
    let name = app.contains("uber") ? "Uber" : (app.contains("lyft") ? "Lyft" : app)
    HistoryStore.append(app: name, price: price, latencyMs: latency)
    print("[Mystro] Accept \(price) | \(latency)ms")
  }
}
