import XCTest
@testable import RxComposableArchitecture

final class RxComposableArchitectureTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(RxComposableArchitecture().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
