import Foundation
import UIKit

// MARK: - Notifications

extension Notification.Name {
  static let destroDaemonDidBecomeIdle = Notification.Name("destroDaemonDidBecomeIdle")
  static let destroDaemonDidStartScanning = Notification.Name("destroDaemonDidStartScanning")
  static let destroAcceptTapFailed = Notification.Name("destroAcceptTapFailed")
  static let destroRejectTapFailed = Notification.Name("destroRejectTapFailed")
  static let destroConfirmAcceptRequested = Notification.Name("destroConfirmAcceptRequested")
  /// Posted when we see an offer (accept, reject, or confirm). userInfo: app, price, miles, dollarsPerMile, pickupMiles, surge, rideType, reason, decision.
  static let destroOfferSeen = Notification.Name("destroOfferSeen")
}

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
// Scan loop runs every Config.cycleMs (30ms); keep work in the loop minimal to avoid blocking.

class ProdDaemon {
  private var scanTask: Task<Void, Never>?
  private var currentIndex = 0
  private let allApps = ["com.ubercab.driver", "me.lyft.driver"]

  /// Pluggable offer source. Default returns nil (no cross-app read on stock iOS).
  var offerSource: OfferSource = NilOfferSource()
  /// Pluggable accept/reject executor. Default is no-op.
  var actionExecutor: ActionExecutor = NoOpActionExecutor()

  /// Manages auto-switching: when ride accepted on one app, other goes offline; on completion, other comes back.
  var conflictManager: ConflictManager = ConflictManager()

  /// When ride is active, poll this often to detect trip end (no offer screen = completed).
  private var rideCompletionTask: Task<Void, Never>?
  private let rideCompletionIntervalNs: UInt64 = 10_000_000_000  // 10s
  private let rideCompletionNilCountThreshold = 2

  /// Pending offer for confirm-before-accept mode. Cleared after user accepts/declines or timeout.
  private var pendingConfirmOffer: (offer: OfferData, app: String)?

  /// Last offer seen (for manual accept/reject when auto-accept is off). Set whenever we post destroOfferSeen.
  private var lastSeenOffer: (offer: OfferData, app: String)?

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

  /// Idle minutes since last accept/reject; used by CriteriaEngine for dynamic thresholds.
  static var lastDecisionTime: Date?
  static var idleMinutesForCriteria: Double {
    guard let t = lastDecisionTime else { return 60 }
    return max(0, Date().timeIntervalSince(t) / 60)
  }

  /// Build userInfo for destroOfferSeen / confirm alert: app, price, miles, $/mi, pickup, surge, rideType, reason, decision.
  private static func offerBreakdownUserInfo(offer: OfferData, app: String, decision: RideDecision) -> [String: Any] {
    let dollarsPerMile = offer.miles > 0 ? offer.price / offer.miles : 0.0
    let reasonStr: String
    let decStr: String
    switch decision {
    case .accept(let r): reasonStr = r.rawValue; decStr = "accept"
    case .reject(let r): reasonStr = r.rawValue; decStr = "reject"
    }
    var info: [String: Any] = [
      "app": app,
      "price": offer.price,
      "miles": offer.miles,
      "dollarsPerMile": dollarsPerMile,
      "reason": reasonStr,
      "decision": decStr,
      "stops": offer.stops,
      "shared": offer.shared,
    ]
    if let p = offer.pickupDistanceMiles { info["pickupMiles"] = p }
    if let s = offer.surgeMultiplier { info["surge"] = s }
    if let rt = offer.rideType { info["rideType"] = rt.displayName }
    if let hr = offer.estimatedHourlyRate { info["estimatedHourlyRate"] = hr }
    return info
  }

