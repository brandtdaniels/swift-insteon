import XCTest

#if !canImport(ObjectiveC)

public func allTests() -> [XCTestCaseEntry] {

    return [
        testCase(BasicAuthenticationHTTPClientTests.allTests),
        testCase(URLSessionHTTPClientTests.allTests)
    ]

}

#endif
