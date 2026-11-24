import Foundation
import Testing
@testable import InsteonPluginKit

/// What a notifier reads from each frame of the stream.
@Suite(.timeLimit(.minutes(1)))
struct StreamItemTests {
  private func item(id: String? = "run-4", _ json: String) -> StreamItem? { StreamItem(ServerSentEvent(id: id, data: json)) }

  @Test func aNotificationCarriesItsRuleDeviceAndTime() {
    let json = #"{"version":1,"runId":"run","sequence":4,"kind":"notification","ruleId":"basement-leak","ruleName":"Basement leak","address":"1A.2B.3C","firedAt":"2027-01-15T08:00:00Z"}"#
    #expect(item(json) == .notification(NotificationEvent(id: "run-4", ruleID: "basement-leak", ruleName: "Basement leak", address: "1A.2B.3C", firedAt: "2027-01-15T08:00:00Z", event: nil)))
  }

  @Test func aNotificationNamesItsEventOnlyWhenTheRuleIncludesDetail() {
    let json = #"{"kind":"notification","ruleId":"r","ruleName":"Leak","address":"1A.2B.3C","firedAt":"2027-01-15T08:00:00Z","name":"wet","futureField":[1,2]}"#
    guard case let .notification(notification)? = item(json) else {
      Issue.record("not a notification")
      return
    }
    #expect(notification.event == "wet")
  }

  @Test func aGapIsAGapWhateverElseItCarries() {
    #expect(item(id: "run2-7", #"{"version":1,"kind":"gap","reason":"tooOld","runId":"run2","sequence":7}"#) == .gap(id: "run2-7"))
  }

  @Test(arguments: [#"{"kind":"commandCompleted","address":"1A.2B.3C"}"#, #"{"kind":"somethingNew"}"#, #"{"kind":"notification","ruleId":"r"}"#, "not json", "[]"])
  func anythingElseIsIgnoredButKeepsItsPlace(_ json: String) {
    #expect(item(json) == .other(id: "run-4"))
  }

  @Test func theGreetingMeansTheStreamIsOpenAndAKeepaliveMeansNothing() {
    #expect(StreamItem(ServerSentEvent(id: nil, data: nil, comment: "connected")) == .connected)
    #expect(StreamItem(ServerSentEvent(id: nil, data: nil, comment: "keepalive")) == nil)
  }

  @Test func aBlockWithoutDataOrIdIsNothing() {
    #expect(StreamItem(ServerSentEvent(id: nil, data: nil)) == nil)
    #expect(StreamItem(ServerSentEvent(id: "run-5", data: nil)) == .other(id: "run-5"))
  }

  @Test func positionsOrderWithinOneRunOnly() throws {
    let low = try #require(StreamPosition("abc-3")), high = try #require(StreamPosition("abc-10")), other = try #require(StreamPosition("xyz-99"))
    #expect(high.follows(low))
    #expect(!low.follows(high) && !low.follows(low))
    #expect(!other.follows(low) && !low.follows(other))
    #expect(StreamPosition("no-number-x") == nil && StreamPosition("-5") == nil && StreamPosition("plain") == nil)
  }
}
