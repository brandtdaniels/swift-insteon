import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCore
import InsteonHubClient
import InsteonService
import Testing
@testable import InsteonServerSupport

/// An event stream read frame by frame. The test waits on frames arriving, never on time.
final class EventStreamReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  struct Frame: @unchecked Sendable {
    let id: String?
    let json: [String: Any]
  }

  private let lock = NSLock()
  private var pending = ""
  private let continuation: AsyncStream<Frame>.Continuation
  let frames: AsyncStream<Frame>
  /// Yields once the server has subscribed and said so, so a command sent after it is seen.
  let ready: AsyncStream<Void>
  private let readyContinuation: AsyncStream<Void>.Continuation
  private var session: URLSession?
  private var task: URLSessionDataTask?

  init(port: Int, password: String, bearer: String? = nil, lastEventID: String? = nil, query: String? = nil) {
    (frames, continuation) = AsyncStream<Frame>.makeStream()
    (ready, readyContinuation) = AsyncStream<Void>.makeStream()
    super.init()
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/v1/events" + (query.map { "?" + $0 } ?? ""))!)
    request.setValue(bearer.map { "Bearer " + $0 } ?? "Basic " + Data(("insteon:" + password).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
    if let lastEventID { request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID") }
    let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    self.session = session
    task = session.dataTask(with: request)
    task?.resume()
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock(); defer { lock.unlock() }
    pending += String(decoding: data, as: UTF8.self)
    while let end = pending.range(of: "\n\n") {
      let block = String(pending[..<end.lowerBound])
      pending.removeSubrange(..<end.upperBound)
      var id: String?
      var body: [String: Any]?
      for line in block.split(separator: "\n") {
        if line.hasPrefix("id: ") { id = String(line.dropFirst(4)) }
        if line.hasPrefix("data: ") { body = (try? JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8))) as? [String: Any] }
      }
      if let body { continuation.yield(Frame(id: id, json: body)) } else if block.hasPrefix(": connected") { readyContinuation.yield() }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    // A connection that ends before the greeting ends the wait for it, so a test fails instead of hanging.
    readyContinuation.finish()
    continuation.finish()
  }

  func close() {
    readyContinuation.finish()
    task?.cancel()
    session?.invalidateAndCancel()
    continuation.finish()
  }
}

/// The event stream through the real server, router and service over the scripted modem connection.
@Suite(.timeLimit(.minutes(2)))
struct EventSequenceServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  private func connected() async throws -> (server: RunningServer, link: HubLink) {
    let link = HubLink()
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.connect(link)])))
    _ = await server.code("modem_connected")
    return (server, link)
  }

  /// Opens a stream and returns once the server has subscribed it.
  private func stream(_ server: RunningServer, lastEventID: String? = nil, query: String? = nil) async -> EventStreamReader {
    let reader = EventStreamReader(port: server.port, password: gatewayPassword, lastEventID: lastEventID, query: query)
    var ready = reader.ready.makeAsyncIterator()
    _ = await ready.next()
    return reader
  }

  private func commands(_ count: Int, on server: RunningServer) async throws {
    for index in 0..<count {
      let result = try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: index.isMultiple(of: 2) ? #"{"action":"on"}"# : #"{"action":"off"}"#, password: gatewayPassword)
      #expect(result.status == 200)
    }
  }

  @Test func everyFrameHasAnIdAndTheRunAndNumberInItsData() async throws {
    let (server, _) = try await connected()
    let reader = await stream(server)
    var frames = reader.frames.makeAsyncIterator()
    // The reader is subscribed once the server has sent its first bytes; a command's completion then arrives numbered.
    try await commands(1, on: server)
    let frame = try #require(await frames.next())
    #expect(frame.json["kind"] as? String == "commandCompleted")
    let run = try #require(frame.json["runId"] as? String)
    #expect(frame.json["sequence"] as? Int != nil)
    #expect(frame.id == "\(run)-\(frame.json["sequence"] as! Int)")
    reader.close()
    await server.stop()
  }

  @Test func aReconnectWithLastEventIDGetsWhatItMissedAndNoGap() async throws {
    let (server, _) = try await connected()
    let first = await stream(server)
    var seen = first.frames.makeAsyncIterator()
    try await commands(1, on: server)
    let one = try #require(await seen.next())
    first.close()
    try await commands(2, on: server)
    let second = await stream(server, lastEventID: one.id)
    var resumed = second.frames.makeAsyncIterator()
    let two = try #require(await resumed.next())
    let three = try #require(await resumed.next())
    let base = one.json["sequence"] as! Int
    #expect(two.json["sequence"] as? Int == base + 1)
    #expect(three.json["sequence"] as? Int == base + 2)
    #expect(two.json["kind"] as? String == "commandCompleted")
    #expect(three.json["kind"] as? String == "commandCompleted")
    second.close()
    await server.stop()
  }

  @Test func theQueryParameterResumesLikeTheHeader() async throws {
    let (server, _) = try await connected()
    let first = await stream(server)
    var seen = first.frames.makeAsyncIterator()
    try await commands(1, on: server)
    let one = try #require(await seen.next())
    first.close()
    try await commands(1, on: server)
    let second = await stream(server, query: "lastEventId=" + one.id!)
    var resumed = second.frames.makeAsyncIterator()
    let next = try #require(await resumed.next())
    #expect(next.json["sequence"] as? Int == (one.json["sequence"] as! Int) + 1)
    second.close()
    await server.stop()
  }

  @Test func aClientFromAnotherRunGetsAGapNamingTheCurrentRunThenLiveEvents() async throws {
    let (server, _) = try await connected()
    let reader = await stream(server, lastEventID: "feedbeef-3")
    var frames = reader.frames.makeAsyncIterator()
    let gap = try #require(await frames.next())
    #expect(gap.json["kind"] as? String == "gap")
    #expect(gap.json["reason"] as? String == "otherRun")
    let run = try #require(gap.json["runId"] as? String)
    #expect(run != "feedbeef")
    #expect(gap.id == "\(run)-\(gap.json["sequence"] as! Int)")
    try await commands(1, on: server)
    var live = try #require(await frames.next())
    // The gap may be followed by the announcement of the modem's state; the command's completion follows.
    while live.json["kind"] as? String != "commandCompleted" { live = try #require(await frames.next()) }
    #expect(live.json["runId"] as? String == run)
    reader.close()
    await server.stop()
  }

  @Test func aRestartedServerIsAnotherRun() async throws {
    let (first, _) = try await connected()
    let reader = await stream(first)
    var seen = reader.frames.makeAsyncIterator()
    try await commands(1, on: first)
    let before = try #require(await seen.next())
    reader.close()
    await first.stop()

    let (second, _) = try await connected()
    let resumed = await stream(second, lastEventID: before.id)
    var frames = resumed.frames.makeAsyncIterator()
    let gap = try #require(await frames.next())
    #expect(gap.json["kind"] as? String == "gap")
    #expect(gap.json["reason"] as? String == "otherRun")
    #expect(gap.json["runId"] as? String != before.json["runId"] as? String)
    resumed.close()
    await second.stop()
  }

  @Test func aClientTooFarBehindGetsAGapAndOneJustInsideTheBufferDoesNot() async throws {
    let (server, _) = try await connected()
    let first = await stream(server)
    var seen = first.frames.makeAsyncIterator()
    try await commands(1, on: server)
    let one = try #require(await seen.next())
    first.close()
    let run = one.json["runId"] as! String
    let base = one.json["sequence"] as! Int
    try await commands(300, on: server)
    let behind = await stream(server, lastEventID: one.id)
    var frames = behind.frames.makeAsyncIterator()
    let gap = try #require(await frames.next())
    #expect(gap.json["kind"] as? String == "gap")
    #expect(gap.json["reason"] as? String == "tooOld")
    #expect(gap.json["runId"] as? String == run)
    #expect(gap.json["sequence"] as? Int == base + 300)
    behind.close()

    // The newest 256 events are kept, so a client at the number just below the oldest kept resumes.
    let edge = await stream(server, lastEventID: "\(run)-\(base + 300 - 256)")
    var edgeFrames = edge.frames.makeAsyncIterator()
    let firstKept = try #require(await edgeFrames.next())
    #expect(firstKept.json["kind"] as? String == "commandCompleted")
    #expect(firstKept.json["sequence"] as? Int == base + 300 - 255)
    edge.close()
    await server.stop()
  }

  @Test func aClientAheadOfTheRunGetsAGap() async throws {
    let (server, _) = try await connected()
    let first = await stream(server)
    var seen = first.frames.makeAsyncIterator()
    try await commands(1, on: server)
    let one = try #require(await seen.next())
    first.close()
    let run = one.json["runId"] as! String
    let ahead = await stream(server, lastEventID: "\(run)-9999")
    var frames = ahead.frames.makeAsyncIterator()
    let gap = try #require(await frames.next())
    #expect(gap.json["reason"] as? String == "ahead")
    ahead.close()
    await server.stop()
  }

  @Test func theModemGoingAwayAndComingBackAreNumberedAndResumable() async throws {
    let first = HubLink()
    let second = HubLink()
    let away = HubStoppedAnswering(underlyingError: URLError(.timedOut))
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.connect(first), .connect(second)])))
    _ = await server.code("modem_connected")
    let reader = await stream(server)
    var frames = reader.frames.makeAsyncIterator()
    first.drop(with: away)
    let down = try #require(await frames.next())
    #expect(down.json["kind"] as? String == "modemUnavailable")
    server.retries.release()
    let back = try #require(await frames.next())
    #expect(back.json["kind"] as? String == "reconnected")
    #expect(back.json["sequence"] as? Int == (down.json["sequence"] as! Int) + 1)
    // A client that saw nothing after the outage's start resumes into the reconnect without a gap.
    let resumed = await stream(server, lastEventID: down.id)
    var resumedFrames = resumed.frames.makeAsyncIterator()
    let replayed = try #require(await resumedFrames.next())
    #expect(replayed.json["kind"] as? String == "reconnected")
    resumed.close()
    reader.close()
    await server.stop()
  }
}
