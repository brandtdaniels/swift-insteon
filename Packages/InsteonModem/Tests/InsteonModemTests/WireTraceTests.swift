import Testing
import InsteonModem
import InsteonTestSupport

/// What a serial modem's connection traces when it is wrapped in a ``TracingConnection``.
@Suite(.timeLimit(.minutes(1)))
struct WireTraceTests {

  @Test func everyFrameWrittenIsTracedBeforeItIsSent() async throws {

    let trace = RecordingWireTrace()
    let inner = ScriptedConnection { _, _ in [] }
    let connection = TracingConnection(inner, tracer: trace)

    try await connection.write([0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x11, 0xFF])
    try await connection.write([0x02, 0x60])

    #expect(trace.events == [
      .init(direction: .written, bytes: [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x11, 0xFF]),
      .init(direction: .written, bytes: [0x02, 0x60]),
    ])
    #expect(inner.written.count == 2)

  }

  @Test func everyChunkReadIsTracedAsItArrivesAndPassedOnUnchanged() async throws {

    let trace = RecordingWireTrace()
    let inner = ScriptedConnection { _, _ in [] }
    let connection = TracingConnection(inner, tracer: trace)
    var chunks = connection.receive().makeAsyncIterator()

    inner.incoming.yield([0x02, 0x58])
    inner.incoming.yield([0x06])

    #expect(try await chunks.next() == [0x02, 0x58])
    #expect(try await chunks.next() == [0x06])
    #expect(trace.events == [
      .init(direction: .received, bytes: [0x02, 0x58]),
      .init(direction: .received, bytes: [0x06]),
    ])

  }

  @Test func aFailedWriteIsStillTracedAndStillThrows() async throws {

    struct Refused: Error {}

    let trace = RecordingWireTrace()
    let connection = TracingConnection(FailingConnection(error: Refused()), tracer: trace)

    await #expect(throws: Refused.self) { try await connection.write([0x02, 0x60]) }
    #expect(trace.events == [.init(direction: .written, bytes: [0x02, 0x60])])

  }

  @Test func withoutATracerNothingIsTraced() async throws {

    let inner = ScriptedConnection { _, _ in [0x06] }
    let connection = TracingConnection(inner, tracer: nil)
    var chunks = connection.receive().makeAsyncIterator()

    try await connection.write([0x02, 0x60])

    #expect(try await chunks.next() == [0x06])

  }

}

private struct FailingConnection: ModemConnection {

  let error: any Error

  func write(_ bytes: [UInt8]) async throws { throw error }

  func receive() -> AsyncThrowingStream<[UInt8], any Error> { AsyncThrowingStream { $0.finish() } }

}
