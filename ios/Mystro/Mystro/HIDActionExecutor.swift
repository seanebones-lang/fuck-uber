import Foundation
import UIKit

// MARK: - HIDActionExecutor
// Injects touch events via IOHIDEvent private API (Misaka26 / jailbreak).
// Uses jitter and randomized hold/delay for anti-detection. No-op on stock iOS when API unavailable.

final class HIDActionExecutor: ActionExecutor {

  private let jitterRange: ClosedRange<CGFloat>
  private let tapHoldUs: UInt32
  private let tapDelayUsMin: UInt32
  private let tapDelayUsMax: UInt32

  init(
    jitterRange: ClosedRange<CGFloat> = -15...15,
    tapHoldUs: UInt32 = 50_000,
    tapDelayUsMin: UInt32 = 100_000,
    tapDelayUsMax: UInt32 = 300_000
  ) {
    self.jitterRange = jitterRange
    self.tapHoldUs = tapHoldUs
    self.tapDelayUsMin = tapDelayUsMin
    self.tapDelayUsMax = tapDelayUsMax
  }

  func executeAccept(at point: CGPoint, appBundleId: String) -> Bool {
    performTap(at: pointWithJitter(point))
  }

  func executeReject(at point: CGPoint, appBundleId: String) -> Bool {
    performTap(at: pointWithJitter(point))
  }

  private func pointWithJitter(_ point: CGPoint) -> CGPoint {
    let jitterX = CGFloat.random(in: jitterRange)
    let jitterY = CGFloat.random(in: jitterRange)
    return CGPoint(x: point.x + jitterX, y: point.y + jitterY)
  }

  private func performTap(at point: CGPoint) -> Bool {
    for attempt in 1...3 {
      if HIDInjector.shared.injectTap(at: point, holdMicroseconds: tapHoldUs) {
        let delayUs = UInt32.random(in: tapDelayUsMin...tapDelayUsMax)
        usleep(delayUs)
        return true
      }
      if attempt < 3 { usleep(100_000) }
    }
    return false
  }
}

// MARK: - HID Injector (Private API)

private final class HIDInjector {
  static let shared = HIDInjector()

  private var loaded = false
  private var _createDigitizerEvent: ((Double, Double, UInt64, UInt32) -> Unmanaged<AnyObject>?)?
  private var _getSystemEventDispatcher: (() -> Unmanaged<AnyObject>?)?
  private var _dispatchEvent: ((IOHIDEventSystemClientRef, IOHIDEventRef) -> Void)?

  private typealias IOHIDEventRef = OpaquePointer
  private typealias IOHIDEventSystemClientRef = OpaquePointer

  private init() {}

  func injectTap(at point: CGPoint, holdMicroseconds: UInt32) -> Bool {
    if !loaded { load() }
    guard let createEvent = _createDigitizerEvent,
          let getDispatcher = _getSystemEventDispatcher,
          let dispatch = _dispatchEvent else { return false }

    let scale = UIScreen.main.scale
    let x = Double(point.x * scale)
    let y = Double(point.y * scale)
    let time = UInt64(DispatchTime.now().uptimeNanoseconds)
    guard let eventObj = createEvent(x, y, time, holdMicroseconds)?.takeRetainedValue() else { return false }
    let event = unsafeBitCast(eventObj, to: IOHIDEventRef.self)
    defer { releaseEvent(event) }
    guard let clientObj = getDispatcher()?.takeUnretainedValue() else { return false }
    let client = unsafeBitCast(clientObj, to: IOHIDEventSystemClientRef.self)
    dispatch(client, event)
    return true
  }

  private func load() {
    let path = "/System/Library/PrivateFrameworks/IOKit.framework/IOKit"
    guard let h = dlopen(path, RTLD_NOW) else { loaded = true; return }

    if let sym = dlsym(h, "IOHIDEventCreateDigitizerFingerEvent") {
      typealias Fn = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, Double, Double, Double, Double, Double, UInt32, UInt32, UInt32, UInt32) -> Unmanaged<AnyObject>?
      let f = unsafeBitCast(sym, to: Fn.self)
      _createDigitizerEvent = { (x: Double, y: Double, time: UInt64, _: UInt32) in
        f(nil, time, 0, 0, x, y, 0, 0, 0, 1, 1, 0x01 | 0x02, 0)
      }
    }

    if _createDigitizerEvent == nil, let sym = dlsym(h, "IOHIDEventCreateDigitizerEvent") {
      typealias Fn = @convention(c) (CFAllocator?, UInt32, UInt32, UInt64) -> Unmanaged<AnyObject>?
      let f = unsafeBitCast(sym, to: Fn.self)
      _createDigitizerEvent = { (x: Double, y: Double, time: UInt64, _: UInt32) in
        f(nil, 3, 0, time)
      }
    }

    if let sym = dlsym(h, "IOHIDEventSystemClientCreate") {
      typealias Fn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
      let f = unsafeBitCast(sym, to: Fn.self)
      _getSystemEventDispatcher = { f(nil) }
    }

    if let sym = dlsym(h, "IOHIDEventSystemClientDispatchEvent") {
      typealias Fn = @convention(c) (IOHIDEventSystemClientRef, IOHIDEventRef) -> Void
      _dispatchEvent = unsafeBitCast(sym, to: Fn.self)
    }
    if _dispatchEvent == nil, let sym = dlsym(h, "IOHIDEventSystemClientDispatchEventToClient") {
      typealias Fn = @convention(c) (IOHIDEventSystemClientRef, IOHIDEventRef, IOHIDEventSystemClientRef) -> Void
      let fn = unsafeBitCast(sym, to: Fn.self)
      _dispatchEvent = { client, event in fn(client, event, client) }
    }

    loaded = true
  }

  private func releaseEvent(_ event: IOHIDEventRef) {
    let path = "/System/Library/PrivateFrameworks/IOKit.framework/IOKit"
    guard let h = dlopen(path, RTLD_NOW), let sym = dlsym(h, "IOHIDEventRelease") else { return }
    typealias Fn = @convention(c) (IOHIDEventRef) -> Void
    unsafeBitCast(sym, to: Fn.self)(event)
  }
}
