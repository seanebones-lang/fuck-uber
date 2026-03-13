import UIKit

// MARK: - Constants

private enum DestroUI {
  static let backgroundColor = UIColor(white: 0.06, alpha: 1)
  static let cardBackground = UIColor(white: 0.12, alpha: 1)
  static let accentOrange = UIColor(red: 1, green: 0.42, blue: 0, alpha: 1)
  static let connectedGreen = UIColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
  static let textPrimary = UIColor.white
  static let textSecondary = UIColor(white: 0.65, alpha: 1)
  static let cornerRadius: CGFloat = 12
  static let version = "2026.2.23.861"
}

private enum OfferBreakdownStyle {
  case card(decision: String)
  case alert
}

private func formatOfferBreakdown(info: [String: Any], style: OfferBreakdownStyle) -> String {
  let appDefault: String
  switch style {
  case .card: appDefault = "—"
  case .alert: appDefault = "App"
  }
  let app = (info["app"] as? String).map { $0.contains("uber") ? "Uber" : "Lyft" } ?? appDefault
  let price = info["price"] as? Double ?? 0
  let miles = info["miles"] as? Double ?? 0
  let dollarsPerMile = info["dollarsPerMile"] as? Double ?? 0
  let pickupMiles = info["pickupMiles"] as? Double
  let surge = info["surge"] as? Double
  let rideType = info["rideType"] as? String
  let reason = (info["reason"] as? String ?? "").replacingOccurrences(of: "_", with: " ")

  switch style {
  case .card(let decision):
    var lines = [
      "\(app) · $\(String(format: "%.2f", price))",
      "\(String(format: "%.1f", miles)) mi · $\(String(format: "%.2f", dollarsPerMile))/mi",
    ]
    if let p = pickupMiles { lines.append("Pickup: \(String(format: "%.1f", p)) mi") }
    if let s = surge, s != 1.0 { lines.append("Surge: \(String(format: "%.1fx", s))") }
    if let rt = rideType, !rt.isEmpty { lines.append(rt) }
    lines.append("→ \(decision): \(reason)")
    return lines.joined(separator: "\n")
  case .alert:
    var message = String(format: "$%.2f from %@", price, app)
    if miles > 0 { message += String(format: "\n%.1f mi · $%.2f/mi", miles, dollarsPerMile) }
    if let p = pickupMiles { message += String(format: "\nPickup: %.1f mi", p) }
    if let s = surge, s != 1.0 { message += String(format: "\nSurge: %.1fx", s) }
    if let rt = rideType, !rt.isEmpty { message += "\n\(rt)" }
    if !reason.isEmpty { message += "\n(\(reason))" }
    return message
  }
}

// MARK: - Dashboard

@MainActor
final class DashboardViewController: UIViewController {

  private var uberEnabled = true
  private var lyftEnabled = true
  private var isOnline = false

