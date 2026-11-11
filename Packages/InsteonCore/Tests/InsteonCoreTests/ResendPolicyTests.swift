import Testing
@testable import InsteonCore

/// Whether a message is sent again after it fails, from whether sending it twice leaves the
/// device as sending it once does.
struct ResendPolicyTests {

  @Test func resendsAfterTheModemRejectsTheMessageWhateverTheEntryMarks() {

    #expect(ResendPolicy.decision(after: .modemRejected, isIdempotent: false) == .resend)
    #expect(ResendPolicy.decision(after: .modemRejected, isIdempotent: nil) == .resend)
    #expect(ResendPolicy.decision(after: .modemRejected, isIdempotent: true) == .resend)

  }

  @Test func resendsOnceAnIdempotentMessageGetsNoAcknowledgment() {

    #expect(ResendPolicy.decision(after: .noDeviceAcknowledgment, isIdempotent: true) == .resend)

  }

  @Test func reportsTheFailureOfAMessageThatIsntIdempotentAndGetsNoAcknowledgment() {

    #expect(ResendPolicy.decision(after: .noDeviceAcknowledgment, isIdempotent: false) == .doNotResend)

  }

  @Test func reportsTheFailureOfAMessageWithNoIdempotentMarkAndNoAcknowledgment() {

    #expect(ResendPolicy.decision(after: .noDeviceAcknowledgment, isIdempotent: nil) == .doNotResend)

  }

  @Test func resendsAfterABusyDeviceRejectsTheMessageWhateverTheEntryMarks() {

    #expect(ResendPolicy.decision(after: .deviceBusy, isIdempotent: false) == .resend)
    #expect(ResendPolicy.decision(after: .deviceBusy, isIdempotent: nil) == .resend)

  }

  @Test func doesNotResendAfterAnyOtherDeviceRejection() {

    #expect(ResendPolicy.decision(after: .deviceRejected, isIdempotent: true) == .doNotResend)
    #expect(ResendPolicy.decision(after: .deviceRejected, isIdempotent: false) == .doNotResend)

  }

}
