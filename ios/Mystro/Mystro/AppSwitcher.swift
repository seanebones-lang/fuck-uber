import Foundation
import UIKit

// MARK: - AppSwitcher
// Controls foreground/background of driver apps via FBSSystemService / FrontBoard private APIs (Misaka26).
// No-op when private API unavailable.

final class AppSwitcher {

  static let shared = AppSwitcher()

  private var _openApplication: ((String) -> Bool)?
  private var _suspendApplication: ((String) -> Bool)?
  private var loaded = false

  private init() {}

  /// Bring app with bundleId to foreground. Returns true if call succeeded.
  func bringToForeground(bundleId: String) -> Bool {
    load()
    return _openApplication?(bundleId) ?? false
  }

  /// Send app with bundleId to background. Returns true if call succeeded.
  func sendToBackground(bundleId: String) -> Bool {
    load()
    return _suspendApplication?(bundleId) ?? false
  }

  /// Best-effort: check if app is running (e.g. via runningProcesses). May return false on stock iOS.
  func isAppRunning(bundleId: String) -> Bool {
    load()
    if _openApplication != nil {
      return true
    }
    return false
  }

  private func load() {
    if loaded { return }
    loaded = true
    let paths = [
      "/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",
      "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"
    ]
    for path in paths {
      guard let h = dlopen(path, RTLD_NOW) else { continue }
      if let sym = dlsym(h, "FBSSystemServiceOpenApplication") ?? dlsym(h, "SBSLaunchApplicationWithIdentifier") {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Int32
        let f = unsafeBitCast(sym, to: Fn.self)
        _openApplication = { bid in
          bid.withCString { cStr in
            f(nil, cStr, nil) == 0
          }
        }
        break
      }
    }
    for path in paths {
      guard let h = dlopen(path, RTLD_NOW) else { continue }
      if let sym = dlsym(h, "FBSSystemServiceSuspendApplication") ?? dlsym(h, "SBSSuspendApplication") {
        typealias Fn = @convention(c) (UnsafePointer<CChar>?) -> Int32
        let f = unsafeBitCast(sym, to: Fn.self)
        _suspendApplication = { bid in
          bid.withCString { cStr in
            f(cStr) == 0
          }
        }
        break
      }
    }
  }
}
