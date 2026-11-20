import Foundation
import Testing
@testable import InsteonPluginKit

/// Reading the service's event stream, however the bytes are split.
@Suite(.timeLimit(.minutes(1)))
struct ServerSentEventParserTests {
  private func feed(_ chunks: [String]) -> [ServerSentEvent] {
    var parser = ServerSentEventParser()
    return chunks.flatMap { parser.feed(Data($0.utf8)) }
  }

  @Test func aBlockWithAnIdAndDataIsOneEvent() {
    #expect(feed(["id: run-3\ndata: {\"kind\":\"x\"}\n\n"]) == [ServerSentEvent(id: "run-3", data: #"{"kind":"x"}"#)])
  }

  @Test func aBlockSplitAnywhereGivesTheSameEvent() {
    let whole = "id: run-3\ndata: {\"kind\":\"x\"}\n\n"
    for split in 1..<whole.utf8.count {
      let bytes = Array(whole.utf8)
      let chunks = [String(decoding: bytes[..<split], as: UTF8.self), String(decoding: bytes[split...], as: UTF8.self)]
      #expect(feed(chunks) == [ServerSentEvent(id: "run-3", data: #"{"kind":"x"}"#)], "split at \(split)")
    }
  }

  @Test func aCommentBlockIsAnEventThatCarriesOnlyItsText() {
    #expect(feed([": connected\n\n", ": keepalive\n\n"]) == [ServerSentEvent(id: nil, data: nil, comment: "connected"), ServerSentEvent(id: nil, data: nil, comment: "keepalive")])
  }

  @Test func aCommentInsideABlockDoesNotChangeIt() {
    #expect(feed(["id: a-1\n: note\ndata: 1\n\n"]) == [ServerSentEvent(id: "a-1", data: "1")])
  }

  @Test func eventsAreReadInOrderAcrossBlocks() {
    let events = feed(["id: a-1\ndata: 1\n\n: keepalive\n\nid: a-2\ndata: 2\n\n"]).filter { $0.comment == nil }
    #expect(events.map(\.id) == ["a-1", "a-2"])
    #expect(events.map(\.data) == ["1", "2"])
  }

  @Test func carriageReturnsAndMultipleDataLinesAreHandled() {
    #expect(feed(["id: a-1\r\ndata: one\r\ndata: two\r\n\r\n"]) == [ServerSentEvent(id: "a-1", data: "one\ntwo")])
  }

  @Test func aBlockWithAnIdAndNoDataSetsThePlace() {
    #expect(feed(["id: a-9\n\n"]) == [ServerSentEvent(id: "a-9", data: nil)])
  }

  @Test func anIncompleteBlockWaitsForItsEnd() {
    var parser = ServerSentEventParser()
    #expect(parser.feed(Data("id: a-1\ndata: 1\n".utf8)).isEmpty)
    #expect(parser.feed(Data("\n".utf8)).count == 1)
  }
}
