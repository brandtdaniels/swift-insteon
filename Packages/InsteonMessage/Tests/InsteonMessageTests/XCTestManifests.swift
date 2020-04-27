import XCTest

#if !canImport(ObjectiveC)

public func allTests() -> [XCTestCaseEntry] {

    return [
        testCase(StandardLengthMessageTests.allTests),
        testCase(ExtendedLengthMessageTests.allTests),
        testCase(CommandTests.allTests),
        testCase(ExtendedUserDataTests, allTests),
        testCase(InsteonIdentifierTests, allTests),
        testCase(MessageFlagsTests, allTests),
        testCase(FormatterTests, allTests),
        testCase(StandardLengthDirectCommandTests, allTests),
        testCase(ExtendedLengthDirectCommandTests, allTests)
    ]

}

#endif