  private let scrollView = UIScrollView()
  private let stack = UIStackView()
  private let enabledLabel = UILabel()
  private let uberCard = ServiceCard(service: "Uber", bundleId: "com.ubercab.driver")
  private let lyftCard = ServiceCard(service: "Lyft", bundleId: "me.lyft.driver")
  private let unlinkedLabel = UILabel()
  private let didiCard = UnlinkedServiceCard(service: "DiDi")
  private let doorDashCard = UnlinkedServiceCard(service: "DoorDash")
  private let statusLabel = UILabel()
  private let goButton = UIButton(type: .system)
  private let goHintLabel = UILabel()
  private let driveTab = UIButton(type: .system)
  private let historyTab = UIButton(type: .system)
  private let earningsLabel = UILabel()
  private let dailyGoalLabel = UILabel()
  private let conflictLabel = UILabel()
  private let relayConnectionLabel = UILabel()
  private let rushHourLabel = UILabel()
  private let setupBannerLabel = UILabel()
  private let setPIDsButton = UIButton(type: .system)
  private let imBackButton = UIButton(type: .system)
  private var currentRideActiveApp: String?
  private var earningsTimer: Timer?
  private var didPromptResumeThisLaunch = false
  private var lastOfferBreakdownText: String?
  private var lastSeenOfferApp: String?
  private let offerBreakdownLabel = UILabel()
  private let offerSectionContainer = UIView()
  private let manualAcceptButton = UIButton(type: .system)
  private let manualRejectButton = UIButton(type: .system)
  private var offerManualButtonsRow: UIStackView?

  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = DestroUI.backgroundColor
    loadState()
    setupHeader()
    setupScrollContent()
    setupBottomBar()
    updateStatusText()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(daemonDidBecomeIdle(_:)),
      name: .destroDaemonDidBecomeIdle,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(acceptTapFailed(_:)),
      name: .destroAcceptTapFailed,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(rejectTapFailed(_:)),
      name: .destroRejectTapFailed,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(relayConnectionDidChange(_:)),
      name: .destroDashboardRelayConnectionDidChange,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(confirmAcceptRequested(_:)),
      name: .destroConfirmAcceptRequested,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(offerSeen(_:)),
      name: .destroOfferSeen,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(daemonDidStartScanning(_:)),
      name: .destroDaemonDidStartScanning,
      object: nil
    )
  }

  @objc private func daemonDidStartScanning(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isOnline = true
      self.updateStatusText()
      self.refreshEarningsAndConflict()
    }
  }

  @objc private func offerSeen(_ notification: Notification) {
    guard let info = notification.userInfo as? [String: Any] else { return }
    lastSeenOfferApp = info["app"] as? String
    let decision = info["decision"] as? String ?? ""
    lastOfferBreakdownText = formatOfferBreakdown(info: info, style: .card(decision: decision))
    DispatchQueue.main.async { [weak self] in
      self?.updateOfferBreakdownDisplay()
    }
  }

  private func updateOfferBreakdownDisplay() {
    if isOnline {
      offerSectionContainer.isHidden = false
      if let text = lastOfferBreakdownText, !text.isEmpty {
        offerBreakdownLabel.text = text
        offerBreakdownLabel.textColor = DestroUI.textPrimary
        let app = lastSeenOfferApp ?? "com.ubercab.driver"
        let showManual = !FilterConfig.autoAccept(service: FilterConfig.service(from: app))
        offerManualButtonsRow?.isHidden = !showManual
      } else {
        offerBreakdownLabel.text = "No offer detected.\nDestro cycles between Uber and Lyft; when a request appears it will show here."
        offerBreakdownLabel.textColor = DestroUI.textSecondary
        offerManualButtonsRow?.isHidden = true
      }
    } else {
      offerSectionContainer.isHidden = true
    }
  }

  @objc private func confirmAcceptRequested(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let info = (notification.userInfo as? [String: Any]) ?? [:]
      let message = formatOfferBreakdown(info: info, style: .alert)
      let alert = UIAlertController(
        title: "Accept ride?",
        message: message,
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "Decline", style: .cancel) { _ in
        DaemonHolder.shared.daemon?.clearPendingConfirm()
      })
      alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
        DaemonHolder.shared.daemon?.performPendingAccept()
        self.refreshEarningsAndConflict()
      })
      self.present(alert, animated: true)
    }
  }

  @objc private func relayConnectionDidChange(_ notification: Notification) {
    updateRelayConnectionLabel()
  }

  private func updateRelayConnectionLabel() {
    let connected = DashboardRelay.shared.isConnected
    relayConnectionLabel.text = connected ? "Dashboard: connected" : "Dashboard: disconnected"
    relayConnectionLabel.textColor = connected ? DestroUI.connectedGreen : DestroUI.textSecondary
  }

  private func updateRushHourLabel() {
    let engine = DynamicRuleEngine.shared
    if engine.isCurrentlyRushHour {
      rushHourLabel.text = engine.rushHourDescription
      rushHourLabel.isHidden = false
    } else {
      rushHourLabel.text = nil
      rushHourLabel.isHidden = true
    }
  }

  private func updateSetupBannerVisibility() {
    let hasEnabledAndLinked = (uberEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "com.ubercab.driver")) || (lyftEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "me.lyft.driver"))
    let hasGoneOnlineOnce = UserDefaults.standard.bool(forKey: "destro.hasGoneOnlineOnce")
    let show = hasEnabledAndLinked && !hasGoneOnlineOnce
    stack.arrangedSubviews.first { $0.tag == 9000 }?.isHidden = !show
  }

  @objc private func acceptTapFailed(_ notification: Notification) {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let app = (notification.userInfo?["app"] as? String).map { $0.contains("uber") ? "Uber" : "Lyft" } ?? "Driver app"
      let price = notification.userInfo?["price"] as? Double
      let priceStr = price.map { String(format: " $%.2f", $0) } ?? ""
      let alert = UIAlertController(
        title: "Accept tap failed",
        message: "Destro could not tap Accept for \(app)\(priceStr). Accept manually in the driver app.\n\nIf taps keep failing, ensure Destro is enabled in Settings → Accessibility and try reopening the driver app.",
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      self.present(alert, animated: true)
    }
  }

  @objc private func rejectTapFailed(_ notification: Notification) {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let app = (notification.userInfo?["app"] as? String).map { $0.contains("uber") ? "Uber" : "Lyft" } ?? "Driver app"
      let price = notification.userInfo?["price"] as? Double
      let priceStr = price.map { String(format: " $%.2f", $0) } ?? ""
      let alert = UIAlertController(
        title: "Reject tap failed",
        message: "Destro could not tap Reject for \(app)\(priceStr). Reject manually in the driver app.\n\nIf taps keep failing, ensure Destro is enabled in Settings → Accessibility and try reopening the driver app.",
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      self.present(alert, animated: true)
    }
  }

  @objc private func daemonDidBecomeIdle(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isOnline = false
      UserDefaults.standard.set(false, forKey: "destro.wasScanning")
      if #available(iOS 16.1, *) { endDestroLiveActivity() }
      self.updateStatusText()
      self.refreshEarningsAndConflict()
      if let err = notification.userInfo?["error"] as? String, !err.isEmpty {
        self.showDaemonErrorAlert(message: err)
      }
    }
  }

  private func showDaemonErrorAlert(message: String) {
    let alert = UIAlertController(
      title: "Scanning stopped",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    uberCard.refreshAutoState()
    lyftCard.refreshAutoState()
    uberCard.refreshReadiness()
    lyftCard.refreshReadiness()
    updateRelayConnectionLabel()
    updateRushHourLabel()
    updateSetupBannerVisibility()
    if let daemon = DaemonHolder.shared.daemon {
      if isOnline, !daemon.isScanning {
        isOnline = false
        UserDefaults.standard.set(false, forKey: "destro.wasScanning")
        updateStatusText()
      } else if !isOnline, daemon.isScanning {
        isOnline = true
        updateStatusText()
      }
    }
    refreshEarningsAndConflict()
    updateOfferBreakdownDisplay()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    tryShowResumeScanningPrompt()
  }

  private func tryShowResumeScanningPrompt() {
    guard !didPromptResumeThisLaunch,
          UserDefaults.standard.bool(forKey: "destro.wasScanning") else { return }
    didPromptResumeThisLaunch = true
    UserDefaults.standard.set(false, forKey: "destro.wasScanning")
    let alert = UIAlertController(
      title: "Resume scanning?",
      message: nil,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Yes", style: .default) { [weak self] _ in
      self?.performGoOnline()
    })
    alert.addAction(UIAlertAction(title: "No", style: .cancel))
    present(alert, animated: true)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    earningsTimer?.invalidate()
    earningsTimer = nil
  }

  private func refreshEarningsAndConflict() {
    let session = EarningsTracker.shared.sessionEarnings()
    let today = EarningsTracker.shared.todayEarnings()
    earningsLabel.text = String(format: "Session: $%.2f (%.1f/hr) · Today: $%.2f (%d trips)\nUber: $%.2f · Lyft: $%.2f", session.total, session.hourlyRate, today.total, today.tripCount, session.uberTotal, session.lyftTotal)
    let goal = EarningsTracker.shared.dailyGoal
    let progress = EarningsTracker.shared.dailyGoalProgress()
    dailyGoalLabel.text = String(format: "Daily goal: $%.0f / $%.0f (%.0f%%)", today.total, goal, min(100, progress * 100))
    AppGroupStore.writeSessionEarnings(session.total)
    if isOnline, #available(iOS 16.1, *) {
      let (status, lastApp) = AppGroupStore.readStatus()
      updateDestroLiveActivity(status: status, activeApp: lastApp, sessionEarnings: session.total, timeOnline: Date().timeIntervalSince(session.startDate))
    }
    if let daemon = DaemonHolder.shared.daemon {
      switch daemon.conflictManager.state {
      case .idle:
        conflictLabel.text = "Conflict: Idle"
        AppGroupStore.writeConflictState("idle")
        DashboardRelay.shared.send(["type": "conflict_state", "state": "idle"])
        currentRideActiveApp = nil
        imBackButton.isHidden = true
      case .rideActive(let app):
        conflictLabel.text = "Ride active: \(app.contains("uber") ? "Uber" : "Lyft")"
        AppGroupStore.writeConflictState("rideActive:\(app)")
        DashboardRelay.shared.send(["type": "conflict_state", "state": "rideActive"])
        currentRideActiveApp = app
        imBackButton.isHidden = false
      case .transitioning:
        conflictLabel.text = "Conflict: Switching…"
        AppGroupStore.writeConflictState("transitioning")
        DashboardRelay.shared.send(["type": "conflict_state", "state": "transitioning"])
        currentRideActiveApp = nil
        imBackButton.isHidden = true
      }
    } else {
      conflictLabel.text = "Conflict: —"
      AppGroupStore.writeConflictState("idle")
      currentRideActiveApp = nil
      imBackButton.isHidden = true
    }
  }

  @objc private func imBackTapped() {
    guard let app = currentRideActiveApp,
          let daemon = DaemonHolder.shared.daemon else { return }
    daemon.conflictManager.rideCompleted(wasActiveAppBundleId: app)
    refreshEarningsAndConflict()
  }

  @objc private func manualAcceptTapped() {
    DaemonHolder.shared.daemon?.performManualAccept()
    lastOfferBreakdownText = nil
    updateOfferBreakdownDisplay()
    refreshEarningsAndConflict()
  }

  @objc private func manualRejectTapped() {
    DaemonHolder.shared.daemon?.performManualReject()
    lastOfferBreakdownText = nil
    updateOfferBreakdownDisplay()
    refreshEarningsAndConflict()
  }

  private func loadState() {
    let d = UserDefaults.standard
    uberEnabled = d.bool(forKey: "destro.uber.enabled")
    lyftEnabled = d.bool(forKey: "destro.lyft.enabled")
    if d.object(forKey: "destro.uber.enabled") == nil { d.set(true, forKey: "destro.uber.enabled") }
    if d.object(forKey: "destro.lyft.enabled") == nil { d.set(true, forKey: "destro.lyft.enabled") }
  }

  private func saveState() {
    UserDefaults.standard.set(uberEnabled, forKey: "destro.uber.enabled")
    UserDefaults.standard.set(lyftEnabled, forKey: "destro.lyft.enabled")
  }

  private func setupHeader() {
    let safe = view.safeAreaLayoutGuide
    let menu = UIButton(type: .system)
    menu.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
    menu.tintColor = DestroUI.textPrimary
    menu.translatesAutoresizingMaskIntoConstraints = false
    menu.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
    view.addSubview(menu)

    let logo = UILabel()
    logo.text = "destro."
    logo.font = .systemFont(ofSize: 22, weight: .semibold)
    logo.textColor = DestroUI.textPrimary
    let dot = UILabel()
    dot.text = "●"
    dot.textColor = DestroUI.accentOrange
    dot.font = .systemFont(ofSize: 14)
    let logoStack = UIStackView(arrangedSubviews: [logo, dot])
    logoStack.spacing = 4
    logoStack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(logoStack)

    NSLayoutConstraint.activate([
      menu.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      menu.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
      logoStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      logoStack.centerYAnchor.constraint(equalTo: menu.centerYAnchor)
    ])
  }

  private func setupScrollContent() {
    let safe = view.safeAreaLayoutGuide
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.showsVerticalScrollIndicator = false
    view.addSubview(scrollView)

    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(stack)

    relayConnectionLabel.font = .systemFont(ofSize: 12, weight: .regular)
    updateRelayConnectionLabel()
    stack.addArrangedSubview(relayConnectionLabel)

    rushHourLabel.font = .systemFont(ofSize: 11, weight: .medium)
    rushHourLabel.textColor = DestroUI.accentOrange
    rushHourLabel.numberOfLines = 1
    updateRushHourLabel()
    stack.addArrangedSubview(rushHourLabel)

    // Offer breakdown: show last seen offer (price, miles, $/mi, pickup, surge, decision) or "No offer detected"
    let offerTitle = UILabel()
    offerTitle.text = "Offer"
    offerTitle.font = .systemFont(ofSize: 18, weight: .semibold)
    offerTitle.textColor = DestroUI.textPrimary
    offerBreakdownLabel.font = .systemFont(ofSize: 13, weight: .regular)
    offerBreakdownLabel.numberOfLines = 0
    offerBreakdownLabel.text = "No offer detected.\nDestro cycles between Uber and Lyft; when a request appears it will show here."
    offerBreakdownLabel.textColor = DestroUI.textSecondary
    manualAcceptButton.setTitle("Accept", for: .normal)
    manualAcceptButton.setTitleColor(DestroUI.accentOrange, for: .normal)
    manualAcceptButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    manualAcceptButton.addTarget(self, action: #selector(manualAcceptTapped), for: .touchUpInside)
    manualAcceptButton.accessibilityLabel = "Accept this offer"
    manualRejectButton.setTitle("Reject", for: .normal)
    manualRejectButton.setTitleColor(DestroUI.textSecondary, for: .normal)
    manualRejectButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    manualRejectButton.addTarget(self, action: #selector(manualRejectTapped), for: .touchUpInside)
    manualRejectButton.accessibilityLabel = "Reject this offer"
    let manualButtonsRow = UIStackView(arrangedSubviews: [manualAcceptButton, manualRejectButton])
    manualButtonsRow.axis = .horizontal
    manualButtonsRow.spacing = 16
    offerManualButtonsRow = manualButtonsRow
    offerSectionContainer.backgroundColor = DestroUI.cardBackground
    offerSectionContainer.layer.cornerRadius = DestroUI.cornerRadius
    offerSectionContainer.translatesAutoresizingMaskIntoConstraints = false
    let offerStack = UIStackView(arrangedSubviews: [offerTitle, offerBreakdownLabel, manualButtonsRow])
    offerStack.axis = .vertical
    offerStack.spacing = 8
    offerStack.translatesAutoresizingMaskIntoConstraints = false
    offerSectionContainer.addSubview(offerStack)
    NSLayoutConstraint.activate([
      offerStack.leadingAnchor.constraint(equalTo: offerSectionContainer.leadingAnchor, constant: 16),
      offerStack.trailingAnchor.constraint(equalTo: offerSectionContainer.trailingAnchor, constant: -16),
      offerStack.topAnchor.constraint(equalTo: offerSectionContainer.topAnchor, constant: 16),
      offerStack.bottomAnchor.constraint(equalTo: offerSectionContainer.bottomAnchor, constant: -16),
    ])
    manualButtonsRow.isHidden = true
    offerSectionContainer.isHidden = true
    stack.addArrangedSubview(offerSectionContainer)

    setupBannerLabel.font = .systemFont(ofSize: 12, weight: .regular)
    setupBannerLabel.textColor = DestroUI.accentOrange
    setupBannerLabel.numberOfLines = 2
    setupBannerLabel.text = "Enable Destro in Settings → Accessibility to scan offers."
    setPIDsButton.setTitle("Open Settings", for: .normal)
    setPIDsButton.setTitleColor(DestroUI.accentOrange, for: .normal)
    setPIDsButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
    setPIDsButton.addTarget(self, action: #selector(openAppSettings), for: .touchUpInside)
    let setupRow = UIStackView(arrangedSubviews: [setupBannerLabel, setPIDsButton])
    setupRow.axis = .vertical
    setupRow.spacing = 6
    setupRow.isHidden = true
    setupRow.tag = 9000
    stack.addArrangedSubview(setupRow)
    updateSetupBannerVisibility()

    enabledLabel.text = "Enabled"
    enabledLabel.font = .systemFont(ofSize: 18, weight: .semibold)
    enabledLabel.textColor = DestroUI.textPrimary
    stack.addArrangedSubview(enabledLabel)

    earningsLabel.font = .systemFont(ofSize: 14, weight: .regular)
    earningsLabel.textColor = DestroUI.textSecondary
    earningsLabel.numberOfLines = 3
    stack.addArrangedSubview(earningsLabel)

    dailyGoalLabel.font = .systemFont(ofSize: 12, weight: .regular)
    dailyGoalLabel.textColor = DestroUI.textSecondary
    dailyGoalLabel.numberOfLines = 1
    stack.addArrangedSubview(dailyGoalLabel)

    conflictLabel.font = .systemFont(ofSize: 13, weight: .regular)
    conflictLabel.textColor = DestroUI.textSecondary
    stack.addArrangedSubview(conflictLabel)

    imBackButton.setTitle("I'm back", for: .normal)
    imBackButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
    imBackButton.setTitleColor(DestroUI.accentOrange, for: .normal)
    imBackButton.isHidden = true
    imBackButton.addTarget(self, action: #selector(imBackTapped), for: .touchUpInside)
    stack.addArrangedSubview(imBackButton)

    stack.setCustomSpacing(8, after: conflictLabel)
    stack.setCustomSpacing(8, after: imBackButton)

    uberCard.onToggle = { [weak self] on in
      self?.uberEnabled = on
      self?.saveState()
      self?.updateDaemonEnabledApps()
    }
    uberCard.onFiltersTap = { [weak self] in self?.showFilters(service: "Uber") }
    uberCard.onLinkTap = { [weak self] in self?.showLinkAlert(service: "Uber") }
    uberCard.onUnlinkTap = { [weak self] in self?.confirmUnlink(service: "Uber", bundleId: "com.ubercab.driver") }
    uberCard.onOpenTap = { [weak self] in self?.openDriverApp(service: "Uber") }
    uberCard.onSetPIDTap = { [weak self] bundleId, name in self?.showSingleAppPIDAlert(bundleId: bundleId, serviceName: name) }
    uberCard.isOn = uberEnabled
    stack.addArrangedSubview(uberCard)

    lyftCard.onToggle = { [weak self] on in
      self?.lyftEnabled = on
      self?.saveState()
      self?.updateDaemonEnabledApps()
    }
    lyftCard.onFiltersTap = { [weak self] in self?.showFilters(service: "Lyft") }
    lyftCard.onLinkTap = { [weak self] in self?.showLinkAlert(service: "Lyft") }
    lyftCard.onUnlinkTap = { [weak self] in self?.confirmUnlink(service: "Lyft", bundleId: "me.lyft.driver") }
    lyftCard.onOpenTap = { [weak self] in self?.openDriverApp(service: "Lyft") }
    lyftCard.onSetPIDTap = { [weak self] bundleId, name in self?.showSingleAppPIDAlert(bundleId: bundleId, serviceName: name) }
    lyftCard.isOn = lyftEnabled
    stack.addArrangedSubview(lyftCard)

    stack.setCustomSpacing(24, after: lyftCard)

    let unlinkedHeader = UIStackView()
    unlinkedHeader.axis = .horizontal
    unlinkedLabel.text = "Unlinked"
    unlinkedLabel.font = .systemFont(ofSize: 18, weight: .semibold)
    unlinkedLabel.textColor = DestroUI.textPrimary
    let hideBtn = UIButton(type: .system)
    hideBtn.setTitle("Hide", for: .normal)
    hideBtn.setTitleColor(DestroUI.textSecondary, for: .normal)
    hideBtn.titleLabel?.font = .systemFont(ofSize: 15)
    unlinkedHeader.addArrangedSubview(unlinkedLabel)
    unlinkedHeader.addArrangedSubview(UIView())
    unlinkedHeader.addArrangedSubview(hideBtn)
    stack.addArrangedSubview(unlinkedHeader)
    let unlinkedSubtitle = UILabel()
    unlinkedSubtitle.text = "Tap to link"
    unlinkedSubtitle.font = .systemFont(ofSize: 13, weight: .regular)
    unlinkedSubtitle.textColor = DestroUI.textSecondary
    stack.addArrangedSubview(unlinkedSubtitle)
    stack.setCustomSpacing(4, after: unlinkedHeader)

    didiCard.onTap = { [weak self] in self?.showLinkAlert(service: "DiDi") }
    stack.addArrangedSubview(didiCard)
    doorDashCard.onTap = { [weak self] in self?.showLinkAlert(service: "DoorDash") }
    stack.addArrangedSubview(doorDashCard)

    stack.setCustomSpacing(32, after: doorDashCard)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: safe.topAnchor, constant: 56),
      scrollView.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -140),
      stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
      stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
      stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
    ])
  }

  private func setupBottomBar() {
    let safe = view.safeAreaLayoutGuide
    let bar = UIStackView()
    bar.axis = .horizontal
    bar.distribution = .equalSpacing
    bar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bar)

    driveTab.setTitle("Drive", for: .normal)
    driveTab.setTitleColor(DestroUI.accentOrange, for: .normal)
    driveTab.setImage(UIImage(systemName: "steeringwheel"), for: .normal)
    driveTab.tintColor = DestroUI.accentOrange
    driveTab.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
    historyTab.setTitle("History", for: .normal)
    historyTab.setTitleColor(DestroUI.textSecondary, for: .normal)
    historyTab.setImage(UIImage(systemName: "doc.text"), for: .normal)
    historyTab.tintColor = DestroUI.textSecondary
    historyTab.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
    historyTab.addTarget(self, action: #selector(showHistory), for: .touchUpInside)

    driveTab.accessibilityLabel = "Drive"
    historyTab.accessibilityLabel = "History"

    let centerBlock = UIView()
    statusLabel.textAlignment = .center
    statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
    statusLabel.textColor = DestroUI.textSecondary
    statusLabel.numberOfLines = 2
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    centerBlock.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      statusLabel.centerXAnchor.constraint(equalTo: centerBlock.centerXAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: centerBlock.centerYAnchor)
    ])

    bar.addArrangedSubview(driveTab)
    bar.addArrangedSubview(centerBlock)
    bar.addArrangedSubview(historyTab)

    goButton.setTitle("GO", for: .normal)
    goButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .bold)
    goButton.setTitleColor(.black, for: .normal)
    goButton.backgroundColor = DestroUI.accentOrange
    goButton.layer.cornerRadius = 40
    goButton.translatesAutoresizingMaskIntoConstraints = false
    goButton.addTarget(self, action: #selector(toggleGo), for: .touchUpInside)
    goButton.accessibilityLabel = "Go online"
    view.addSubview(goButton)

    goHintLabel.font = .systemFont(ofSize: 11, weight: .regular)
    goHintLabel.textColor = DestroUI.textSecondary
    goHintLabel.textAlignment = .center
    goHintLabel.numberOfLines = 2
    goHintLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(goHintLabel)

    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      bar.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8),
      bar.heightAnchor.constraint(equalToConstant: 44),
      goButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      goButton.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -16),
      goButton.widthAnchor.constraint(equalToConstant: 80),
      goButton.heightAnchor.constraint(equalToConstant: 80),
      goHintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      goHintLabel.topAnchor.constraint(equalTo: goButton.bottomAnchor, constant: 4),
      goHintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      goHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
    ])
  }

  private func updateStatusText() {
    if isOnline {
      statusLabel.text = "You're online\n\(DestroUI.version)"
      statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
      statusLabel.textColor = DestroUI.accentOrange
      statusLabel.accessibilityLabel = "Online. \(DestroUI.version)"
      goButton.setTitle("STOP", for: .normal)
      goButton.accessibilityLabel = "Stop scanning"
      goButton.accessibilityHint = nil
      goButton.backgroundColor = UIColor(white: 0.25, alpha: 1)
      goHintLabel.isHidden = true
    } else {
      statusLabel.text = "You're offline\n\(DestroUI.version)"
      statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
      statusLabel.textColor = DestroUI.textSecondary
      statusLabel.accessibilityLabel = "Offline. \(DestroUI.version)"
      goButton.setTitle("GO", for: .normal)
      goButton.accessibilityLabel = "Go online"
      goButton.accessibilityHint = "Tap after linking a service"
      goButton.backgroundColor = DestroUI.accentOrange
      goHintLabel.text = "Link a service, then tap GO"
      goHintLabel.isHidden = false
    }
    updateRushHourLabel()
    uberCard.setOnline(isOnline)
    lyftCard.setOnline(isOnline)
  }

  private func updateDaemonEnabledApps() {
    guard isOnline, let daemon = DaemonHolder.shared.daemon else { return }
    var ids: [String] = []
    if uberEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "com.ubercab.driver") { ids.append("com.ubercab.driver") }
    if lyftEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "me.lyft.driver") { ids.append("me.lyft.driver") }
    daemon.enabledBundleIds = ids
    if !ids.isEmpty { daemon.startScanning() }
  }

  @objc private func toggleGo() {
    if !isOnline {
      if !canGoOnline() {
        showGoBlockedAlert()
        return
      }
      performGoOnline()
      return
    }
    EarningsTracker.shared.endSession()
    isOnline = false
    UserDefaults.standard.set(false, forKey: "destro.wasScanning")
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    updateStatusText()
    let daemon = DaemonHolder.shared.daemon
    daemon?.stopScanning()
    daemon?.conflictManager.onStateChange = nil
    earningsTimer?.invalidate()
    earningsTimer = nil
    if #available(iOS 16.1, *) { endDestroLiveActivity() }
    GeofenceManager.shared.stopUpdatingLocation()
    refreshEarningsAndConflict()
    updateOfferBreakdownDisplay()
  }

  private func performGoOnline() {
    UserDefaults.standard.set(true, forKey: "destro.hasGoneOnlineOnce")
    EarningsTracker.shared.startSession()
    isOnline = true
    UserDefaults.standard.set(true, forKey: "destro.wasScanning")
    updateStatusText()
    var ids: [String] = []
    if uberEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "com.ubercab.driver") { ids.append("com.ubercab.driver") }
    if lyftEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "me.lyft.driver") { ids.append("me.lyft.driver") }
    let daemon = DaemonHolder.shared.daemon
    daemon?.enabledBundleIds = ids
    if !ids.isEmpty { daemon?.startScanning() }
    daemon?.conflictManager.onStateChange = { [weak self] _ in DispatchQueue.main.async { self?.refreshEarningsAndConflict() } }
    earningsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshEarningsAndConflict() }
    }
    if #available(iOS 16.1, *) { startDestroLiveActivity() }
    GeofenceManager.shared.startUpdatingLocation()
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    refreshEarningsAndConflict()
    lastOfferBreakdownText = nil
    updateOfferBreakdownDisplay()
  }

  /// True if at least one enabled service is linked (or ready/degraded).
  private func canGoOnline() -> Bool {
    if uberEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "com.ubercab.driver") { return true }
    if lyftEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "me.lyft.driver") { return true }
    return false
  }

  private func showGoBlockedAlert() {
    let alert = UIAlertController(
      title: "Link a service first",
      message: "Like Mystro: open Uber or Lyft only from Destro (tap Open ↗️ on the card), not from the home screen, so we recognize you're online. Sign in in the driver app, then return and tap GO.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Link Uber Driver", style: .default) { [weak self] _ in
      self?.markServiceLinkedAndPrompt(service: "Uber")
    })
    alert.addAction(UIAlertAction(title: "Open Uber Driver (↗️)", style: .default) { [weak self] _ in
      self?.openDriverApp(service: "Uber")
    })
    alert.addAction(UIAlertAction(title: "Link Lyft Driver", style: .default) { [weak self] _ in
      self?.markServiceLinkedAndPrompt(service: "Lyft")
    })
    alert.addAction(UIAlertAction(title: "Open Lyft Driver (↗️)", style: .default) { [weak self] _ in
      self?.openDriverApp(service: "Lyft")
    })
    alert.addAction(UIAlertAction(title: "OK", style: .cancel))
    present(alert, animated: true)
  }

  @objc private func showHistory() {
    let vc = HistoryViewController()
    vc.view.backgroundColor = DestroUI.backgroundColor
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .pageSheet
    present(nav, animated: true)
  }

  @objc private func showMenu() {
    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
    alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
    })
    alert.addAction(UIAlertAction(title: "Dashboard URL…", style: .default) { [weak self] _ in
      self?.showDashboardURLAlert()
    })
    alert.addAction(UIAlertAction(title: "Set driver app PID…", style: .default) { [weak self] _ in
      self?.showPIDAlert()
    })
    alert.addAction(UIAlertAction(title: "About Destro \(DestroUI.version)", style: .default) { [weak self] _ in
      self?.showAboutDestroAlert()
    })
    alert.addAction(UIAlertAction(title: "View logs", style: .default) { [weak self] _ in
      self?.showLogsAlert()
    })
    alert.addAction(UIAlertAction(title: "Export history", style: .default) { [weak self] _ in
      self?.exportHistory()
    })
    alert.addAction(UIAlertAction(title: "Set daily goal…", style: .default) { [weak self] _ in
      self?.showDailyGoalAlert()
    })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let pop = alert.popoverPresentationController {
      pop.sourceView = view
      pop.sourceRect = CGRect(x: 30, y: 60, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func showDashboardURLAlert() {
    let alert = UIAlertController(
      title: "Dashboard WebSocket URL",
      message: "Your Mac’s URL so the phone can reach the dashboard. Run the dashboard on your Mac (npm start), then enter its address here.",
      preferredStyle: .alert
    )
    alert.addTextField { tf in
      tf.placeholder = "e.g. ws://192.168.1.10:3000"
      tf.text = DashboardRelay.shared.getBaseURL()
      tf.autocapitalizationType = .none
      tf.autocorrectionType = .no
      tf.keyboardType = .URL
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
      let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      DashboardRelay.shared.setBaseURL(text)
    })
    present(alert, animated: true)
  }

  @objc private func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
      UIApplication.shared.open(url)
    }
  }

  @objc private func showPIDAlert() {
    let alert = UIAlertController(
      title: "Driver app PIDs",
      message: "Only needed if scanning doesn’t work. Get PIDs from Mac Console.app while the driver app is running, or leave blank to use automatic (frontmost app).",
      preferredStyle: .alert
    )
    let uberPID = ServiceReadinessStore.storedPID(bundleId: "com.ubercab.driver")
    let lyftPID = ServiceReadinessStore.storedPID(bundleId: "me.lyft.driver")
    alert.addTextField { tf in
      tf.placeholder = "Uber driver app PID"
      tf.text = uberPID.map { String(Int32($0)) } ?? ""
      tf.keyboardType = .numberPad
    }
    alert.addTextField { tf in
      tf.placeholder = "Lyft driver app PID"
      tf.text = lyftPID.map { String(Int32($0)) } ?? ""
      tf.keyboardType = .numberPad
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
      let uberText = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let lyftText = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if let v = Int32(uberText), v > 0 {
        ServiceReadinessStore.storePID(pid_t(v), bundleId: "com.ubercab.driver")
      }
      if let v = Int32(lyftText), v > 0 {
        ServiceReadinessStore.storePID(pid_t(v), bundleId: "me.lyft.driver")
      }
      self?.uberCard.refreshReadiness()
      self?.lyftCard.refreshReadiness()
      self?.updateSetupBannerVisibility()
    })
    present(alert, animated: true)
  }

  private func showSingleAppPIDAlert(bundleId: String, serviceName: String) {
    let current = ServiceReadinessStore.storedPID(bundleId: bundleId)
    let alert = UIAlertController(
      title: "\(serviceName) driver app PID",
      message: "Optional. Destro normally uses the frontmost app (no PID needed). Set a PID only if automatic detection fails.",
      preferredStyle: .alert
    )
    alert.addTextField { tf in
      tf.placeholder = "PID"
      tf.text = current.map { String(Int32($0)) } ?? ""
      tf.keyboardType = .numberPad
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
      let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if let v = Int32(text), v > 0 {
        ServiceReadinessStore.storePID(pid_t(v), bundleId: bundleId)
      }
      if bundleId.contains("uber") {
        self?.uberCard.refreshReadiness()
      } else {
        self?.lyftCard.refreshReadiness()
      }
      self?.updateSetupBannerVisibility()
    })
    present(alert, animated: true)
  }

  private func showAboutDestroAlert() {
    let message = """
    Version \(DestroUI.version).

    How it works (stock iOS): Offer reading and accept/reject use Accessibility. App switching uses app URLs. No PID needed in normal use.

    Enable Destro in Settings → Accessibility for offer detection and taps.
    """
    let alert = UIAlertController(
      title: "About Destro",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  private func showLogsAlert() {
    let all = LogBuffer.shared.lines
    let last = Array(all.suffix(10))
    let message = last.isEmpty ? "No logs yet." : last.joined(separator: "\n")
    let alert = UIAlertController(title: "Destro logs", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  private func exportHistory() {
    let entries = HistoryStore.load()
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    let tf = DateFormatter()
    tf.dateFormat = "HH:mm:ss"
    var csv = "date,time,app,price,latencyMs,decision,reason\n"
    for e in entries {
      let dateStr = df.string(from: e.date)
      let timeStr = tf.string(from: e.date)
      let dec = e.decision ?? ""
      let reason = (e.reason ?? "").replacingOccurrences(of: "\"", with: "\"\"")
      csv += "\(dateStr),\(timeStr),\(e.app),\(String(format: "%.2f", e.price)),\(e.latencyMs),\(dec),\"\(reason)\"\n"
    }
    let fileName = "destro_history_\(df.string(from: Date())).csv"
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    do {
      try csv.write(to: temp, atomically: true, encoding: .utf8)
      let av = UIActivityViewController(activityItems: [temp], applicationActivities: nil)
      if let pop = av.popoverPresentationController {
        pop.sourceView = view
        pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
      }
      present(av, animated: true)
    } catch {
      let alert = UIAlertController(title: "Export failed", message: error.localizedDescription, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
    }
  }

  private func showDailyGoalAlert() {
    let alert = UIAlertController(
      title: "Daily goal ($)",
      message: "Earnings goal for today.",
      preferredStyle: .alert
    )
    alert.addTextField { tf in
      tf.keyboardType = .decimalPad
      tf.placeholder = "200"
      tf.text = String(format: "%.0f", EarningsTracker.shared.dailyGoal)
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
      if let text = alert.textFields?.first?.text, let v = Double(text), v >= 0 {
        EarningsTracker.shared.dailyGoal = v
        self?.refreshEarningsAndConflict()
      }
    })
    present(alert, animated: true)
  }

  private func showLinkAlert(service: String) {
    // Driver app URLs use bundle ID scheme (opens driver app, not rider). Mystro-style: open from Destro (↗️).
    let driverURL: URL? = {
      switch service.lowercased() {
      case "uber": return URL(string: "com.ubercab.driver://")
      case "lyft": return URL(string: "me.lyft.driver://")
      default: return nil
      }
    }()
    let appStoreURL: URL? = {
      switch service.lowercased() {
      case "uber": return URL(string: "https://apps.apple.com/app/uber-driver/id1131342792")
      case "lyft": return URL(string: "https://apps.apple.com/app/lyft-driver/id905997506")
      case "didi": return URL(string: "https://apps.apple.com/search/didi%20driver")
      case "doordash": return URL(string: "https://apps.apple.com/app/doordash-driver/id947045479")
      default: return nil
      }
    }()
    let driverName = (service.lowercased() == "uber" || service.lowercased() == "lyft") ? "\(service) Driver" : service
    let alert = UIAlertController(
      title: "Link \(service)",
      message: "Destro will use the \(driverName) app when you're online. Open it from Destro (tap Open ↗️) so we recognize you're online; opening from the home screen may not be recognized. Sign in there, then return and tap GO.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if service.lowercased() == "uber" || service.lowercased() == "lyft" {
      alert.addAction(UIAlertAction(title: "Link \(driverName)", style: .default) { [weak self] _ in
        self?.markServiceLinkedAndPrompt(service: service)
      })
      if driverURL != nil {
        alert.addAction(UIAlertAction(title: "Open \(driverName) (↗️)", style: .default) { [weak self] _ in
          self?.openDriverApp(service: service)
        })
      }
    }
    if let u = appStoreURL {
      alert.addAction(UIAlertAction(title: "App Store", style: .default) { _ in
        UIApplication.shared.open(u)
      })
    }
    present(alert, animated: true)
  }

  /// After linking, prompt to open driver app from Destro (↗️), then GO.
  private func markServiceLinkedAndPrompt(service: String) {
    markServiceLinked(service: service)
    let appName = (service.lowercased() == "uber" || service.lowercased() == "lyft") ? "\(service) Driver" : service
    let alert = UIAlertController(
      title: "\(service) linked",
      message: "Next: open the \(appName) app from Destro (tap Open ↗️ on the card), sign in there, then return and tap GO.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  private func markServiceLinked(service: String) {
    let bundleId: String
    switch service.lowercased() {
    case "uber": bundleId = "com.ubercab.driver"
    case "lyft": bundleId = "me.lyft.driver"
    default: return
    }
    ServiceReadinessStore.markLinked(bundleId: bundleId)
    uberCard.refreshReadiness()
    lyftCard.refreshReadiness()
  }

  /// Open the driver app via its URL scheme (Mystro-style ↗️). Use from Destro so we recognize you're online. Checks canOpenURL and alerts if app not installed.
  private func openDriverApp(service: String) {
    let bundleId: String
    switch service.lowercased() {
    case "uber": bundleId = "com.ubercab.driver"
    case "lyft": bundleId = "me.lyft.driver"
    default: return
    }
    guard let url = URL(string: "\(bundleId)://") else { return }
    if !UIApplication.shared.canOpenURL(url) {
      let appName = (service.lowercased() == "uber" || service.lowercased() == "lyft") ? "\(service) Driver" : service
      let alert = UIAlertController(
        title: "\(appName) not available",
        message: "The \(appName) app does not appear to be installed or cannot be opened. Install it from the App Store and try again.",
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "App Store", style: .default) { _ in
        let storeURL: URL? = service.lowercased() == "uber"
          ? URL(string: "https://apps.apple.com/app/uber-driver/id1131342792")
          : URL(string: "https://apps.apple.com/app/lyft-driver/id905997506")
        if let u = storeURL { UIApplication.shared.open(u) }
      })
      alert.addAction(UIAlertAction(title: "OK", style: .cancel))
      present(alert, animated: true)
      return
    }
    UIApplication.shared.open(url)
  }

  private func confirmUnlink(service: String, bundleId: String) {
    let alert = UIAlertController(
      title: "Unlink \(service)?",
      message: "Destro will stop using the \(service) driver app until you link again. Use Link to open the driver app and re-link.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Unlink", style: .destructive) { [weak self] _ in
      ServiceReadinessStore.markUnlinked(bundleId: bundleId)
      self?.uberCard.refreshReadiness()
      self?.lyftCard.refreshReadiness()
      self?.updateSetupBannerVisibility()
    })
    present(alert, animated: true)
  }
}

// MARK: - Service Card (Uber / Lyft)

final class ServiceCard: UIView {
  var onToggle: ((Bool) -> Void)?
  var onFiltersTap: (() -> Void)?
  var onLinkTap: (() -> Void)?
  var onUnlinkTap: (() -> Void)?
  /// Open driver app from Destro (↗️). Shown when linked.
  var onOpenTap: (() -> Void)?
  /// Called with (bundleId, serviceName) when user taps Set PID.
  var onSetPIDTap: ((String, String) -> Void)?
  var isOn: Bool = true {
    didSet { toggle.isOn = isOn }
  }

  private let bundleId: String
  private let serviceName: String

  /// Update status line when dashboard goes online/offline.
  func setOnline(_ online: Bool) {
    isOnline = online
    updateStatusLine()
  }

  func refreshReadiness() {
    updateStatusLine()
  }

  private var isOnline = false

  private func updateStatusLine() {
    let readiness = ServiceReadinessStore.get(bundleId: bundleId)
    let readinessText: String
    switch readiness {
    case .unlinked: readinessText = "Not linked"
    case .linked: readinessText = "Linked"
    case .ready: readinessText = "Ready"
    case .degraded: readinessText = "Degraded"
    }
    linkButton.isHidden = (readiness != .unlinked)
    unlinkButton.isHidden = (readiness == .unlinked)
    openButton.isHidden = (readiness == .unlinked)
    let base = isOnline ? "Destro is online" : "Destro is offline"
    var line = "\(base) · \(readinessText)"
    if let pid = ServiceReadinessStore.storedPID(bundleId: bundleId) {
      line += " · PID: \(pid)"
    }
    statusLabel.text = line
    statusLabel.accessibilityLabel = "\(serviceName), \(base), \(readinessText)"
  }

  private let titleLabel = UILabel()
  private let statusLabel = UILabel()
  let toggle = UISwitch()
  private let filtersButton = UIButton(type: .system)
  private let linkButton = UIButton(type: .system)
  private let unlinkButton = UIButton(type: .system)
  private let openButton = UIButton(type: .system)
  private let setPIDButton = UIButton(type: .system)
  private let autoAcceptButton = UIButton(type: .system)
  private let autoRejectButton = UIButton(type: .system)

  init(service: String, bundleId: String) {
    self.bundleId = bundleId
    self.serviceName = service
    super.init(frame: .zero)
    backgroundColor = DestroUI.cardBackground
    layer.cornerRadius = DestroUI.cornerRadius
    translatesAutoresizingMaskIntoConstraints = false

    titleLabel.text = "\(service) - Enabled"
    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    titleLabel.textColor = DestroUI.textPrimary
    statusLabel.text = "Destro is offline"
    statusLabel.font = .systemFont(ofSize: 14, weight: .regular)
    statusLabel.textColor = DestroUI.textSecondary
    toggle.onTintColor = DestroUI.accentOrange
    toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
    filtersButton.setTitle("Filters", for: .normal)
    filtersButton.setTitleColor(DestroUI.textPrimary, for: .normal)
    filtersButton.setImage(UIImage(systemName: "line.3.horizontal.decrease.circle"), for: .normal)
    filtersButton.tintColor = DestroUI.textSecondary
    filtersButton.accessibilityLabel = "Filters for \(service)"
    linkButton.setTitle("Link", for: .normal)
    linkButton.setTitleColor(DestroUI.accentOrange, for: .normal)
    linkButton.titleLabel?.font = .systemFont(ofSize: 12)
    linkButton.addTarget(self, action: #selector(linkTapped), for: .touchUpInside)
    linkButton.accessibilityLabel = "Link \(service) Driver"
    unlinkButton.setTitle("Unlink", for: .normal)
    unlinkButton.setTitleColor(DestroUI.textSecondary, for: .normal)
    unlinkButton.titleLabel?.font = .systemFont(ofSize: 12)
    unlinkButton.addTarget(self, action: #selector(unlinkTapped), for: .touchUpInside)
    unlinkButton.accessibilityLabel = "Unlink"
    openButton.setTitle("Open (↗️)", for: .normal)
    openButton.setTitleColor(DestroUI.accentOrange, for: .normal)
    openButton.titleLabel?.font = .systemFont(ofSize: 12)
    openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
    openButton.accessibilityLabel = "Open \(service) Driver app"
    setPIDButton.setTitle("Set PID", for: .normal)
    setPIDButton.setTitleColor(DestroUI.textSecondary, for: .normal)
    setPIDButton.titleLabel?.font = .systemFont(ofSize: 12)
    setPIDButton.addTarget(self, action: #selector(setPIDTapped), for: .touchUpInside)
    setPIDButton.accessibilityLabel = "Set PID for \(service)"
    autoAcceptButton.setTitle(" Auto-accept", for: .normal)
    autoAcceptButton.setTitleColor(DestroUI.accentOrange, for: .normal)
    autoAcceptButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
    autoAcceptButton.tintColor = DestroUI.accentOrange
    autoRejectButton.setTitle(" Auto-reject", for: .normal)
    autoRejectButton.setTitleColor(DestroUI.accentOrange, for: .normal)
    autoRejectButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
    autoRejectButton.tintColor = DestroUI.accentOrange
    autoAcceptButton.addTarget(self, action: #selector(autoAcceptTapped), for: .touchUpInside)
    autoRejectButton.addTarget(self, action: #selector(autoRejectTapped), for: .touchUpInside)

    let topRow = UIStackView(arrangedSubviews: [titleLabel, toggle])
    topRow.axis = .horizontal
    topRow.alignment = .center
    topRow.distribution = .equalSpacing
    let filtersRow = UIStackView(arrangedSubviews: [filtersButton, linkButton, unlinkButton, openButton, setPIDButton, UIView()])
    filtersRow.axis = .horizontal
    filtersRow.spacing = 8
    filtersButton.addTarget(self, action: #selector(filtersTapped), for: .touchUpInside)
    let buttonsRow = UIStackView(arrangedSubviews: [autoAcceptButton, autoRejectButton])
    buttonsRow.axis = .horizontal
    buttonsRow.spacing = 12
    let stack = UIStackView(arrangedSubviews: [topRow, statusLabel, filtersRow, buttonsRow])
    stack.axis = .vertical
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
    ])
    refreshAutoState()
    updateStatusLine()
  }

  func refreshAutoState() {
    let svc = FilterConfig.service(from: bundleId)
    autoAcceptButton.setTitle(FilterConfig.autoAccept(service: svc) ? " Auto-accept" : " Auto-accept (off)", for: .normal)
    autoRejectButton.setTitle(FilterConfig.autoReject(service: svc) ? " Auto-reject" : " Auto-reject (off)", for: .normal)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func toggleChanged() { onToggle?(toggle.isOn) }
  @objc private func filtersTapped() { onFiltersTap?() }
  @objc private func linkTapped() { onLinkTap?() }
  @objc private func unlinkTapped() { onUnlinkTap?() }
  @objc private func openTapped() { onOpenTap?() }
  @objc private func setPIDTapped() { onSetPIDTap?(bundleId, serviceName) }
  @objc private func autoAcceptTapped() {
    let svc = FilterConfig.service(from: bundleId)
    FilterConfig.setAutoAccept(!FilterConfig.autoAccept(service: svc), service: svc)
    refreshAutoState()
  }
  @objc private func autoRejectTapped() {
    let svc = FilterConfig.service(from: bundleId)
    FilterConfig.setAutoReject(!FilterConfig.autoReject(service: svc), service: svc)
    refreshAutoState()
  }
}

// MARK: - Unlinked Service Card

final class UnlinkedServiceCard: UIView {
  var onTap: (() -> Void)?

  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()

  init(service: String) {
    super.init(frame: .zero)
    backgroundColor = DestroUI.cardBackground
    layer.cornerRadius = DestroUI.cornerRadius
    translatesAutoresizingMaskIntoConstraints = false
    isUserInteractionEnabled = true
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

    isAccessibilityElement = true
    accessibilityLabel = "\(service), tap to link"
    accessibilityHint = "Opens link options"

    titleLabel.text = "\(service) - Unlinked"
    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    titleLabel.textColor = DestroUI.textPrimary
    subtitleLabel.text = "Tap to link"
    subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
    subtitleLabel.textColor = DestroUI.textSecondary
    let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    stack.axis = .vertical
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    let info = UIImageView(image: UIImage(systemName: "info.circle"))
    info.tintColor = DestroUI.textSecondary
    info.translatesAutoresizingMaskIntoConstraints = false
    addSubview(info)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      info.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      info.centerYAnchor.constraint(equalTo: centerYAnchor),
      heightAnchor.constraint(equalToConstant: 72)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func tapped() { onTap?() }
}

// MARK: - Filters

extension DashboardViewController {
  func showFilters(service: String) {
    let vc = FiltersViewController(service: service)
    let nav = UINavigationController(rootViewController: vc)
    nav.modalPresentationStyle = .pageSheet
    present(nav, animated: true)
  }
}

// MARK: - Filters View Controller

@MainActor
final class FiltersViewController: UIViewController {
  private let service: String
  private var serviceKey: String { service.lowercased() }
  private let minPriceField = UITextField()
  private let minPerMileField = UITextField()
  private let minHourlyField = UITextField()
  private let maxPickupField = UITextField()
  private let minPassengerRatingField = UITextField()
  private let minSurgeField = UITextField()
  private let autoAcceptSwitch = UISwitch()
  private let autoRejectSwitch = UISwitch()
  private let requireConfirmSwitch = UISwitch()
  private let activeStartField = UITextField()
  private let activeEndField = UITextField()
  private var blockedRideTypeSwitches: [RideType: UISwitch] = [:]
  private var geofenceZoneRowsStack: UIStackView?

  init(service: String) {
    self.service = service
    super.init(nibName: nil, bundle: nil)
    title = "\(service) Filters"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func makeLabel(_ text: String) -> UILabel {
    let l = UILabel()
    l.text = text
    l.textColor = DestroUI.textSecondary
    l.font = .systemFont(ofSize: 14)
    return l
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = DestroUI.backgroundColor
    navigationController?.navigationBar.tintColor = DestroUI.accentOrange
    navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismissTap))
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTap))

    let sk = serviceKey
    minPriceField.text = String(format: "%.0f", FilterConfig.minPrice(service: sk))
    minPerMileField.text = String(format: "%.2f", FilterConfig.minPricePerMile(service: sk))
    minHourlyField.text = String(format: "%.0f", FilterConfig.minHourlyRate(service: sk))
    maxPickupField.text = String(format: "%.1f", FilterConfig.maxPickupDistance(service: sk))
    minPassengerRatingField.text = String(format: "%.1f", FilterConfig.minPassengerRating(service: sk))
    minSurgeField.text = String(format: "%.2f", FilterConfig.minSurgeMultiplier(service: sk))
    autoAcceptSwitch.isOn = FilterConfig.autoAccept(service: sk)
    autoAcceptSwitch.onTintColor = DestroUI.accentOrange
    autoRejectSwitch.isOn = FilterConfig.autoReject(service: sk)
    autoRejectSwitch.onTintColor = DestroUI.accentOrange
    requireConfirmSwitch.isOn = FilterConfig.requireConfirmBeforeAccept(service: sk)
    requireConfirmSwitch.onTintColor = DestroUI.accentOrange
    activeStartField.text = String(FilterConfig.activeHoursStart(service: sk))
    activeEndField.text = String(FilterConfig.activeHoursEnd(service: sk))

    let minPriceLabel = makeLabel("Min trip ($)")
    let minPerMileLabel = makeLabel("Min $/mile")
    let minHourlyLabel = makeLabel("Min $/hr")
    let maxPickupLabel = makeLabel("Max pickup (mi)")
    let minRatingLabel = makeLabel("Min passenger rating (0–5)")
    let minSurgeLabel = makeLabel("Min surge multiplier (1.0 = no surge)")
    let autoAcceptLabel = makeLabel("Auto-accept when criteria met")
    let autoRejectLabel = makeLabel("Auto-reject when below criteria")
    let requireConfirmLabel = makeLabel("Require confirm before accept (show Accept/Decline)")
    let activeLabel = makeLabel("Active hours (0–23, start / end)")
    let rushNote = makeLabel("Rush hour (7–9a, 4–7p): min $/mile is 10% higher.")
    rushNote.font = .systemFont(ofSize: 12)
    rushNote.numberOfLines = 0
    let geofenceLabel = makeLabel("Geofence zones (accept = only accept pickups here; avoid = reject)")
    geofenceLabel.numberOfLines = 0
    let geofenceZoneRows = UIStackView()
    geofenceZoneRows.axis = .vertical
    geofenceZoneRows.spacing = 6
    geofenceZoneRowsStack = geofenceZoneRows
    refreshGeofenceZoneRows()
    let addZoneBtn = UIButton(type: .system)
    addZoneBtn.setTitle("Add zone", for: .normal)
    addZoneBtn.setTitleColor(DestroUI.accentOrange, for: .normal)
    addZoneBtn.titleLabel?.font = .systemFont(ofSize: 14)
    addZoneBtn.addTarget(self, action: #selector(addGeofenceZoneTapped), for: .touchUpInside)
    let geofenceSection = UIStackView(arrangedSubviews: [geofenceLabel, geofenceZoneRows, addZoneBtn])
    geofenceSection.axis = .vertical
    geofenceSection.spacing = 8

    [minPriceField, minPerMileField, minHourlyField, maxPickupField, minPassengerRatingField, minSurgeField, activeStartField, activeEndField].forEach {
      $0.keyboardType = .decimalPad
      $0.backgroundColor = DestroUI.cardBackground
      $0.textColor = DestroUI.textPrimary
      $0.layer.cornerRadius = 8
      $0.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
      $0.leftViewMode = .always
      $0.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
      $0.rightViewMode = .always
    }
    minHourlyField.keyboardType = .decimalPad
    maxPickupField.keyboardType = .decimalPad
    activeStartField.keyboardType = .numberPad
    activeEndField.keyboardType = .numberPad

    let autoAcceptRow = UIStackView(arrangedSubviews: [autoAcceptLabel, autoAcceptSwitch])
    autoAcceptRow.axis = .horizontal
    autoAcceptRow.distribution = .equalSpacing
    let autoRejectRow = UIStackView(arrangedSubviews: [autoRejectLabel, autoRejectSwitch])
    autoRejectRow.axis = .horizontal
    autoRejectRow.distribution = .equalSpacing

    let requireConfirmRow = UIStackView(arrangedSubviews: [requireConfirmLabel, requireConfirmSwitch])
    requireConfirmRow.axis = .horizontal
    requireConfirmRow.distribution = .equalSpacing

    let blockedLabel = makeLabel("Blocked ride types (auto-reject when offer matches)")
    var blockedRows: [UIView] = [blockedLabel]
    for type in RideType.allCases {
      let rowLabel = makeLabel("Block \(type.displayName)")
      let sw = UISwitch()
      sw.isOn = FilterConfig.blockedRideTypes(service: serviceKey).contains(type)
      sw.onTintColor = DestroUI.accentOrange
      blockedRideTypeSwitches[type] = sw
      let row = UIStackView(arrangedSubviews: [rowLabel, sw])
      row.axis = .horizontal
      row.distribution = .equalSpacing
      blockedRows.append(row)
    }
    let blockedStack = UIStackView(arrangedSubviews: blockedRows)
    blockedStack.axis = .vertical
    blockedStack.spacing = 6

    let activeRow = UIStackView(arrangedSubviews: [activeStartField, activeEndField])
    activeRow.axis = .horizontal
    activeRow.spacing = 12

    let stack = UIStackView(arrangedSubviews: [
      rushNote,
      geofenceSection,
      minPriceLabel, minPriceField,
      minPerMileLabel, minPerMileField,
      minHourlyLabel, minHourlyField,
      maxPickupLabel, maxPickupField,
      minRatingLabel, minPassengerRatingField,
      minSurgeLabel, minSurgeField,
      autoAcceptRow, autoRejectRow, requireConfirmRow,
      blockedStack,
      activeLabel, activeRow
    ])
    stack.axis = .vertical
    stack.spacing = 8
    stack.setCustomSpacing(12, after: rushNote)
    stack.setCustomSpacing(8, after: geofenceSection)
    stack.setCustomSpacing(16, after: minPriceField)
    stack.setCustomSpacing(16, after: minPerMileField)
    stack.setCustomSpacing(16, after: minHourlyField)
    stack.setCustomSpacing(16, after: maxPickupField)
    stack.setCustomSpacing(16, after: minPassengerRatingField)
    stack.setCustomSpacing(16, after: minSurgeField)
    stack.setCustomSpacing(16, after: autoRejectRow)
    stack.setCustomSpacing(16, after: requireConfirmRow)
    stack.setCustomSpacing(16, after: blockedStack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    [minPriceField, minPerMileField, minHourlyField, maxPickupField, minPassengerRatingField, minSurgeField].forEach {
      $0.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    activeStartField.heightAnchor.constraint(equalToConstant: 44).isActive = true
    activeEndField.heightAnchor.constraint(equalToConstant: 44).isActive = true
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
    ])
  }

  private func refreshGeofenceZoneRows() {
    guard let stack = geofenceZoneRowsStack else { return }
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (index, zone) in FilterConfig.geofenceZones.enumerated() {
      let row = makeGeofenceZoneRow(zone: zone, index: index)
      stack.addArrangedSubview(row)
    }
  }

  private func makeGeofenceZoneRow(zone: GeofenceZone, index: Int) -> UIView {
    let label = makeLabel("\(zone.name) · \(String(format: "%.4f", zone.latitude)), \(String(format: "%.4f", zone.longitude)) · \(Int(zone.radiusMeters)) m · \(zone.isAcceptZone ? "Accept" : "Avoid")")
    label.numberOfLines = 2
    let delBtn = UIButton(type: .system)
    delBtn.setTitle("Delete", for: .normal)
    delBtn.setTitleColor(.systemRed, for: .normal)
    delBtn.titleLabel?.font = .systemFont(ofSize: 12)
    delBtn.tag = index
    delBtn.addTarget(self, action: #selector(deleteGeofenceZoneTapped(_:)), for: .touchUpInside)
    let row = UIStackView(arrangedSubviews: [label, delBtn])
    row.axis = .horizontal
    row.distribution = .equalSpacing
    row.alignment = .center
    return row
  }

  @objc private func deleteGeofenceZoneTapped(_ sender: UIButton) {
    var zones = FilterConfig.geofenceZones
    let idx = sender.tag
    guard idx >= 0, idx < zones.count else { return }
    zones.remove(at: idx)
    FilterConfig.geofenceZones = zones
    refreshGeofenceZoneRows()
  }

  @objc private func addGeofenceZoneTapped() {
    let alert = UIAlertController(title: "Add geofence zone", message: "Enter name, latitude, longitude, radius (meters).", preferredStyle: .alert)
    alert.addTextField { $0.placeholder = "Name" }
    alert.addTextField { $0.placeholder = "Latitude"; $0.keyboardType = .decimalPad }
    alert.addTextField { $0.placeholder = "Longitude"; $0.keyboardType = .decimalPad }
    alert.addTextField { $0.placeholder = "Radius (m)"; $0.keyboardType = .decimalPad }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Add as Accept zone", style: .default) { [weak self] _ in
      self?.addGeofenceZoneFromAlert(alert, isAccept: true)
    })
    alert.addAction(UIAlertAction(title: "Add as Avoid zone", style: .default) { [weak self] _ in
      self?.addGeofenceZoneFromAlert(alert, isAccept: false)
    })
    present(alert, animated: true)
  }

  private func addGeofenceZoneFromAlert(_ alert: UIAlertController, isAccept: Bool) {
    let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Zone"
    guard let lat = Double(alert.textFields?[1].text ?? ""),
          let lon = Double(alert.textFields?[2].text ?? ""),
          let radius = Double(alert.textFields?[3].text ?? ""), radius > 0 else { return }
    let zone = GeofenceZone(latitude: lat, longitude: lon, radiusMeters: min(50000, radius), isAcceptZone: isAccept, name: name.isEmpty ? "Zone" : name)
    var zones = FilterConfig.geofenceZones
    zones.append(zone)
    FilterConfig.geofenceZones = zones
    refreshGeofenceZoneRows()
  }

    @objc private func dismissTap() { dismiss(animated: true) }
  @objc private func saveTap() {
    let sk = serviceKey
    if let p = Double(minPriceField.text ?? ""), p >= 0 { FilterConfig.setMinPrice(p, service: sk) }
    if let m = Double(minPerMileField.text ?? ""), m >= 0 { FilterConfig.setMinPricePerMile(m, service: sk) }
    if let h = Double(minHourlyField.text ?? ""), h >= 0 { FilterConfig.setMinHourlyRate(h, service: sk) }
    if let d = Double(maxPickupField.text ?? ""), d >= 0 { FilterConfig.setMaxPickupDistance(d, service: sk) }
    if let r = Double(minPassengerRatingField.text ?? ""), (0...5).contains(r) { FilterConfig.setMinPassengerRating(r, service: sk) }
    if let s = Double(minSurgeField.text ?? ""), s >= 0 { FilterConfig.setMinSurgeMultiplier(s, service: sk) }
    FilterConfig.setBlockedRideTypes(RideType.allCases.filter { blockedRideTypeSwitches[$0]?.isOn == true }, service: sk)
    FilterConfig.setAutoAccept(autoAcceptSwitch.isOn, service: sk)
    FilterConfig.setAutoReject(autoRejectSwitch.isOn, service: sk)
    FilterConfig.setRequireConfirmBeforeAccept(requireConfirmSwitch.isOn, service: sk)
    if let s = Int(activeStartField.text ?? ""), (0...23).contains(s) { FilterConfig.setActiveHoursStart(s, service: sk) }
    if let e = Int(activeEndField.text ?? ""), (0...23).contains(e) { FilterConfig.setActiveHoursEnd(e, service: sk) }
    SyncManager.shared.syncToCloud()
    dismiss(animated: true)
  }
}

// MARK: - History View Controller

@MainActor
final class HistoryViewController: UIViewController {
  private let table = UITableView(frame: .zero, style: .insetGrouped)
  private let filterSegment = UISegmentedControl(items: ["All", "Accept", "Reject"])
  private var filterMode: HistoryFilterMode = .all

  private enum HistoryFilterMode: String {
    case all
    case accept
    case reject
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "History"
    view.backgroundColor = DestroUI.backgroundColor
    navigationController?.navigationBar.tintColor = DestroUI.accentOrange
    filterSegment.selectedSegmentIndex = 0
    filterSegment.backgroundColor = DestroUI.cardBackground
    filterSegment.selectedSegmentTintColor = DestroUI.accentOrange
    filterSegment.setTitleTextAttributes([.foregroundColor: DestroUI.textPrimary], for: .normal)
    filterSegment.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
    filterSegment.addTarget(self, action: #selector(filterSegmentChanged), for: .valueChanged)
    filterSegment.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(filterSegment)
    table.delegate = self
    table.dataSource = self
    table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    table.backgroundColor = .clear
    table.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(table)
    NSLayoutConstraint.activate([
      filterSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      filterSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      filterSegment.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      filterSegment.heightAnchor.constraint(equalToConstant: 32),
      table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      table.topAnchor.constraint(equalTo: filterSegment.bottomAnchor, constant: 8),
      table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    ])
  }

  @objc private func filterSegmentChanged() {
    switch filterSegment.selectedSegmentIndex {
    case 1: filterMode = .accept
    case 2: filterMode = .reject
    default: filterMode = .all
    }
    table.reloadData()
  }

  private var filteredEntries: [HistoryEntry] {
    let list = HistoryStore.load()
    switch filterMode {
    case .all: return list
    case .accept: return list.filter { $0.decision == "accept" }
    case .reject: return list.filter { $0.decision == "reject" }
    }
  }
}

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    let entries = filteredEntries
    return entries.isEmpty ? 1 : entries.count
  }

  private static func humanReadableReason(_ reason: String?) -> String? {
    guard let r = reason, !r.isEmpty else { return nil }
    let map: [String: String] = [
      "below_min_price": "below min trip $",
      "below_min_price_per_mile": "below min $/mile",
      "shared_ride": "shared ride",
      "too_many_stops": "too many stops",
      "auto_accept_disabled": "auto-accept off",
      "auto_reject_match": "auto-reject",
      "below_min_hourly_rate": "below min $/hr",
      "pickup_too_far": "pickup too far",
      "outside_geofence": "outside zone",
      "time_restriction": "outside hours",
      "low_passenger_rating": "low rider rating",
      "below_surge_threshold": "below surge",
      "blocked_ride_type": "blocked ride type",
      "below_ride_quality": "below ride quality",
      "meets_criteria": "met criteria"
    ]
    return map[r] ?? r.replacingOccurrences(of: "_", with: " ")
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    let entries = filteredEntries
    if entries.isEmpty {
      switch filterMode {
      case .all: cell.textLabel?.text = "No decisions yet. Go online to see accept/reject history."
      case .accept: cell.textLabel?.text = "No accepted rides for this filter."
      case .reject: cell.textLabel?.text = "No rejected rides for this filter."
      }
      cell.textLabel?.textColor = DestroUI.textSecondary
      cell.backgroundColor = DestroUI.cardBackground
      cell.selectionStyle = .none
      return cell
    }
    guard indexPath.row < entries.count else { return cell }
    let e = entries[indexPath.row]
    let df = DateFormatter()
    df.dateStyle = .short
    df.timeStyle = .short
    var text = "\(df.string(from: e.date)) · \(e.app) · $\(String(format: "%.2f", e.price))"
    if e.latencyMs > 0 { text += " · \(e.latencyMs)ms" }
    if let dec = e.decision, let reason = e.reason {
      let readable = Self.humanReadableReason(reason) ?? reason
      text += " · \(dec == "accept" ? "Accepted" : "Rejected"): \(readable)"
    }
    cell.textLabel?.text = text
    cell.textLabel?.numberOfLines = 0
    cell.textLabel?.textColor = DestroUI.textPrimary
    cell.backgroundColor = DestroUI.cardBackground
    return cell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    "Decisions"
  }
}
