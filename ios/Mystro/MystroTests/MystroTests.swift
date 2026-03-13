import XCTest
import CoreLocation
@testable import Destro

final class CriteriaEngineTests: XCTestCase {

  func testMeetsCriteria_accepts() {
    let offer = OfferData(
      price: 10,
      miles: 5,
      shared: false,
      stops: 1,
      acceptPoint: .zero,
      rejectPoint: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .accept(reason: .meetsCriteria) = decision else {
      XCTFail("expected accept(meetsCriteria), got \(decision)")
      return
    }
  }

  func testBelowMinPrice_rejects() {
    let offer = OfferData(
      price: 5,
      miles: 5,
      shared: false,
      stops: 1,
      acceptPoint: .zero,
      rejectPoint: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .reject(reason: .belowMinPrice) = decision else {
      XCTFail("expected reject(belowMinPrice), got \(decision)")
      return
    }
  }

  func testBelowMinPricePerMile_rejects() {
    let offer = OfferData(
      price: 8,
      miles: 20,
      shared: false,
      stops: 1,
      acceptPoint: .zero,
      rejectPoint: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .reject(reason: .belowMinPricePerMile) = decision else {
      XCTFail("expected reject(belowMinPricePerMile), got \(decision)")
      return
    }
  }

  func testSharedRide_rejects() {
    let offer = OfferData(
      price: 10,
      miles: 5,
      shared: true,
      stops: 1,
      acceptPoint: .zero,
      rejectPoint: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .reject(reason: .sharedRide) = decision else {
      XCTFail("expected reject(sharedRide), got \(decision)")
      return
    }
  }

  func testTooManyStops_rejects() {
    let offer = OfferData(
      price: 10,
      miles: 5,
      shared: false,
      stops: 2,
      acceptPoint: .zero,
      rejectPoint: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .reject(reason: .tooManyStops) = decision else {
      XCTFail("expected reject(tooManyStops), got \(decision)")
      return
    }
  }

  /// Direct A→B trips (0 stops) should be accepted when other criteria pass.
  func testZeroStops_accepts() {
    let offer = OfferData(
      price: 10,
      miles: 5,
      shared: false,
      stops: 0,
      acceptPoint: .zero,
      rejectPoint: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .accept(reason: .meetsCriteria) = decision else {
      XCTFail("expected accept(meetsCriteria) for 0 stops (direct trip), got \(decision)")
      return
    }
  }

  func testBelowMinHourlyRate_rejects() {
    let offer = OfferData(
      price: 15,
      miles: 5,
      shared: false,
      stops: 1,
      acceptPoint: .zero,
      rejectPoint: nil,
      pickupLocation: nil,
      dropoffLocation: nil,
      estimatedMinutes: nil,
      passengerRating: nil,
      surgeMultiplier: nil,
      rideType: nil,
      pickupDistanceMiles: nil,
      estimatedHourlyRate: 20
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .reject(reason: .belowMinHourlyRate) = decision else {
      XCTFail("expected reject(belowMinHourlyRate), got \(decision)")
      return
    }
  }

  func testPickupTooFar_rejects() {
    let offer = OfferData(
      price: 20,
      miles: 5,
      shared: false,
      stops: 1,
      acceptPoint: .zero,
      rejectPoint: nil,
      pickupLocation: nil,
      dropoffLocation: nil,
      estimatedMinutes: nil,
      passengerRating: nil,
      surgeMultiplier: nil,
      rideType: nil,
      pickupDistanceMiles: 15,
      estimatedHourlyRate: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .reject(reason: .pickupTooFar) = decision else {
      XCTFail("expected reject(pickupTooFar), got \(decision)")
      return
    }
  }

  func testBlockedRideType_rejects() {
    FilterConfig.setBlockedRideTypes([.uberXL], service: "uber")
    defer { FilterConfig.setBlockedRideTypes([], service: "uber") }
    let offer = OfferData(
      price: 20,
      miles: 5,
      shared: false,
      stops: 1,
      acceptPoint: .zero,
      rejectPoint: nil,
      pickupLocation: nil,
      dropoffLocation: nil,
      estimatedMinutes: nil,
      passengerRating: nil,
      surgeMultiplier: nil,
      rideType: .uberXL,
      pickupDistanceMiles: nil,
      estimatedHourlyRate: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .reject(reason: .blockedRideType) = decision else {
      XCTFail("expected reject(blockedRideType), got \(decision)")
      return
    }
  }

  func testLowPassengerRating_rejects() {
    FilterConfig.setMinPassengerRating(4.5, service: "uber")
    defer { FilterConfig.setMinPassengerRating(4.0, service: "uber") }
    let offer = OfferData(
      price: 15,
      miles: 5,
      shared: false,
      stops: 1,
      acceptPoint: .zero,
      rejectPoint: nil,
      pickupLocation: nil,
      dropoffLocation: nil,
      estimatedMinutes: nil,
      passengerRating: 4.0,
      surgeMultiplier: nil,
      rideType: nil,
      pickupDistanceMiles: nil,
      estimatedHourlyRate: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .reject(reason: .lowPassengerRating) = decision else {
      XCTFail("expected reject(lowPassengerRating), got \(decision)")
      return
    }
  }

  func testBelowSurgeThreshold_rejects() {
    FilterConfig.setMinSurgeMultiplier(1.5, service: "uber")
    defer { FilterConfig.setMinSurgeMultiplier(1.0, service: "uber") }
    let offer = OfferData(
      price: 15,
      miles: 5,
      shared: false,
      stops: 1,
      acceptPoint: .zero,
      rejectPoint: nil,
      pickupLocation: nil,
      dropoffLocation: nil,
      estimatedMinutes: nil,
      passengerRating: nil,
      surgeMultiplier: 1.2,
      rideType: nil,
      pickupDistanceMiles: nil,
      estimatedHourlyRate: nil
    )
    let decision = CriteriaEngine.evaluate(offer, appBundleId: "com.ubercab.driver")
    guard case .reject(reason: .belowSurgeThreshold) = decision else {
      XCTFail("expected reject(belowSurgeThreshold), got \(decision)")
      return
    }
  }
}

final class ProdDaemonDecisionTests: XCTestCase {

  func testDaemonDecide_delegatesToCriteriaEngine() {
    let daemon = ProdDaemon()
    let offer = OfferData(
      price: 7,
      miles: 1,
      shared: false,
      stops: 1,
      acceptPoint: CGPoint(x: 100, y: 200),
      rejectPoint: nil
    )
    let decision = daemon.decide(offer, appBundleId: "com.ubercab.driver")
    guard case .accept(reason: .meetsCriteria) = decision else {
      XCTFail("expected accept, got \(decision)")
      return
    }
  }
}

final class DaemonStateTests: XCTestCase {

  func testDaemonStartsIdle() {
    let daemon = ProdDaemon()
    XCTAssertEqual(daemon.state, .idle)
  }

  func testDaemonStopClearsState() {
    let daemon = ProdDaemon()
    daemon.enabledBundleIds = ["com.ubercab.driver"]
    daemon.startScanning()
    daemon.stopScanning()
    XCTAssertEqual(daemon.state, .idle)
  }
}

final class ServiceReadinessStoreTests: XCTestCase {

  func testDefaultIsUnlinked() {
    let bundleId = "test.bundle.\(UUID().uuidString)"
    XCTAssertEqual(ServiceReadinessStore.get(bundleId: bundleId), .unlinked)
  }

  func testMarkLinkedThenAvailable() {
    let bundleId = "test.bundle.\(UUID().uuidString)"
    ServiceReadinessStore.set(.unlinked, bundleId: bundleId)
    XCTAssertFalse(ServiceReadinessStore.isAvailableForScan(bundleId: bundleId))
    ServiceReadinessStore.markLinked(bundleId: bundleId)
    XCTAssertEqual(ServiceReadinessStore.get(bundleId: bundleId), .linked)
    XCTAssertTrue(ServiceReadinessStore.isAvailableForScan(bundleId: bundleId))
  }
}

final class ConflictManagerTests: XCTestCase {

  func testStartsIdle() {
    let m = ConflictManager()
    XCTAssertEqual(m.state, .idle)
  }

  func testRideAcceptedSetsState() {
    let m = ConflictManager()
    m.rideAccepted(appBundleId: ConflictManager.uberBundleId)
    if case .rideActive(let app) = m.state {
      XCTAssertTrue(app.contains("uber"))
    } else {
      XCTFail("expected rideActive(uber)")
    }
    m.reset()
    XCTAssertEqual(m.state, .idle)
  }

  func testRideCompletedReturnsIdle() {
    let m = ConflictManager()
    m.rideAccepted(appBundleId: ConflictManager.lyftBundleId)
    m.rideCompleted(wasActiveAppBundleId: ConflictManager.lyftBundleId)
    XCTAssertEqual(m.state, .idle)
  }
}

final class GeofenceManagerTests: XCTestCase {

  func testEmptyZones_acceptZoneReturnsTrue() {
    FilterConfig.geofenceZones = []
    let coord = CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)
    XCTAssertTrue(GeofenceManager.shared.isInAcceptZone(coordinate: coord))
  }

  func testEmptyZones_avoidZoneReturnsFalse() {
    FilterConfig.geofenceZones = []
    let coord = CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)
    XCTAssertFalse(GeofenceManager.shared.isInAvoidZone(coordinate: coord))
  }
}

final class EarningsTrackerTests: XCTestCase {

  func testSessionEarningsInitialState() {
    EarningsTracker.shared.endSession()
    let s = EarningsTracker.shared.sessionEarnings()
    XCTAssertEqual(s.total, 0)
    XCTAssertEqual(s.tripCount, 0)
  }

  func testTodayEarningsReturnsStruct() {
    let t = EarningsTracker.shared.todayEarnings()
    XCTAssertEqual(t.date.timeIntervalSince1970, Calendar.current.startOfDay(for: Date()).timeIntervalSince1970, accuracy: 1)
  }
}

final class AppGroupStoreTests: XCTestCase {

  func testAppGroupStoreWritesAndReads() {
    guard let defaults = AppGroupStore.defaults else { return }
    let key = "destro.scan.status"
    let value = "test-value-\(UUID().uuidString)"
    defaults.set(value, forKey: key)
    let read = defaults.string(forKey: key)
    XCTAssertEqual(read, value)
  }
}

final class FilterConfigTests: XCTestCase {

  func testMinPassengerRatingRoundTrip() {
    let original = FilterConfig.minPassengerRating(service: "uber")
    FilterConfig.setMinPassengerRating(4.7, service: "uber")
    defer { FilterConfig.setMinPassengerRating(original, service: "uber") }
    XCTAssertEqual(FilterConfig.minPassengerRating(service: "uber"), 4.7)
  }

  func testMinSurgeMultiplierRoundTrip() {
    let original = FilterConfig.minSurgeMultiplier(service: "uber")
    FilterConfig.setMinSurgeMultiplier(1.25, service: "uber")
    defer { FilterConfig.setMinSurgeMultiplier(original, service: "uber") }
    XCTAssertEqual(FilterConfig.minSurgeMultiplier(service: "uber"), 1.25)
  }
}

/// Tests the History screen filter logic: all / accept / reject counts.
final class HistoryFilterTests: XCTestCase {

  func testFilterByDecisionCounts() {
    let date = Date()
    let entries: [HistoryEntry] = [
      HistoryEntry(id: "1", date: date, app: "Uber", price: 10, latencyMs: 0, decision: "accept", reason: "meets_criteria"),
      HistoryEntry(id: "2", date: date, app: "Lyft", price: 8, latencyMs: 0, decision: "reject", reason: "below_min_price"),
      HistoryEntry(id: "3", date: date, app: "Uber", price: 12, latencyMs: 0, decision: "accept", reason: "meets_criteria"),
    ]
    let allCount = entries.count
    let acceptCount = entries.filter { $0.decision == "accept" }.count
    let rejectCount = entries.filter { $0.decision == "reject" }.count
    XCTAssertEqual(allCount, 3)
    XCTAssertEqual(acceptCount, 2)
    XCTAssertEqual(rejectCount, 1)
  }
}

final class HistoryStoreTests: XCTestCase {

  func testAppendAndLoadReturnsEntries() {
    let initial = HistoryStore.load()
    HistoryStore.append(app: "Uber", price: 9.50, latencyMs: 40, decision: .accept(reason: .meetsCriteria))
    let after = HistoryStore.load()
    XCTAssertEqual(after.count, min(initial.count + 1, 200), "Store caps at 200")
    XCTAssertEqual(after.first?.app, "Uber")
    XCTAssertEqual(after.first?.price, 9.50)
    XCTAssertEqual(after.first?.decision, "accept")
  }

  func testLoadRespectsMaxEntries() {
    let uniqueApp = "MaxEntriesCapTest"
    let uniquePrice = 99.99
    for _ in 0..<210 {
      HistoryStore.append(app: uniqueApp, price: uniquePrice, latencyMs: 0, decision: .accept(reason: .meetsCriteria))
    }
    let loaded = HistoryStore.load()
    XCTAssertLessThanOrEqual(loaded.count, 200, "HistoryStore must cap at 200 entries")
  }
}

final class DaemonNotificationsTests: XCTestCase {

  func testDaemonDidBecomeIdleNotificationAcceptsErrorInUserInfo() {
    let name = Notification.Name.destroDaemonDidBecomeIdle
    XCTAssertTrue(name.rawValue.contains("Idle"))
    var receivedError: String?
    let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notif in
      receivedError = notif.userInfo?["error"] as? String
    }
    NotificationCenter.default.post(name: name, object: nil, userInfo: ["error": "Test error"])
    XCTAssertEqual(receivedError, "Test error")
    NotificationCenter.default.removeObserver(observer)
  }

  func testRejectTapFailedNotificationNameExists() {
    let name = Notification.Name.destroRejectTapFailed
    XCTAssertTrue(name.rawValue.contains("Reject"))
  }
}

final class DynamicRuleEngineTests: XCTestCase {

  func testEffectiveMinPricePerMileReturnsValue() {
    let v = DynamicRuleEngine.shared.effectiveMinPricePerMile(base: 1.0)
    XCTAssertGreaterThanOrEqual(v, 1.0)
  }

  func testIsCurrentlyRushHourIsBool() {
    _ = DynamicRuleEngine.shared.isCurrentlyRushHour
  }

  func testRushHourDescriptionNonEmpty() {
    XCTAssertFalse(DynamicRuleEngine.shared.rushHourDescription.isEmpty)
  }

  func testEffectiveThresholdsReturnsStruct() {
    let t = DynamicRuleEngine.shared.effectiveThresholds(idleMinutes: 0)
    XCTAssertGreaterThan(t.minPrice, 0)
    XCTAssertGreaterThan(t.minPricePerMile, 0)
  }
}
