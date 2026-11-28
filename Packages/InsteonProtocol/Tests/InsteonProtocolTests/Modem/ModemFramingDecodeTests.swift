import Testing
@testable import InsteonProtocol

/// The parser decodes only frames of the length it gave them, but `decode` doesn't rely on it.
struct ModemFramingDecodeTests {

  @Test(arguments: 0...8)
  func decodesAnyLengthOfACleanupFailureWithoutTrapping(_ length: Int) {

    let frame = Array(([0x02, 0x56, 0x01, 0x05, 0xC1, 0xC2, 0xC3, 0x02] as [UInt8]).prefix(length))

    let reply = ModemFraming.decode(frame)

    if length == 6 || length == 7 {

      guard case .allLinkCleanupFailed = reply else {

        Issue.record("a frame of \(length) bytes should be a cleanup failure, not \(reply)")

        return

      }

    } else {

      guard case .unrecognized = reply else {

        Issue.record("a frame of \(length) bytes should be unrecognized, not \(reply)")

        return

      }

    }

  }

  @Test(arguments: 0...8)
  func decodesAnyLengthOfAStatusReportWithoutTrapping(_ length: Int) {

    let frame = Array(([0x02, 0x58, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00] as [UInt8]).prefix(length))

    let reply = ModemFraming.decode(frame)

    #expect(reply == (length == 3 ? .allLinkCleanupStatus(isComplete: true) : .unrecognized(number: frame.count > 1 ? 0x58 : frame.last ?? 0, body: Array(frame.dropFirst(2)))))

  }

}
