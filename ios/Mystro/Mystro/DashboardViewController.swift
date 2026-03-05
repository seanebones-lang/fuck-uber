import UIKit

// MARK: - Constants

private enum MystroUI {
  static let backgroundColor = UIColor(white: 0.06, alpha: 1)
  static let cardBackground = UIColor(white: 0.12, alpha: 1)
  static let accentOrange = UIColor(red: 1, green: 0.42, blue: 0, alpha: 1)
  static let textPrimary = UIColor.white
  static let textSecondary = UIColor(white: 0.65, alpha: 1)
  static let cornerRadius: CGFloat = 12
  static let version = "2026.2.23.861"
}

// MARK: - Dashboard

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
  private let driveTab = UIButton(type: .system)
  private let historyTab = UIButton(type: .system)

  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = MystroUI.backgroundColor
    loadState()
    setupHeader()
    setupScrollContent()
    setupBottomBar()
    updateStatusText()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    uberCard.refreshAutoState()
    lyftCard.refreshAutoState()
    uberCard.refreshReadiness()
    lyftCard.refreshReadiness()
  }

  private func loadState() {
    let d = UserDefaults.standard
    uberEnabled = d.bool(forKey: "mystro.uber.enabled")
    lyftEnabled = d.bool(forKey: "mystro.lyft.enabled")
    if d.object(forKey: "mystro.uber.enabled") == nil { d.set(true, forKey: "mystro.uber.enabled") }
    if d.object(forKey: "mystro.lyft.enabled") == nil { d.set(true, forKey: "mystro.lyft.enabled") }
  }

  private func saveState() {
    UserDefaults.standard.set(uberEnabled, forKey: "mystro.uber.enabled")
    UserDefaults.standard.set(lyftEnabled, forKey: "mystro.lyft.enabled")
  }

  private func setupHeader() {
    let safe = view.safeAreaLayoutGuide
    let menu = UIButton(type: .system)
    menu.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
    menu.tintColor = MystroUI.textPrimary
    menu.translatesAutoresizingMaskIntoConstraints = false
    menu.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
    view.addSubview(menu)

    let logo = UILabel()
    logo.text = "mystro."
    logo.font = .systemFont(ofSize: 22, weight: .semibold)
    logo.textColor = MystroUI.textPrimary
    let dot = UILabel()
    dot.text = "●"
    dot.textColor = MystroUI.accentOrange
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

    enabledLabel.text = "Enabled"
    enabledLabel.font = .systemFont(ofSize: 18, weight: .semibold)
    enabledLabel.textColor = MystroUI.textPrimary
    stack.addArrangedSubview(enabledLabel)

    uberCard.onToggle = { [weak self] on in
      self?.uberEnabled = on
      self?.saveState()
      self?.updateDaemonEnabledApps()
    }
    uberCard.onFiltersTap = { [weak self] in self?.showFilters(service: "Uber") }
    uberCard.isOn = uberEnabled
    stack.addArrangedSubview(uberCard)

    lyftCard.onToggle = { [weak self] on in
      self?.lyftEnabled = on
      self?.saveState()
      self?.updateDaemonEnabledApps()
    }
    lyftCard.onFiltersTap = { [weak self] in self?.showFilters(service: "Lyft") }
    lyftCard.isOn = lyftEnabled
    stack.addArrangedSubview(lyftCard)

    let unlinkedHeader = UIStackView()
    unlinkedHeader.axis = .horizontal
    unlinkedLabel.text = "Unlinked"
    unlinkedLabel.font = .systemFont(ofSize: 18, weight: .semibold)
    unlinkedLabel.textColor = MystroUI.textPrimary
    let hideBtn = UIButton(type: .system)
    hideBtn.setTitle("Hide", for: .normal)
    hideBtn.setTitleColor(MystroUI.textSecondary, for: .normal)
    hideBtn.titleLabel?.font = .systemFont(ofSize: 15)
    unlinkedHeader.addArrangedSubview(unlinkedLabel)
    unlinkedHeader.addArrangedSubview(UIView())
    unlinkedHeader.addArrangedSubview(hideBtn)
    stack.addArrangedSubview(unlinkedHeader)

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
    driveTab.setTitleColor(MystroUI.accentOrange, for: .normal)
    driveTab.setImage(UIImage(systemName: "steeringwheel"), for: .normal)
    driveTab.tintColor = MystroUI.accentOrange
    driveTab.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
    historyTab.setTitle("History", for: .normal)
    historyTab.setTitleColor(MystroUI.textSecondary, for: .normal)
    historyTab.setImage(UIImage(systemName: "doc.text"), for: .normal)
    historyTab.tintColor = MystroUI.textSecondary
    historyTab.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
    historyTab.addTarget(self, action: #selector(showHistory), for: .touchUpInside)

    let centerBlock = UIView()
    statusLabel.textAlignment = .center
    statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
    statusLabel.textColor = MystroUI.textSecondary
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
    goButton.backgroundColor = MystroUI.accentOrange
    goButton.layer.cornerRadius = 40
    goButton.translatesAutoresizingMaskIntoConstraints = false
    goButton.addTarget(self, action: #selector(toggleGo), for: .touchUpInside)
    view.addSubview(goButton)

    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      bar.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8),
      bar.heightAnchor.constraint(equalToConstant: 44),
      goButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      goButton.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -16),
      goButton.widthAnchor.constraint(equalToConstant: 80),
      goButton.heightAnchor.constraint(equalToConstant: 80)
    ])
  }

  private func updateStatusText() {
    if isOnline {
      statusLabel.text = "You're online\n\(MystroUI.version)"
      statusLabel.textColor = MystroUI.accentOrange
      goButton.setTitle("STOP", for: .normal)
      goButton.backgroundColor = UIColor(white: 0.25, alpha: 1)
    } else {
      statusLabel.text = "You're offline\n\(MystroUI.version)"
      statusLabel.textColor = MystroUI.textSecondary
      goButton.setTitle("GO", for: .normal)
      goButton.backgroundColor = MystroUI.accentOrange
    }
    uberCard.setOnline(isOnline)
    lyftCard.setOnline(isOnline)
  }

  private func updateDaemonEnabledApps() {
    guard isOnline, let daemon = (UIApplication.shared.delegate as? AppDelegate)?.daemon else { return }
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
    }
    isOnline.toggle()
    updateStatusText()
    let daemon = (UIApplication.shared.delegate as? AppDelegate)?.daemon
    if isOnline {
      var ids: [String] = []
      if uberEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "com.ubercab.driver") { ids.append("com.ubercab.driver") }
      if lyftEnabled && ServiceReadinessStore.isAvailableForScan(bundleId: "me.lyft.driver") { ids.append("me.lyft.driver") }
      daemon?.enabledBundleIds = ids
      if !ids.isEmpty { daemon?.startScanning() }
    } else {
      daemon?.stopScanning()
    }
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
      message: "Open at least one driver app (Uber or Lyft) from the link below and sign in. Then tap GO.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  @objc private func showHistory() {
    let vc = HistoryViewController()
    vc.view.backgroundColor = MystroUI.backgroundColor
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
    alert.addAction(UIAlertAction(title: "About Mystro \(MystroUI.version)", style: .default))
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let pop = alert.popoverPresentationController {
      pop.sourceView = view
      pop.sourceRect = CGRect(x: 30, y: 60, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func showLinkAlert(service: String) {
    let (url, appStoreURL): (URL?, URL?) = {
      switch service.lowercased() {
      case "uber": return (URL(string: "uber://"), URL(string: "https://apps.apple.com/app/uber-driver/id1131342792"))
      case "lyft": return (URL(string: "lyft://"), URL(string: "https://apps.apple.com/app/lyft-driver/id905997506"))
      case "didi": return (URL(string: "didi://"), URL(string: "https://apps.apple.com/search/didi%20driver"))
      case "doordash": return (URL(string: "doordash://"), URL(string: "https://apps.apple.com/app/doordash-driver/id947045479"))
      default: return (nil, nil)
      }
    }()
    let alert = UIAlertController(
      title: "Link \(service)",
      message: "Open the \(service) driver app to sign in. Mystro will use it when you're online.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let u = url {
      alert.addAction(UIAlertAction(title: "Open \(service)", style: .default) { [weak self] _ in
        self?.markServiceLinked(service: service)
        UIApplication.shared.open(u)
      })
    }
    if let u = appStoreURL {
      alert.addAction(UIAlertAction(title: "App Store", style: .default) { _ in
        UIApplication.shared.open(u)
      })
    }
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
}

// MARK: - Service Card (Uber / Lyft)

final class ServiceCard: UIView {
  var onToggle: ((Bool) -> Void)?
  var onFiltersTap: (() -> Void)?
  var isOn: Bool = true {
    didSet { toggle.isOn = isOn }
  }

  private let bundleId: String

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
    let base = isOnline ? "Mystro is online" : "Mystro is offline"
    statusLabel.text = "\(base) · \(readinessText)"
  }

  private let titleLabel = UILabel()
  private let statusLabel = UILabel()
  let toggle = UISwitch()
  private let filtersButton = UIButton(type: .system)
  private let autoAcceptButton = UIButton(type: .system)
  private let autoRejectButton = UIButton(type: .system)

  init(service: String, bundleId: String) {
    self.bundleId = bundleId
    super.init(frame: .zero)
    backgroundColor = MystroUI.cardBackground
    layer.cornerRadius = MystroUI.cornerRadius
    translatesAutoresizingMaskIntoConstraints = false

    titleLabel.text = "\(service) - Enabled"
    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    titleLabel.textColor = MystroUI.textPrimary
    statusLabel.text = "Mystro is offline"
    statusLabel.font = .systemFont(ofSize: 14, weight: .regular)
    statusLabel.textColor = MystroUI.textSecondary
    toggle.onTintColor = MystroUI.accentOrange
    toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
    filtersButton.setTitle("Filters", for: .normal)
    filtersButton.setTitleColor(MystroUI.textPrimary, for: .normal)
    filtersButton.setImage(UIImage(systemName: "line.3.horizontal.decrease.circle"), for: .normal)
    filtersButton.tintColor = MystroUI.textSecondary
    autoAcceptButton.setTitle(" Auto-accept", for: .normal)
    autoAcceptButton.setTitleColor(MystroUI.accentOrange, for: .normal)
    autoAcceptButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
    autoAcceptButton.tintColor = MystroUI.accentOrange
    autoRejectButton.setTitle(" Auto-reject", for: .normal)
    autoRejectButton.setTitleColor(MystroUI.accentOrange, for: .normal)
    autoRejectButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
    autoRejectButton.tintColor = MystroUI.accentOrange
    autoAcceptButton.addTarget(self, action: #selector(autoAcceptTapped), for: .touchUpInside)
    autoRejectButton.addTarget(self, action: #selector(autoRejectTapped), for: .touchUpInside)

    let topRow = UIStackView(arrangedSubviews: [titleLabel, toggle])
    topRow.axis = .horizontal
    topRow.alignment = .center
    topRow.distribution = .equalSpacing
    let filtersRow = UIStackView(arrangedSubviews: [filtersButton, UIView()])
    filtersRow.axis = .horizontal
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
    autoAcceptButton.setTitle(FilterConfig.autoAccept ? " Auto-accept" : " Auto-accept (off)", for: .normal)
    autoRejectButton.setTitle(FilterConfig.autoReject ? " Auto-reject" : " Auto-reject (off)", for: .normal)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func toggleChanged() { onToggle?(toggle.isOn) }
  @objc private func filtersTapped() { onFiltersTap?() }
  @objc private func autoAcceptTapped() {
    FilterConfig.autoAccept.toggle()
    autoAcceptButton.setTitle(FilterConfig.autoAccept ? " Auto-accept" : " Auto-accept (off)", for: .normal)
  }
  @objc private func autoRejectTapped() {
    FilterConfig.autoReject.toggle()
    autoRejectButton.setTitle(FilterConfig.autoReject ? " Auto-reject" : " Auto-reject (off)", for: .normal)
  }
}

// MARK: - Unlinked Service Card

final class UnlinkedServiceCard: UIView {
  var onTap: (() -> Void)?

  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()

  init(service: String) {
    super.init(frame: .zero)
    backgroundColor = MystroUI.cardBackground
    layer.cornerRadius = MystroUI.cornerRadius
    translatesAutoresizingMaskIntoConstraints = false
    isUserInteractionEnabled = true
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

    titleLabel.text = "\(service) - Unlinked"
    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    titleLabel.textColor = MystroUI.textPrimary
    subtitleLabel.text = "Tap to link"
    subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
    subtitleLabel.textColor = MystroUI.textSecondary
    let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    stack.axis = .vertical
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    let info = UIImageView(image: UIImage(systemName: "info.circle"))
    info.tintColor = MystroUI.textSecondary
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

final class FiltersViewController: UIViewController {
  private let service: String
  private let minPriceField = UITextField()
  private let minPerMileField = UITextField()

  init(service: String) {
    self.service = service
    super.init(nibName: nil, bundle: nil)
    title = "\(service) Filters"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = MystroUI.backgroundColor
    navigationController?.navigationBar.tintColor = MystroUI.accentOrange
    navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismissTap))
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTap))

    let minPriceLabel = UILabel()
    minPriceLabel.text = "Min trip ($)"
    minPriceLabel.textColor = MystroUI.textSecondary
    minPriceField.keyboardType = .decimalPad
    minPriceField.backgroundColor = MystroUI.cardBackground
    minPriceField.textColor = MystroUI.textPrimary
    minPriceField.layer.cornerRadius = 8
    minPriceField.text = String(format: "%.0f", FilterConfig.minPrice)
    minPriceField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
    minPriceField.leftViewMode = .always
    minPriceField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
    minPriceField.rightViewMode = .always

    let minPerMileLabel = UILabel()
    minPerMileLabel.text = "Min $/mile"
    minPerMileLabel.textColor = MystroUI.textSecondary
    minPerMileField.keyboardType = .decimalPad
    minPerMileField.backgroundColor = MystroUI.cardBackground
    minPerMileField.textColor = MystroUI.textPrimary
    minPerMileField.layer.cornerRadius = 8
    minPerMileField.text = String(format: "%.2f", FilterConfig.minPricePerMile)
    minPerMileField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
    minPerMileField.leftViewMode = .always
    minPerMileField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
    minPerMileField.rightViewMode = .always

    let stack = UIStackView(arrangedSubviews: [
      minPriceLabel, minPriceField,
      minPerMileLabel, minPerMileField
    ])
    stack.axis = .vertical
    stack.spacing = 8
    stack.setCustomSpacing(20, after: minPriceField)
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    minPriceField.heightAnchor.constraint(equalToConstant: 44).isActive = true
    minPerMileField.heightAnchor.constraint(equalToConstant: 44).isActive = true
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
    ])
  }

  @objc private func dismissTap() { dismiss(animated: true) }
  @objc private func saveTap() {
    if let p = Double(minPriceField.text ?? ""), p > 0 { FilterConfig.minPrice = p }
    if let m = Double(minPerMileField.text ?? ""), m > 0 { FilterConfig.minPricePerMile = m }
    dismiss(animated: true)
  }
}

// MARK: - History View Controller

final class HistoryViewController: UIViewController {
  private let table = UITableView(frame: .zero, style: .insetGrouped)

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "History"
    view.backgroundColor = MystroUI.backgroundColor
    navigationController?.navigationBar.tintColor = MystroUI.accentOrange
    table.delegate = self
    table.dataSource = self
    table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    table.backgroundColor = .clear
    table.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(table)
    NSLayoutConstraint.activate([
      table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    ])
  }
}

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    HistoryStore.load().count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    let entries = HistoryStore.load()
    guard indexPath.row < entries.count else { return cell }
    let e = entries[indexPath.row]
    let df = DateFormatter()
    df.dateStyle = .short
    df.timeStyle = .short
    var text = "\(df.string(from: e.date)) · \(e.app) · $\(String(format: "%.2f", e.price))"
    if e.latencyMs > 0 { text += " · \(e.latencyMs)ms" }
    if let dec = e.decision, let reason = e.reason { text += " · \(dec):\(reason)" }
    cell.textLabel?.text = text
    cell.textLabel?.textColor = MystroUI.textPrimary
    cell.backgroundColor = MystroUI.cardBackground
    return cell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    "Decisions"
  }
}