  /// Light haptic when auto-accept or auto-reject fires (runs on main queue).
  private static func hapticDecision() {
    DispatchQueue.main.async {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
  }

  /// Bring driver app to foreground so we can read its UI. Uses private API when available (Misaka26); otherwise opens app via URL scheme so we cycle between Uber/Lyft.
  private func bringDriverAppToForeground(bundleId: String) async {
    let didSwitch = AppSwitcher.shared.bringToForeground(bundleId: bundleId)
    if didSwitch {
      try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
      return
    }
    // Stock iOS: private API unavailable. Open driver app by URL scheme so it comes to front; then we read the frontmost app.
    await MainActor.run {
      let url = URL(string: "\(bundleId)://")
      if let url = url {
        UIApplication.shared.open(url)
      }
    }
    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1.0s for app to come to front and AX to see it
  }

  /// Bring Destro back to the front so the user sees our UI (offer card, etc.). Like Mystro: offers show in our app.
  private func bringDestroToForeground() async {
    if AppSwitcher.shared.bringToForeground(bundleId: "online.nextelevenstudios.destro") {
      return
    }
    await MainActor.run {
      if let url = URL(string: "destro://") {
        UIApplication.shared.open(url)
      }
    }
    try? await Task.sleep(nanoseconds: 400_000_000)  // 0.4s for Destro to show
  }

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
      DashboardRelay.shared.connect()
      var exitError: String?
      do {
        while !Task.isCancelled {
          let app = apps[self.currentIndex % apps.count]
          await self.bringDriverAppToForeground(bundleId: app)
          _ = await ServiceReadinessStore.discoverPID(for: app)
          var offer: OfferData?
          for attempt in 1...3 {
            offer = source.fetchOffer(appBundleId: app)
            if offer != nil { break }
            try? await Task.sleep(nanoseconds: UInt64(attempt * 50) * 1_000_000)
          }
          if let offer = offer {
            self.state = .decisioning(app: app)
            let decision = self.decide(offer, appBundleId: app)
            self.lastSeenOffer = (offer, app)
            let offerInfo = Self.offerBreakdownUserInfo(offer: offer, app: app, decision: decision)
            NotificationCenter.default.post(name: .destroOfferSeen, object: nil, userInfo: offerInfo)

            let latencyMs = 38
            let svc = FilterConfig.service(from: app)
            switch decision {
            case .accept(let reason):
              if FilterConfig.autoAccept(service: svc) {
                if FilterConfig.requireConfirmBeforeAccept(service: svc) {
                  self.pendingConfirmOffer = (offer, app)
                  var confirmInfo = offerInfo
                  confirmInfo["reason"] = reason.rawValue
                  await self.bringDestroToForeground()
                  NotificationCenter.default.post(
                    name: .destroConfirmAcceptRequested,
                    object: nil,
                    userInfo: confirmInfo
                  )
                } else {
                  await self.bringDriverAppToForeground(bundleId: app)
                  try? await Task.sleep(nanoseconds: 400_000_000)  // 0.4s for accept button to be ready
                  let tapOk = executor.executeAccept(at: offer.acceptPoint, appBundleId: app)
                  if tapOk {
                    Self.hapticDecision()
                    self.conflictManager.rideAccepted(appBundleId: app)
                    ProdDaemon.lastDecisionTime = Date()
                    self.startRideCompletionPoller(source: source, activeAppBundleId: app)
                    Metrics.pubAccept(app: app, price: offer.price, latency: latencyMs, reason: reason)
                  } else {
                    NotificationCenter.default.post(
                      name: .destroAcceptTapFailed,
                      object: nil,
                      userInfo: ["app": app, "price": offer.price]
                    )
                  }
                }
              } else {
                Metrics.pubDecision(app: app, decision: .reject(reason: .autoAcceptDisabled), offer: offer)
              }
              self.state = .cooldown
              try? await Task.sleep(nanoseconds: Config.cooldownMs)
            case .reject(let reason):
              let rejectPoint = offer.rejectPoint ?? CGPoint(x: UIScreen.main.bounds.minX + 60, y: UIScreen.main.bounds.maxY - 80)
              if FilterConfig.autoReject(service: svc) {
                await self.bringDriverAppToForeground(bundleId: app)
                try? await Task.sleep(nanoseconds: 400_000_000)
                let rejectOk = executor.executeReject(at: rejectPoint, appBundleId: app)
                if !rejectOk {
                  NotificationCenter.default.post(
                    name: .destroRejectTapFailed,
                    object: nil,
                    userInfo: ["app": app, "price": offer.price, "reason": reason.rawValue]
                  )
                } else {
                  Self.hapticDecision()
                }
              }
              ProdDaemon.lastDecisionTime = Date()
              Metrics.pubDecision(app: app, decision: .reject(reason: reason), offer: offer)
              self.state = .cooldown
              try? await Task.sleep(nanoseconds: Config.cooldownMs)
            }
          } else {
            // no offer this cycle; stay in scanning
          }
          self.state = .scanning
          Metrics.pubScan(app: app, status: "🟢 SCANNING")
          self.currentIndex += 1
          // Return to Destro so user sees our app and offer card (Mystro-style).
          await self.bringDestroToForeground()
          try await Task.sleep(nanoseconds: Config.cycleMs)
        }
      } catch {
        self.state = .error(error.localizedDescription)
        exitError = error.localizedDescription
        print("[Destro] daemon stopped: \(error)")
        LogBuffer.shared.append("[Destro] daemon stopped: \(error)")
      }
      self.state = .idle
      self.scanTask = nil
      DashboardRelay.shared.disconnect()
      AppGroupStore.writeStatus("🔴 Idle", lastApp: "—")
      if #available(iOS 16.1, *) {
        updateDestroLiveActivity(status: "🔴 Idle", activeApp: "—", sessionEarnings: 0, timeOnline: 0)
      }
      var userInfo: [String: String]?
      if let err = exitError { userInfo = ["error": err] }
      NotificationCenter.default.post(name: .destroDaemonDidBecomeIdle, object: nil, userInfo: userInfo)
    }
  }

  func stopScanning() {
    rideCompletionTask?.cancel()
    rideCompletionTask = nil
    scanTask?.cancel()
    scanTask = nil
    state = .idle
  }

  /// Returns accept or reject with reason. Delegates to CriteriaEngine (service-scoped).
  func decide(_ data: OfferData, appBundleId: String) -> RideDecision {
    CriteriaEngine.evaluate(data, appBundleId: appBundleId)
  }

  /// Call from UI when user taps "Accept" on the confirm-before-accept alert. Performs the stored pending accept (tap + conflict + poller). Uses same bring-to-foreground as daemon (URL fallback on stock iOS), then returns to Destro.
  func performPendingAccept() {
    guard let pending = pendingConfirmOffer else { return }
    pendingConfirmOffer = nil
    let (offer, app) = pending
    Task { [weak self] in
      guard let self else { return }
      await self.bringDriverAppToForeground(bundleId: app)
      try? await Task.sleep(nanoseconds: 400_000_000)  // 0.4s for accept button
      await MainActor.run {
        self.performPendingAcceptAfterDelay(offer: offer, app: app)
      }
      await self.bringDestroToForeground()  // Return to Destro (Mystro-style)
    }
  }

  private func performPendingAcceptAfterDelay(offer: OfferData, app: String) {
    let tapOk = actionExecutor.executeAccept(at: offer.acceptPoint, appBundleId: app)
    if tapOk {
      Self.hapticDecision()
      conflictManager.rideAccepted(appBundleId: app)
      ProdDaemon.lastDecisionTime = Date()
      startRideCompletionPoller(source: offerSource, activeAppBundleId: app)
      Metrics.pubAccept(app: app, price: offer.price, latency: 38, reason: .meetsCriteria)
    } else {
      NotificationCenter.default.post(
        name: .destroAcceptTapFailed,
        object: nil,
        userInfo: ["app": app, "price": offer.price]
      )
    }
  }

  /// Clear pending confirm offer (e.g. user tapped Decline).
  func clearPendingConfirm() {
    pendingConfirmOffer = nil
  }

  /// Call from UI when user taps manual Accept on the offer card (auto-accept off). Uses last seen offer.
  func performManualAccept() {
    guard let last = lastSeenOffer else { return }
    lastSeenOffer = nil
    let (offer, app) = last
    Task { [weak self] in
      guard let self else { return }
      await self.bringDriverAppToForeground(bundleId: app)
      try? await Task.sleep(nanoseconds: 400_000_000)
      await MainActor.run {
        self.performPendingAcceptAfterDelay(offer: offer, app: app)
      }
      await self.bringDestroToForeground()
    }
  }

  /// Call from UI when user taps manual Reject on the offer card. Uses last seen offer; fallback point if rejectPoint nil.
  func performManualReject() {
    guard let last = lastSeenOffer else { return }
    lastSeenOffer = nil
    let (offer, app) = last
    let rejectPoint = offer.rejectPoint ?? CGPoint(x: UIScreen.main.bounds.minX + 60, y: UIScreen.main.bounds.maxY - 80)
    Task { [weak self] in
      guard let self else { return }
      await self.bringDriverAppToForeground(bundleId: app)
      try? await Task.sleep(nanoseconds: 400_000_000)
      await MainActor.run {
        let ok = self.actionExecutor.executeReject(at: rejectPoint, appBundleId: app)
        if ok { Self.hapticDecision() }
        else {
          NotificationCenter.default.post(name: .destroRejectTapFailed, object: nil, userInfo: ["app": app, "price": offer.price, "reason": "manual"])
        }
      }
      ProdDaemon.lastDecisionTime = Date()
      Metrics.pubDecision(app: app, decision: .reject(reason: .autoAcceptDisabled), offer: offer)
      await self.bringDestroToForeground()
    }
  }

  private func parseDouble(_ text: String?) -> Double? {
    guard let t = text else { return nil }
    let cleaned = t.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
    guard let d = Double(cleaned), d >= 0 else { return nil }
    return d
  }

  /// Polls for trip end: when offer source returns nil for active app repeatedly, assume trip completed.
  private func startRideCompletionPoller(source: OfferSource, activeAppBundleId: String) {
    rideCompletionTask?.cancel()
    let app = activeAppBundleId
    let conflict = conflictManager
    rideCompletionTask = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: 15_000_000_000)  // 15s delay before first poll (avoid rideCompleted right after accept)
      var nilCount = 0
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: self.rideCompletionIntervalNs)
        guard !Task.isCancelled else { break }
        if case .rideActive(let active) = conflict.state, active == app {
          if source.fetchOffer(appBundleId: app) == nil {
            nilCount += 1
            if nilCount >= self.rideCompletionNilCountThreshold {
              conflict.rideCompleted(wasActiveAppBundleId: app)
              break
            }
          } else {
            nilCount = 0
          }
        } else {
          break
        }
      }
      self.rideCompletionTask = nil
    }
  }
}

