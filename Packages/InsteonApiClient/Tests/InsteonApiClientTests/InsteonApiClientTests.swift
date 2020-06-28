import XCTest
@testable import InsteonApiClient

final class InsteonApiClientTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(InsteonApiClient().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
