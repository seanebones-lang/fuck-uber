import Foundation
import UIKit

// MARK: - AccessibilityActionExecutor
// Performs accept/reject by finding the button in the frontmost app's AX tree and calling AXUIElementPerformAction(AXPress).
// Works on stock iOS when the app has Accessibility permission. Use as primary executor so offers are actually accepted/rejected.

final class AccessibilityActionExecutor: ActionExecutor {

  func executeAccept(at point: CGPoint, appBundleId: String) -> Bool {
    performButtonAction(kind: .accept)
  }

  func executeReject(at point: CGPoint, appBundleId: String) -> Bool {
    performButtonAction(kind: .reject)
  }

  private enum ButtonKind {
    case accept
    case reject
  }

  private func performButtonAction(kind: ButtonKind) -> Bool {
    guard let pid = ServiceReadinessStore.getFrontmostApplicationPID() else { return false }
    guard AXActionHelper.shared.load() else { return false }
    guard let appElement = AXActionHelper.shared.createApplication(pid) else { return false }
    defer { AXActionHelper.shared.release(appElement) }

    let matchTitle: (String) -> Bool
    switch kind {
    case .accept: matchTitle = { $0.lowercased().contains("accept") }
    case .reject: matchTitle = { $0.lowercased().contains("decline") || $0.lowercased().contains("reject") }
    }

    var found: OpaquePointer?
    AXActionHelper.shared.traverse(appElement) { element in
      guard found == nil else { return }
      guard let role = AXActionHelper.shared.copyAttributeString(element, "AXRole" as CFString),
            (role as String) == "AXButton" else { return }
      let title = (AXActionHelper.shared.copyAttributeString(element, "AXTitle" as CFString) as String?) ?? ""
      let value = (AXActionHelper.shared.copyAttributeString(element, "AXValue" as CFString) as String?) ?? ""
      let label = title + " " + value
      if matchTitle(label) {
        found = element
      }
    }
    guard let button = found else { return false }
    return AXActionHelper.shared.performAction(button, action: "AXPress" as CFString)
  }
}

// MARK: - AX Action Helper (Accessibility framework)

private typealias AXUIElementRef = OpaquePointer

private final class AXActionHelper {
  static let shared = AXActionHelper()

  private var handle: UnsafeMutableRawPointer?
  private var _createApplication: ((pid_t) -> AXUIElementRef?)?
  private var _copyAttributeValue: ((AXUIElementRef, CFString) -> CFTypeRef?)?
  private var _performAction: ((AXUIElementRef, CFString) -> Bool)?
  private var _release: ((AXUIElementRef) -> Void)?

  private init() {}

  func load() -> Bool {
    if handle != nil { return true }
    let path = "/System/Library/PrivateFrameworks/Accessibility.framework/Accessibility"
    guard let h = dlopen(path, RTLD_NOW) else { return false }
    handle = h

    typealias CreateApp = @convention(c) (pid_t) -> AXUIElementRef?
    guard let createApp = dlsym(h, "AXUIElementCreateApplication") else { return false }
    _createApplication = { pid in
      let f = unsafeBitCast(createApp, to: CreateApp.self)
      return f(pid)
    }

    typealias CopyAttr = @convention(c) (AXUIElementRef, CFString, UnsafeMutablePointer<CFTypeRef?>) -> Int32
    guard let copyAttrPtr = dlsym(h, "AXUIElementCopyAttributeValue") else { return false }
    let copyAttrFn = unsafeBitCast(copyAttrPtr, to: CopyAttr.self)
    _copyAttributeValue = { elem, attr in
      var result: CFTypeRef?
      guard copyAttrFn(elem, attr, &result) == 0, let ref = result else { return nil }
      return ref
    }

    typealias PerformActionFn = @convention(c) (AXUIElementRef, CFString) -> Int32
    guard let performPtr = dlsym(h, "AXUIElementPerformAction") else { return false }
    _performAction = { elem, action in
      let f = unsafeBitCast(performPtr, to: PerformActionFn.self)
      return f(elem, action) == 0
    }

    typealias ReleaseFn = @convention(c) (AXUIElementRef) -> Void
    guard let rel = dlsym(h, "AXUIElementRelease") else { return false }
    _release = { elem in
      let f = unsafeBitCast(rel, to: ReleaseFn.self)
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

  func performAction(_ element: AXUIElementRef, action: CFString) -> Bool {
    _performAction?(element, action) ?? false
  }

  private static let kAXChildrenAttribute = "AXChildren" as CFString

  func copyAttributeArray(_ element: AXUIElementRef) -> [AXUIElementRef]? {
    guard let value = _copyAttributeValue?(element, AXActionHelper.kAXChildrenAttribute) else { return nil }
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

  func traverse(_ element: AXUIElementRef, visit: (AXUIElementRef) -> Void) {
    visit(element)
    guard let children = copyAttributeArray(element) else { return }
    for child in children {
      traverse(child, visit: visit)
    }
  }
}
