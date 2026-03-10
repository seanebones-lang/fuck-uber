import Foundation
import Security

// MARK: - Service Bundle IDs

enum ServiceBundleIds {
  static let uber = "com.ubercab.driver"
  static let lyft = "me.lyft.driver"
  static let doorDash = "com.dd.doordash.driver"
  static let walmartSpark = "com.walmart.electronicmobile"
}

// MARK: - ServiceReadiness
// Lifecycle for manual sign-in: unlinked → linked (user opened app) → ready (optional; use when we have confirmation).

enum ServiceReadiness: String, Codable, CaseIterable {
  case unlinked
  case linked
  case ready
  case degraded
}

// MARK: - ServiceReadinessStore
// Persisted per-service readiness. Used to gate GO and show status on cards.
// Optional: store auth tokens in Keychain (not UserDefaults) for linked services.

enum ServiceReadinessStore {
  private static func key(bundleId: String) -> String {
    "destro.readiness.\(bundleId)"
  }

  private static func tokenKey(bundleId: String) -> String {
    "destro.token.\(bundleId)"
  }

  static func get(bundleId: String) -> ServiceReadiness {
    guard let raw = UserDefaults.standard.string(forKey: key(bundleId: bundleId)),
          let r = ServiceReadiness(rawValue: raw) else { return .unlinked }
    return r
  }

  static func set(_ readiness: ServiceReadiness, bundleId: String) {
    UserDefaults.standard.set(readiness.rawValue, forKey: key(bundleId: bundleId))
  }

