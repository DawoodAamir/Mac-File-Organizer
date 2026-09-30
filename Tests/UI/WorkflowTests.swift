import XCTest

final class WorkflowTests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  override func tearDownWithError() throws { XCUIApplication().terminate() }

  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["PORTFOLIO_UI_TEST"] = UUID().uuidString
    app.launch()
    app.activate()
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  func testPreviewMoveAndUndo() {
    let app = launch()
    XCTAssertTrue(app.buttons["Preview"].waitForExistence(timeout: 10))
    app.buttons["Preview"].click()

    XCTAssertTrue(app.staticTexts["demo.txt"].waitForExistence(timeout: 10))
    capture(app, "preview")
    app.buttons["Move files"].click()
    XCTAssertTrue(app.sheets.buttons["Move files"].waitForExistence(timeout: 5))
    app.sheets.buttons["Move files"].click()
    XCTAssertTrue(app.buttons["Undo 1 moves"].waitForExistence(timeout: 10))
    app.buttons["Undo 1 moves"].click()
    XCTAssertTrue(app.staticTexts["All recorded moves restored."].waitForExistence(timeout: 10))
  }
}
