import XCTest

/// UI tests for Destro: launch app, tap GO (Go online), then tap STOP (Stop scanning) to verify critical flow.
final class DestroUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testLaunchThenGoOnlineThenStop() throws {
    let app = XCUIApplication()
    app.launch()

    // Tap GO (or "Go online") to go online
    let goButton = app.buttons["Go online"]
    if goButton.waitForExistence(timeout: 5) {
      goButton.tap()
    } else {
      // Fallback: button may show title "GO"
      let goTitleButton = app.buttons["GO"]
      XCTAssertTrue(goTitleButton.waitForExistence(timeout: 3), "GO or Go online button should exist")
      goTitleButton.tap()
    }

    // Brief wait for state to update
    sleep(1)

    // Tap STOP (or "Stop scanning") to stop
    let stopButton = app.buttons["Stop scanning"]
    if stopButton.waitForExistence(timeout: 5) {
      stopButton.tap()
    } else {
      let stopTitleButton = app.buttons["STOP"]
      XCTAssertTrue(stopTitleButton.waitForExistence(timeout: 3), "STOP or Stop scanning button should exist when online")
      stopTitleButton.tap()
    }
  }
}