  /// Store auth token in Keychain (optional; for future API use).
  /// Never log or persist token values; Keychain is the single source of truth.
  static func setToken(_ token: Data?, bundleId: String) {
    let k = tokenKey(bundleId: bundleId)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.destro.app.tokens",
      kSecAttrAccount as String: k
    ]
    SecItemDelete(query as CFDictionary)
    if let data = token {
      var add = query
      add[kSecValueData as String] = data
      let status = SecItemAdd(add as CFDictionary, nil)
      if status != errSecSuccess {
        print("[Destro] SecItemAdd failed: \(status)")
      }
    }
  }

  static func getToken(bundleId: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.destro.app.tokens",
      kSecAttrAccount as String: tokenKey(bundleId: bundleId),
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return data
  }

  /// Call when user taps "Open Uber/Lyft" to open the driver app — mark as linked.
  static func markLinked(bundleId: String) {
    set(.linked, bundleId: bundleId)
  }

  /// Call when user taps Unlink — clear linked state so they can re-link (e.g. to driver app).
  static func markUnlinked(bundleId: String) {
    set(.unlinked, bundleId: bundleId)
  }

  /// True if we can consider this service available for scanning (linked or better).
  static func isAvailableForScan(bundleId: String) -> Bool {
    switch get(bundleId: bundleId) {
    case .unlinked: return false
    case .linked, .ready, .degraded: return true
    }
  }

  // MARK: - PID discovery (same as Mystro: Accessibility only, no special permission)

  /// Get PID of the app currently in the foreground. Uses only Accessibility (same framework as reading UI).
  /// Call after bringing the driver app to front (e.g. AppSwitcher.bringToForeground) so the returned PID is that app.
  static func getFrontmostApplicationPID() -> pid_t? {
    return tryFrontmostPIDViaAccessibility()
  }

  /// Discover PID for running app. Prefer frontmost-app PID (call after bringToForeground) so no manual PID or SpringBoard needed.
  /// Retries frontmost AX a few times so the driver app has time to become focused. Uses async delay so callers can avoid blocking.
  static func discoverPID(for bundleId: String) async -> pid_t? {
    for _ in 0..<3 {
      if let pid = tryFrontmostPIDViaAccessibility() {
        storePID(pid, bundleId: bundleId)
        return pid
      }
      try? await Task.sleep(nanoseconds: 150_000_000)  // 0.15s
    }
    if let pid = tryPrivatePIDDiscovery(bundleId: bundleId) {
      storePID(pid, bundleId: bundleId)
      return pid
    }
    return storedPID(bundleId: bundleId)
  }

  /// Synchronous discover PID. Runs the async implementation and waits; avoids Thread.sleep on the calling thread.
  /// Prefer calling `discoverPID(for:) async` from async contexts (e.g. daemon scan loop).
  static func discoverPIDSync(for bundleId: String) -> pid_t? {
    var result: pid_t?
    let sema = DispatchSemaphore(value: 0)
    Task {
      result = await discoverPID(for: bundleId)
      sema.signal()
    }
    sema.wait()
    return result
  }

  static func storedPID(bundleId: String) -> pid_t? {
    let key = "destro.pid.\(bundleId)"
    guard let n = UserDefaults.standard.object(forKey: key) as? Int32 else { return nil }
    return pid_t(exactly: n)
  }

  static func storePID(_ pid: pid_t, bundleId: String) {
    UserDefaults.standard.set(Int32(pid), forKey: "destro.pid.\(bundleId)")
  }

  private static func tryPrivatePIDDiscovery(bundleId: String) -> pid_t? {
    // SpringBoardServices (optional): works on some setups; not required when using frontmost-PID + Accessibility.
    typealias SBSProcessIDForDisplayIdentifierFn = @convention(c) (CFString, UnsafeMutablePointer<pid_t>) -> DarwinBoolean
    let frameworkPath = "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"
    guard let handle = dlopen(frameworkPath, RTLD_NOW),
          let sym = dlsym(handle, "SBSProcessIDForDisplayIdentifier") else { return nil }
    let fn = unsafeBitCast(sym, to: SBSProcessIDForDisplayIdentifierFn.self)
    let id = bundleId as CFString
    var pid: pid_t = 0
    guard fn(id, &pid) == true, pid != 0 else { return nil }
    return pid
  }

  /// Use only Accessibility framework (same as reading UI). No SpringBoardServices or manual PID needed when app is in front.
  private static func tryFrontmostPIDViaAccessibility() -> pid_t? {
    let path = "/System/Library/PrivateFrameworks/Accessibility.framework/Accessibility"
    guard let h = dlopen(path, RTLD_NOW) else { return nil }
    typealias CreateSystemWideFn = @convention(c) () -> OpaquePointer?
    typealias CopyAttrFn = @convention(c) (OpaquePointer?, CFString, UnsafeMutablePointer<CFTypeRef?>) -> Int32
    typealias GetPidFn = @convention(c) (OpaquePointer?) -> pid_t
    typealias ReleaseFn = @convention(c) (OpaquePointer?) -> Void
    guard let createSys = dlsym(h, "AXUIElementCreateSystemWide") else { return nil }
    guard let copyAttr = dlsym(h, "AXUIElementCopyAttributeValue") else { return nil }
    guard let getPid = dlsym(h, "AXUIElementGetPid") else { return nil }
    guard let release = dlsym(h, "AXUIElementRelease") else { return nil }
    let fCreate = unsafeBitCast(createSys, to: CreateSystemWideFn.self)
    let fCopy = unsafeBitCast(copyAttr, to: CopyAttrFn.self)
    let fPid = unsafeBitCast(getPid, to: GetPidFn.self)
    let fRelease = unsafeBitCast(release, to: ReleaseFn.self)
    let kAXFocusedApplicationAttribute = "AXFocusedApplication" as CFString
    guard let systemWide = fCreate() else { return nil }
    defer { fRelease(systemWide) }
    var focusedApp: CFTypeRef?
    guard fCopy(systemWide, kAXFocusedApplicationAttribute, &focusedApp) == 0,
          let app = focusedApp, let appPtr = (app as? OpaquePointer) else { return nil }
    defer { fRelease(appPtr) }
    let pid = fPid(appPtr)
    return pid != 0 ? pid : nil
  }
}
