import Foundation
import Testing
@testable import InsteonService

@Suite(.timeLimit(.minutes(1)))
struct HubClockDriftTests {
  private let zone = TimeZone(identifier: "America/Los_Angeles")!
  /// 14:38:39 in Los Angeles on November 20, 2026.
  private let date = Date(timeIntervalSince1970: 1_795_214_319)

  @Test func aHubWithinAMinuteIsNotReported() {
    #expect(HubClockDrift.seconds(reported: "11/20/2026 02:38:39 PM", in: zone, at: date) == nil)
    #expect(HubClockDrift.seconds(reported: "11/20/2026 02:39:39 PM", in: zone, at: date) == nil)
  }

  @Test func aHubMoreThanAMinuteAwayIsReportedWithTheSignOfItsDifference() {
    #expect(HubClockDrift.seconds(reported: "11/20/2026 02:41:39 PM", in: zone, at: date) == 180)
    #expect(HubClockDrift.seconds(reported: "11/20/2026 02:35:39 PM", in: zone, at: date) == -180)
  }

  @Test func theHubsLocalTimeIsReadInTheHomesZone() {
    // The same wall time in New York is three hours earlier in UTC than in Los Angeles.
    let newYork = TimeZone(identifier: "America/New_York")!
    #expect(HubClockDrift.seconds(reported: "11/20/2026 02:38:39 PM", in: newYork, at: date) == -10_800)
  }

  @Test(arguments: ["", "yesterday", "2026-11-20 14:38:39", "13/40/2026 02:38:39 PM"])
  func aTimeItCannotReadIsNotReported(_ text: String) {
    #expect(HubClockDrift.seconds(reported: text, in: zone, at: date) == nil)
  }
}
