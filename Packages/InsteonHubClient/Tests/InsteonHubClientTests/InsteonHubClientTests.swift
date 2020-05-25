import XCTest
@testable import InsteonHubClient

final class InsteonHubClientTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(InsteonHubClient().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