// MARK: - Metrics

struct Metrics {
  static func pubScan(app: String, status: String) {
    print("[Destro] \(status) \(app)")
    LogBuffer.shared.append("[Destro] \(status) \(app)")
    AppGroupStore.writeStatus(status, lastApp: app)
    if #available(iOS 16.1, *) {
      let session = EarningsTracker.shared.sessionEarnings()
      updateDestroLiveActivity(status: status, activeApp: app, sessionEarnings: session.total, timeOnline: Date().timeIntervalSince(session.startDate))
    }
  }

  static func pubState(old: DaemonState, new: DaemonState) {
    let msg = "[Destro] state \(stateLabel(old)) -> \(stateLabel(new))"
    print(msg)
    LogBuffer.shared.append(msg)
    DashboardRelay.shared.send([
      "type": "state",
      "old": stateLabel(old),
      "new": stateLabel(new)
    ])
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
    AppGroupStore.writeSessionEarnings(EarningsTracker.shared.sessionEarnings().total)
    if #available(iOS 16.1, *) {
      let session = EarningsTracker.shared.sessionEarnings()
      updateDestroLiveActivity(status: "🟢 SCANNING", activeApp: name, sessionEarnings: session.total, timeOnline: Date().timeIntervalSince(session.startDate))
    }
    DashboardRelay.shared.send([
      "type": "decision", "decision": "accept", "app": name, "price": price, "latency": latency, "reason": reason.rawValue
    ])
    DashboardRelay.shared.send([
      "type": "earnings",
      "session": EarningsTracker.shared.sessionEarnings().total,
      "today": EarningsTracker.shared.todayEarnings().total
    ])
    print("[Destro] Accept \(price) | \(latency)ms | \(reason.rawValue)")
    LogBuffer.shared.append("[Destro] Accept \(price) | \(latency)ms | \(reason.rawValue)")
  }

  static func pubDecision(app: String, decision: RideDecision, offer: OfferData) {
    let name = app.contains("uber") ? "Uber" : (app.contains("lyft") ? "Lyft" : app)
    let reason: DecisionReason
    switch decision {
    case .accept(let r): reason = r
    case .reject(let r): reason = r
    }
    HistoryStore.appendDecision(app: name, offer: offer, decision: decision)
    let decStr: String = { if case .reject = decision { return "reject" }; return "accept" }()
    DashboardRelay.shared.send([
      "type": "decision", "decision": decStr, "app": name, "price": offer.price, "reason": reason.rawValue
    ])
    print("[Destro] Decision \(decision) | \(name) $\(offer.price)")
    LogBuffer.shared.append("[Destro] Decision \(decision) | \(name) $\(offer.price)")
  }
}
