import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ApiClientTests.allTests),
        testCase(AuthenticatingHTTPClientTests.allTests),
        testCase(CachingAccessTokenProviderTests.allTests),
    ]
}
#endif
