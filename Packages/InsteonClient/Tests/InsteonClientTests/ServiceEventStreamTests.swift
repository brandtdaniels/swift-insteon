import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonClient
import InsteonCore
import InsteonNetworking
import InsteonProtocol
import InsteonService
import InsteonTestSupport
import Testing

private let base = URL(string: "http://192.0.2.20:8080")!
private let secret = "tok-3f9a0c-invented"

private func path(_ http: StreamingHTTPClient) -> ServicePath {
  ServicePath(name: "lan", baseURL: base, token: secret, http: http)
}

private func frame(_ sequence: Int, _ json: String) -> String { "id: run1-\(sequence)\ndata: \(json)\n\n" }

private func status(_ sequence: Int) -> String {
  frame(sequence, #"{"version":1,"runId":"run1","sequence":\#(sequence),"kind":"statusChanged","address":"1A.2B.3C"}"#)
}

private func read(_ count: Int, from events: SequencedEvents) async throws -> [SequencedItem] {
  var items: [SequencedItem] = []
  guard count > 0 else { return items }
  for try await item in events {
    items.append(item)
    if items.count == count { break }
  }
  return items
}

@Suite("ServicePath follows the service's events as server-sent events", .timeLimit(.minutes(1)))
struct ServiceEventStreamTests {

  // Given a stream that is lost, when the connection reconnects, then it asks the service to
  // resume after the last id it saw and the client reads on without a break.
  @Test func aClientReadsEventsAcrossALostStreamThroughTheConnection() async throws {
    let first = Feed()
    let second = Feed()
    let http = StreamingHTTPClient(openings: [.stream(status: 200, first.body), .stream(status: 200, second.body)])
    let clock = TestClock()
    let connection = ClientConnection(paths: [path(http)], clock: clock)
    first.send(": connected\n\n" + status(1))
    first.fail()
    second.send(status(2))

    async let events = Array(sequence: connection.events(), count: 2)
    await clock.waitForSleeper(until: .seconds(1))
    clock.advance(by: .seconds(1))

    #expect(try await events == [.event(.statusChanged(lampAddress)), .event(.statusChanged(lampAddress))])
    let requests = await http.streamRequests
    #expect(requests.count == 2)
    #expect(requests[0].value(forHTTPHeaderField: "Last-Event-ID") == nil)
    #expect(requests[1].value(forHTTPHeaderField: "Last-Event-ID") == "run1-1")
  }

  // Given a service, when a client subscribes, then the request is a read of the events route
  // with the bearer token that accepts an event stream.
  @Test func theRequestIsAnAuthorizedGetThatAcceptsAnEventStream() async throws {
    let feed = Feed()
    let http = StreamingHTTPClient(openings: [.stream(status: 200, feed.body)])
    let calls = try await path(http).open()

    _ = try await calls.sequencedEvents(after: EventCursor(runID: "run9", sequence: 7))

    let request = try #require(await http.streamRequests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "http://192.0.2.20:8080/api/v1/events")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + secret)
    #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    #expect(request.value(forHTTPHeaderField: "Last-Event-ID") == "run9-7")
    #expect(request.value(forHTTPHeaderField: "X-Insteon-Request") == nil)
  }

  /// How the bytes of a stream arrive, and what the client reads from them.
  struct Wire: CustomTestStringConvertible, Sendable {
    let name: String
    let chunks: [[UInt8]]
    let items: [SequencedItem]
    var testDescription: String { name }
    init(_ name: String, _ text: String, items: [SequencedItem]) { self.init(name, chunks: [Array(text.utf8)], items: items) }
    init(_ name: String, chunks: [[UInt8]], items: [SequencedItem]) { self.name = name; self.chunks = chunks; self.items = items }
  }

  static let lamp = SequencedItem.event(.statusChanged(lampAddress), EventCursor(runID: "run1", sequence: 1))

  static let wires: [Wire] = [
    Wire("one whole frame", status(1), items: [lamp]),
    Wire("a frame cut in the middle of a line", chunks: [Array("id: run1".utf8), Array("-1\ndata: {\"version\":1,\"runId\":\"run1\",\"seq".utf8), Array("uence\":1,\"kind\":\"statusChanged\",\"address\":\"1A.2B.3C\"}\n\n".utf8)], items: [lamp]),
    Wire("a frame cut between two bytes of one character", chunks: {
      let text = Array(frame(1, #"{"version":1,"runId":"run1","sequence":1,"kind":"identified","address":"1A.2B.3C","productName":"Lamp é"}"#).utf8)
      let cut = text.firstIndex(of: 0xC3)! + 1
      return [Array(text[..<cut]), Array(text[cut...])]
    }(), items: [.event(.identified(lampAddress, productName: "Lamp é"), EventCursor(runID: "run1", sequence: 1))]),
    Wire("carriage returns and line feeds", status(1).replacingOccurrences(of: "\n", with: "\r\n"), items: [lamp]),
    Wire("a frame cut between a carriage return and its line feed", chunks: [Array(status(1).replacingOccurrences(of: "\n", with: "\r\n").utf8.dropLast()), [0x0A]], items: [lamp]),
    Wire("comments and keepalives", ": connected\n\n: keepalive\n\n" + status(1) + ": keepalive\n\n", items: [lamp]),
    Wire("an id with no data is a position", "id: run1-5\n\n", items: [.position(EventCursor(runID: "run1", sequence: 5))]),
    Wire("an event name is ignored, the kind is in the data", "event: message\n" + status(1), items: [lamp]),
    Wire("data over two lines is joined with a line feed", "id: run1-1\ndata: {\"version\":1,\"runId\":\"run1\",\ndata: \"sequence\":1,\"kind\":\"statusChanged\",\"address\":\"1A.2B.3C\"}\n\n", items: [lamp]),
    Wire("a field with no space after the colon", "id:run1-1\ndata:{\"version\":1,\"runId\":\"run1\",\"sequence\":1,\"kind\":\"statusChanged\",\"address\":\"1A.2B.3C\"}\n\n", items: [lamp]),
    Wire("a kind this library doesn't know is a position", frame(2, #"{"version":1,"runId":"run1","sequence":2,"kind":"futureKind"}"#), items: [.position(EventCursor(runID: "run1", sequence: 2))]),
    Wire("a version this library doesn't know is a position", frame(2, #"{"version":2,"runId":"run1","sequence":2,"kind":"statusChanged"}"#), items: [.position(EventCursor(runID: "run1", sequence: 2))]),
    Wire("a gap", "id: run2-0\ndata: {\"version\":1,\"kind\":\"gap\",\"reason\":\"tooOld\",\"runId\":\"run2\",\"sequence\":0}\n\n", items: [.gap(.tooOld, current: EventCursor(runID: "run2", sequence: 0))]),
    Wire("two frames in one chunk", status(1) + status(2), items: [lamp, .event(.statusChanged(lampAddress), EventCursor(runID: "run1", sequence: 2))])
  ]

  @Test(arguments: wires) func framesAreReadWhateverWayTheBytesArrive(wire: Wire) async throws {
    let feed = Feed()
    let http = StreamingHTTPClient(openings: [.stream(status: 200, feed.body)])
    let calls = try await path(http).open()
    let events = try await calls.sequencedEvents(after: nil)
    for chunk in wire.chunks { feed.send(bytes: chunk) }

    let items = try await read(wire.items.count, from: events)

    #expect(items == wire.items)
  }

  /// Each kind of event the service names, as it writes it.
  struct Kind: CustomTestStringConvertible, Sendable {
    let name: String
    let json: String
    let event: ServiceEvent
    var testDescription: String { name }
  }

  static let kinds: [Kind] = [
    Kind(name: "commandCompleted", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"commandCompleted","address":"1A.2B.3C","completion":{"action":"on","levelPercent":50,"result":{"version":1,"address":"1A.2B.3C","outcome":"read","status":{"group":null,"kind":"percent","value":128,"isOn":true,"percent":50,"label":null},"persistence":"saved"}}}"#,
         event: .commandCompleted(ServiceCommand(address: lampAddress, action: .on, levelPercent: 50), CommandReceipt(address: lampAddress, outcome: .read, status: DeviceStatus(group: nil, value: 128, allLinkDatabaseDelta: 0, reading: .percent(50), isOn: true), persistence: .saved))),
    Kind(name: "identified", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"identified","address":"1A.2B.3C","productName":"Example Dimmer"}"#, event: .identified(lampAddress, productName: "Example Dimmer")),
    Kind(name: "setButtonPressed", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"setButtonPressed","address":"1A.2B.3C"}"#, event: .setButtonPressed(lampAddress)),
    Kind(name: "groupCommand", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"groupCommand","address":"1A.2B.3C","group":3,"name":"on"}"#, event: .groupCommand(lampAddress, group: 3, name: "on")),
    Kind(name: "heartbeat", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"heartbeat","address":"1A.2B.3C","group":null}"#, event: .heartbeat(lampAddress, group: nil)),
    Kind(name: "modemUnavailable", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"modemUnavailable","cause":"hubUnreachable","message":"The Hub is unreachable."}"#, event: .modemUnavailable(.hubUnreachable)),
    Kind(name: "reconnected", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"reconnected"}"#, event: .modemReconnected),
    Kind(name: "notification", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"notification","address":"1A.2B.3C","name":"wet","ruleId":"rule-1","ruleName":"Basement","firedAt":"2026-11-25T10:00:00Z"}"#,
         event: .notification(ServiceNotification(ruleID: "rule-1", ruleName: "Basement", device: lampAddress, firedAt: Date(timeIntervalSince1970: 1_795_600_800), eventName: "wet"))),
    Kind(name: "schedule", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"schedule","address":"1A.2B.3C","name":"Evening","scheduleId":"sched-1","source":"schedule","outcome":"acknowledged","firedAt":"2026-11-25T10:00:00Z","nextRun":"2026-11-26T10:00:00Z"}"#,
         event: .schedule(ScheduleRun(source: .schedule, id: "sched-1", name: "Evening", device: lampAddress, outcome: .acknowledged, firedAt: Date(timeIntervalSince1970: 1_795_600_800), nextRun: Date(timeIntervalSince1970: 1_795_687_200)))),
    Kind(name: "a timer that was refused", json: #"{"version":1,"runId":"run1","sequence":1,"kind":"schedule","address":"1A.2B.3C","name":"Once","scheduleId":"timer-1","source":"timer","outcome":"refused","reason":"notLinked","firedAt":"2026-11-25T10:00:00Z","nextRun":null}"#,
         event: .schedule(ScheduleRun(source: .timer, id: "timer-1", name: "Once", device: lampAddress, outcome: .refused(.notLinked), firedAt: Date(timeIntervalSince1970: 1_795_600_800), nextRun: nil)))
  ]

  @Test(arguments: kinds) func eachKindOfEventBecomesTheServicesEvent(kind: Kind) async throws {
    let feed = Feed()
    let http = StreamingHTTPClient(openings: [.stream(status: 200, feed.body)])
    let events = try await path(http).open().sequencedEvents(after: nil)
    feed.send(frame(1, kind.json))

    let items = try await read(1, from: events)

    #expect(items == [.event(kind.event, EventCursor(runID: "run1", sequence: 1))])
  }

  /// What the service answers a subscription with when it refuses it.
  @Test(arguments: [(401, ConnectionPathError.unauthorized), (403, .forbidden), (503, .interrupted), (429, .interrupted), (404, .badResponse), (302, .badResponse)])
  func aRefusalIsTheErrorTheConnectionActsOn(status: Int, error: ConnectionPathError) async throws {
    let http = StreamingHTTPClient(openings: [.stream(status: status, Feed().body)])
    let calls = try await path(http).open()

    await #expect(throws: error) { _ = try await calls.sequencedEvents(after: nil) }
  }

  @Test func aStreamThatCannotBeOpenedIsInterrupted() async throws {
    let calls = try await path(StreamingHTTPClient(openings: [.failure])).open()

    await #expect(throws: ConnectionPathError.interrupted) { _ = try await calls.sequencedEvents(after: nil) }
  }

  // Given a connection that drops, when the events stop, then what arrived is read and then the
  // reader is told the path was interrupted.
  @Test func aStreamLostAfterItsFirstEventsDeliversThemThenThrowsInterrupted() async throws {
    let feed = Feed()
    let calls = try await path(StreamingHTTPClient(openings: [.stream(status: 200, feed.body)])).open()
    let events = try await calls.sequencedEvents(after: nil)
    feed.send(status(1))
    feed.fail()

    var iterator = events.makeAsyncIterator()

    #expect(try await iterator.next() == Self.lamp)
    await #expect(throws: ConnectionPathError.interrupted) { _ = try await iterator.next() }
  }

  @Test func aStreamTheServiceClosesEndsTheSequence() async throws {
    let feed = Feed()
    let calls = try await path(StreamingHTTPClient(openings: [.stream(status: 200, feed.body)])).open()
    let events = try await calls.sequencedEvents(after: nil)
    feed.send(status(1))
    feed.end()

    #expect(try await read(2, from: events) == [Self.lamp])
  }

  @Test func dataThatIsNotJSONIsABadResponse() async throws {
    let feed = Feed()
    let calls = try await path(StreamingHTTPClient(openings: [.stream(status: 200, feed.body)])).open()
    let events = try await calls.sequencedEvents(after: nil)
    feed.send("id: run1-1\ndata: not json\n\n")

    await #expect(throws: ConnectionPathError.badResponse) { _ = try await read(1, from: events) }
  }

  @Test func anIdThatIsNotACursorIsABadResponse() async throws {
    let feed = Feed()
    let calls = try await path(StreamingHTTPClient(openings: [.stream(status: 200, feed.body)])).open()
    let events = try await calls.sequencedEvents(after: nil)
    feed.send("id: nonsense\ndata: {\"version\":1,\"kind\":\"reconnected\"}\n\n")

    await #expect(throws: ConnectionPathError.badResponse) { _ = try await read(1, from: events) }
  }

  // Given an HTTP client that can't stream and no other path, when a client subscribes, then it is
  // told no path carries events, and the connection doesn't retry.
  @Test func anHTTPClientThatCannotStreamMakesTheSubscriptionUnsupported() async throws {
    let http = FakeHTTPClient { _ in json(#"{"version":1,"status":"ready","modem":{"connected":true,"cause":null}}"#) }
    let connection = ClientConnection(paths: [ServicePath(name: "lan", baseURL: base, token: secret, http: http)], clock: TestClock())

    await #expect(throws: ConnectionError.unsupported(paths: ["lan"])) {
      var iterator = connection.sequencedEvents(after: nil).makeAsyncIterator()
      _ = try await iterator.next()
    }
  }
}

extension Array {
  /// The first `count` elements of an asynchronous sequence.
  init<Events: AsyncSequence>(sequence: Events, count: Int) async throws where Events.Element == Element {
    self.init()
    for try await element in sequence {
      append(element)
      if self.count == count { break }
    }
  }
}
