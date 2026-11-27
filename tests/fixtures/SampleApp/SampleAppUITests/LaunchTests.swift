import XCTest

final class LaunchTests: XCTestCase {
    func testLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Total: 3"].waitForExistence(timeout: 10))
    }
}
