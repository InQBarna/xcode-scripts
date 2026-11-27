import XCTest
@testable import SampleApp

final class CalculatorTests: XCTestCase {
    func testAdd() {
        XCTAssertEqual(Calculator.add(1, 2), 3)
    }
}
