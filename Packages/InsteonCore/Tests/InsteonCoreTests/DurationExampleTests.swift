import Testing
@testable import InsteonCore
import InsteonDeviceCatalog

/// How a value table's first duration is written as an example someone could type.
struct DurationExampleTests {

  static let examples: [(Duration, String)] = [
    (.seconds(2), "2s"),
    (.milliseconds(500), "0.5s"),
    (.milliseconds(1_500), "1.5s"),
    // Far longer than any catalog's, which a table made in code can still hold.
    (.seconds(Int64.max), "9223372036854775807s"),
  ]

  @Test(arguments: examples)
  func writesADurationOfAnyLength(duration: Duration, text: String) {

    let table = ValueTable(name: "rampRate", entries: [ValueTable.Entry(value: 0x1C, label: "Some time", duration: duration)])

    #expect(SettingPresentation.durationExample(in: table) == text)

  }

}
