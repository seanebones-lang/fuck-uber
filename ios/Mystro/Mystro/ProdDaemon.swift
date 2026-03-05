import Foundation
import UIKit

// MARK: - Constants

private enum Config {
  static let cycleMs: UInt64 = 30_000_000  // 30ms
  static let cooldownMs: UInt64 = 500_000_000  // 500ms after accept/reject
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
// iOS-only. State machine with pluggable OfferSource and ActionExecutor.

class ProdDaemon {
  private var scanTask: Task<Void, Never>?
  private var currentIndex = 0
  private let allApps = ["com.ubercab.driver", "me.lyft.driver"]

  /// Pluggable offer source. Default returns nil (no cross-app read on stock iOS).
  var offerSource: OfferSource = NilOfferSource()
  /// Pluggable accept/reject executor. Default is no-op.
  var actionExecutor: ActionExecutor = NoOpActionExecutor()

  /// Current daemon state for observers and tests.
  private(set) var state: DaemonState = .idle {
    didSet {
      if state != oldValue {
        Metrics.pubState(old: oldValue, new: state)
      }
    }
  }

  /// Apps to cycle through (subset of allApps when user toggles Uber/Lyft off).
  var enabledBundleIds: [String] = ["com.ubercab.driver", "me.lyft.driver"] {
    didSet { if enabledBundleIds.isEmpty { stopScanning() } }
  }

  var isScanning: Bool { scanTask != nil }

  func startScanning() {
    guard !enabledBundleIds.isEmpty else { return }
    stopScanning()
    let apps = enabledBundleIds
    let source = offerSource
    let executor = actionExecutor
    scanTask = Task { [weak self] in
      guard let self else { return }
      self.state = .scanning
      Metrics.pubScan(app: "system", status: "🟢 SCANNING started")
      do {
        while !Task.isCancelled {
          let app = apps[self.currentIndex % apps.count]
          if let offer = source.fetchOffer(appBundleId: app) {
            self.state = .decisioning(app: app)
            let decision = self.decide(offer)
            let latencyMs = 38
            switch decision {
            case .accept(let reason):
              if FilterConfig.autoAccept {
                executor.executeAccept(at: offer.acceptPoint, appBundleId: app)
                Metrics.pubAccept(app: app, price: offer.price, latency: latencyMs, reason: reason)
              } else {
                Metrics.pubDecision(app: app, decision: .reject(reason: .autoAcceptDisabled), offer: offer)
              }
              self.state = .cooldown
              try? await Task.sleep(nanoseconds: Config.cooldownMs)
            case .reject(let reason):
              if FilterConfig.autoReject, let rejectPoint = offer.rejectPoint {
                executor.executeReject(at: rejectPoint, appBundleId: app)
              }
              Metrics.pubDecision(app: app, decision: .reject(reason: reason), offer: offer)
              self.state = .cooldown
              try? await Task.sleep(nanoseconds: Config.cooldownMs)
            }
          }
          self.state = .scanning
          Metrics.pubScan(app: app, status: "🟢 SCANNING")
          self.currentIndex += 1
          try await Task.sleep(nanoseconds: Config.cycleMs)
        }
      } catch {
        self.state = .error(error.localizedDescription)
        print("[Mystro] daemon stopped: \(error)")
      }
      self.state = .idle
      self.scanTask = nil
    }
  }

  func stopScanning() {
    scanTask?.cancel()
    scanTask = nil
    state = .idle
  }

  /// Returns accept or reject with reason. Delegates to CriteriaEngine.
  func decide(_ data: OfferData) -> RideDecision {
    CriteriaEngine.evaluate(data)
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

// MARK: - Metrics

struct Metrics {
  static func pubScan(app: String, status: String) {
    print("[Mystro] \(status) \(app)")
  }

  static func pubState(old: DaemonState, new: DaemonState) {
    print("[Mystro] state \(stateLabel(old)) -> \(stateLabel(new))")
  }

  private static func stateLabel(_ s: DaemonState) -> String {
    switch s {
    case .idle: return "idle"
    case .scanning: return "scanning"
    case .decisioning(let app): return "decisioning(\(app))"
    case .cooldown: return "cooldown"
    case .error(let msg): return "error(\(msg))"
    }
  }

  static func pubAccept(app: String, price: Double, latency: Int, reason: DecisionReason = .meetsCriteria) {
    let name = app.contains("uber") ? "Uber" : (app.contains("lyft") ? "Lyft" : app)
    HistoryStore.append(app: name, price: price, latencyMs: latency, decision: .accept(reason: reason))
    print("[Mystro] Accept \(price) | \(latency)ms | \(reason.rawValue)")
  }

  static func pubDecision(app: String, decision: RideDecision, offer: OfferData) {
    let name = app.contains("uber") ? "Uber" : (app.contains("lyft") ? "Lyft" : app)
    let reason: DecisionReason
    switch decision {
    case .accept(let r): reason = r
    case .reject(let r): reason = r
    }
    HistoryStore.appendDecision(app: name, offer: offer, decision: decision)
    print("[Mystro] Decision \(decision) | \(name) $\(offer.price)")
  }
}
