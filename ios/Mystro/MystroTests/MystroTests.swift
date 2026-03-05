import XCTest
@testable import Mystro

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
    let decision = CriteriaEngine.evaluate(offer)
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
    let decision = CriteriaEngine.evaluate(offer)
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
    let decision = CriteriaEngine.evaluate(offer)
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
    let decision = CriteriaEngine.evaluate(offer)
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
    let decision = CriteriaEngine.evaluate(offer)
    guard case .reject(reason: .tooManyStops) = decision else {
      XCTFail("expected reject(tooManyStops), got \(decision)")
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
    let decision = daemon.decide(offer)
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
