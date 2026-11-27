import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonHubClient
import InsteonModem
import InsteonNetworking
import Logging
import Testing
@testable import InsteonServerSupport

/// The server's wire trace: what it logs, how it masks addresses, and when it does nothing.
struct WireTraceTests {

  let base = ContinuousClock.now

  /// A logger that keeps the messages it is given, at trace level.
  func capture() -> (WireTraceLogger, LogLines) {

    let lines = LogLines()
    var logger = Logger(label: "trace-test") { _ in lines }
    logger.logLevel = .trace

    return (WireTraceLogger(logger: logger, maskAddresses: true, salt: 7, start: base), lines)

  }

  @Test func aWrittenFrameIsLoggedAsHexWithTheTimeSinceTheLastLine() {

    let (tracer, lines) = capture()

    tracer.trace(.written, [0x02, 0x60], at: base + .milliseconds(250))
    tracer.trace(.received, [0x02, 0x58, 0x06], at: base + .milliseconds(1500))

    #expect(lines.messages.count == 2)
    #expect(lines.messages[0] == "+0.250s serial write 02 60")
    #expect(lines.messages[1] == "+1.250s serial read 02 58 06")

  }

  @Test func aHubRequestIsLoggedWithItsPathAndAHubReadWithItsEndAndTheCursorsTreatment() {

    let (tracer, lines) = capture()

    tracer.trace(.hubRequest(path: "/3"), [0x02, 0x58], at: base)
    tracer.trace(.hubRequest(path: "/buffstatus.xml"), [], at: base + .milliseconds(10))
    tracer.trace(.hubBuffer(endIndex: 12, step: .wrapped), [0x01, 0x02], at: base + .milliseconds(20))
    tracer.trace(.hubBuffer(endIndex: 12, step: .unchanged), [], at: base + .milliseconds(530))

    #expect(lines.messages == [
      "+0.000s hub request /3 02 58",
      "+0.010s hub request /buffstatus.xml",
      "+0.010s hub read end=12 cursor=wrapped 01 02",
      "+0.510s hub read end=12 cursor=unchanged gap=0.510s",
    ])

  }

  @Test func eachLineIsLoggedAtTraceLevelOnly() {

    let (tracer, lines) = capture()

    tracer.trace(.written, [0x02, 0x60], at: base)

    #expect(lines.levels == [.trace])

  }

  @Test func anAddressIsReplacedByTheSameTagWhereverItAppears() {

    let (tracer, lines) = capture()
    let device: [UInt8] = [0x1A, 0x2B, 0x3C]
    let modem: [UInt8] = [0x11, 0x22, 0x33]

    tracer.trace(.written, [0x02, 0x62] + device + [0x0F, 0x11, 0xFF], at: base)
    tracer.trace(.received, [0x02, 0x62] + device + [0x0F, 0x11, 0xFF, 0x06], at: base)
    tracer.trace(.received, [0x02, 0x50] + device + modem + [0x2B, 0x11, 0xFF], at: base)

    let tag = lines.messages[0].split(separator: " ")[5]
    #expect(tag.hasPrefix("@") && tag.count == 3)
    #expect(lines.messages[0] == "+0.000s serial write 02 62 \(tag) 0F 11 FF")
    #expect(lines.messages[1] == "+0.000s serial read 02 62 \(tag) 0F 11 FF 06")
    let modemTag = lines.messages[2].split(separator: " ")[6]
    #expect(modemTag != tag)
    #expect(lines.messages[2] == "+0.000s serial read 02 50 \(tag) \(modemTag) 2B 11 FF")
    for line in lines.messages { #expect(!line.contains("1A 2B 3C") && !line.contains("11 22 33")) }

  }

  @Test func differentAddressesGetDifferentTagsEvenWhenTheirHashesCollide() {

    let (tracer, lines) = capture()

    for last in 0...255 { tracer.trace(.written, [0x02, 0x62, 0x00, 0x00, UInt8(last), 0x0F, 0x11, 0xFF], at: base) }

    let tags = Set(lines.messages.map { $0.split(separator: " ")[5] })
    #expect(tags.count == 256)

  }

  @Test func aServerRunStartsWithAFreshSaltSoTheSameAddressHasADifferentTagInAnotherRun() {

    let frame: [UInt8] = [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x11, 0xFF]
    let tags = (UInt64(1)...8).map { salt -> String in
      var masker = AddressMasker(salt: salt)
      return masker.mask(frame, in: .outbound)
    }

    #expect(Set(tags).count > 1)

    let first = AddressMasker(), second = AddressMasker()
    #expect(first.salt != second.salt)

  }

  @Test func theFramesOfEachKindMaskTheirAddressesAndNothingElse() {

    var masker = AddressMasker(salt: 1)
    func tag(_ address: [UInt8]) -> String { masker.mask([0x02, 0x62] + address + [0x0F, 0x11, 0xFF], in: .outbound).split(separator: " ")[2].description }
    let (a, b) = (tag([0xAA, 0xBB, 0xCC]), tag([0xDD, 0xEE, 0xFF]))

    // ALL-Link Cleanup Failure Report: 02 56 group address, as a Hub 2's bench trace shows it.
    #expect(masker.mask([0x02, 0x56, 0x05, 0xAA, 0xBB, 0xCC], in: .inbound) == "02 56 05 \(a)")
    // ALL-Link Cleanup Status Report carries no address.
    #expect(masker.mask([0x02, 0x58, 0x06], in: .inbound) == "02 58 06")
    // Extended message: from and to.
    #expect(masker.mask([0x02, 0x51, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x1B, 0x2E, 0x00] + [UInt8](repeating: 0, count: 14), in: .inbound).hasPrefix("02 51 \(a) \(b) 1B 2E 00"))
    // ALL-Link record response, and Manage ALL-Link Record.
    #expect(masker.mask([0x02, 0x57, 0xE2, 0x01, 0xDD, 0xEE, 0xFF, 0x00, 0x00, 0x00], in: .inbound) == "02 57 E2 01 \(b) 00 00 00")
    #expect(masker.mask([0x02, 0x6F, 0x40, 0xE2, 0x01, 0xAA, 0xBB, 0xCC, 0x00, 0x00, 0x00], in: .outbound) == "02 6F 40 E2 01 \(a) 00 00 00")

  }

  // An invented sequence in the layout a Hub 2 sent: 02 5C like a standard message received, then
  // a failure report and a status report, then a standard message, all in one read.
  @Test func everyFrameOfARunKeepsItsStartByteAndEveryAddressIsMaskedConsistently() {

    var masker = AddressMasker(salt: 1)
    let read: [UInt8] = [0x02, 0x5C, 0xA1, 0xA2, 0xA3, 0xB1, 0xB2, 0xB3, 0x23, 0x13, 0x05, 0x02, 0x56, 0x05, 0xC1, 0xC2, 0xC3, 0x02, 0x58, 0x06, 0x02, 0x50, 0xD1, 0xD2, 0xD3, 0xE1, 0xE2, 0xE3, 0x60, 0x13, 0x05]

    let masked = masker.mask(read, in: .inbound).split(separator: " ").map(String.init)

    #expect(masked.filter { $0 == "02" }.count == 4)
    let tags = masked.filter { $0.hasPrefix("@") }
    #expect(tags.count == 5 && Set(tags).count == 5)
    #expect(masked.count == 31 - 15 + 5)
    let frames = masked.split(separator: "02").map(Array.init)
    #expect(frames.map { $0.first } == ["5C", "56", "58", "50"])
    #expect(frames[1][1] == "05" && frames[1][2].hasPrefix("@") && frames[1].count == 3)
    #expect(frames[2] == ["58", "06"])
    for hidden in ["A1", "A2", "A3", "B1", "B2", "B3", "C1", "C2", "C3", "D1", "D2", "D3", "E1", "E2", "E3"] { #expect(!masked.contains(hidden)) }

    // The same read once more gives the same tags.
    #expect(masker.mask(read, in: .inbound) == masked.joined(separator: " "))

  }

  @Test func aFrameOfAnUnknownNumberDoesNotShowAnAddressSeenEarlierInTheRun() {

    var masker = AddressMasker(salt: 1)
    let seen = masker.mask([0x02, 0x62, 0xAA, 0xBB, 0xCC, 0x0F, 0x11, 0xFF], in: .outbound).split(separator: " ")[2]

    let unknown = masker.mask([0x02, 0x7F, 0x01, 0xAA, 0xBB, 0xCC, 0x02, 0x58, 0x06], in: .inbound)

    #expect(unknown == "02 7F 01 \(seen) 02 58 06")
    #expect(masker.mask([0x02, 0x7F, 0x01, 0xAA, 0xBB, 0xCD], in: .inbound) == "02 7F 01 AA BB CD")

  }

  @Test func anAddressSplitAcrossTwoReadsIsMaskedWhenItIsComplete() {

    var masker = AddressMasker(salt: 1)
    let whole = masker.mask([0x02, 0x50, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF], in: .inbound)
    var split = AddressMasker(salt: 1)

    let first = split.mask([0x02, 0x50, 0xAA, 0xBB], in: .inbound)
    let second = split.mask([0xCC, 0x11, 0x22, 0x33, 0x2B, 0x11, 0xFF], in: .inbound)

    #expect(!first.contains("AA") && !first.contains("BB"))
    #expect([first, second].filter { !$0.isEmpty }.joined(separator: " ") == whole)

  }

  // MARK: Reads with nothing new

  /// A scripted run of reads of a Hub's buffer, each `(endIndex, step, bytes)` at a time in milliseconds.
  func play(_ reads: [(Int, WireTraceBufferStep, [UInt8], Int)], through tracer: WireTraceLogger) {

    for (end, step, bytes, milliseconds) in reads { tracer.trace(.hubBuffer(endIndex: end, step: step), bytes, at: base + .milliseconds(milliseconds)) }

  }

  @Test func readsWithNothingNewAreSummarizedWhenTheNextChangeComes() {

    let (tracer, lines) = capture()

    play([
      (4, .advanced, [0x02, 0x58, 0x06, 0x01], 0),
      (4, .unchanged, [], 500), (4, .unchanged, [], 1000), (4, .unchanged, [], 1500), (4, .unchanged, [], 2000),
      (6, .advanced, [0x02, 0x58], 2500),
    ], through: tracer)

    #expect(lines.messages == [
      "+0.000s hub read end=4 cursor=advanced 02 58 06 01",
      "+0.500s hub read end=4 cursor=unchanged gap=0.500s",
      "+1.500s hub read unchanged x3 for 1.500s",
      "+0.500s hub read end=6 cursor=advanced gap=0.500s 02 58",
    ])

  }

  @Test func aLongQuietStretchIsSummarizedEveryThirtySecondsAndStaysReadable() {

    let (tracer, lines) = capture()

    play([(4, .advanced, [0x01], 0)] + (1...200).map { (4, WireTraceBufferStep.unchanged, [UInt8](), $0 * 500) }, through: tracer)

    // 100 seconds of reads: the first, then a summary each 30 seconds, not 200 lines.
    #expect(lines.messages.count < 10)
    #expect(lines.messages.filter { $0.contains("unchanged x") }.count == 3)
    #expect(lines.messages.filter { $0.contains("cursor=unchanged") }.count == 1)

  }

  @Test func theFirstQuietReadAfterEachChangeIsLoggedAndAChangeWithNoQuietReadsAddsNoSummary() {

    let (tracer, lines) = capture()

    play([
      (2, .advanced, [1, 2], 0), (4, .advanced, [3, 4], 500),
      (4, .unchanged, [], 1000), (6, .advanced, [5, 6], 1500),
      (6, .unchanged, [], 2000),
    ], through: tracer)

    #expect(lines.messages.filter { $0.contains("unchanged x") }.isEmpty)
    #expect(lines.messages.filter { $0.contains("cursor=unchanged") }.count == 2)

  }

  @Test func aRequestEndsTheQuietStretchSoTheSummaryComesBeforeIt() {

    let (tracer, lines) = capture()

    play([(4, .advanced, [1], 0), (4, .unchanged, [], 500), (4, .unchanged, [], 1000), (4, .unchanged, [], 1500)], through: tracer)
    tracer.trace(.hubRequest(path: "/3"), [0x02, 0x60], at: base + .milliseconds(1600))

    #expect(lines.messages.suffix(2) == ["+1.000s hub read unchanged x2 for 1.000s", "+0.100s hub request /3 02 60"])

  }

  @Test func withMaskingOffTheBytesAreLoggedAsTheyAre() {

    let lines = LogLines()
    var logger = Logger(label: "trace-test") { _ in lines }
    logger.logLevel = .trace
    let tracer = WireTraceLogger(logger: logger, maskAddresses: false, salt: 7, start: base)

    tracer.trace(.written, [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x11, 0xFF], at: base)

    #expect(lines.messages == ["+0.000s serial write 02 62 1A 2B 3C 0F 11 FF"])

  }

  @Test func theHubsUserNameAndPasswordNeverReachTheLog() async throws {

    let (tracer, lines) = capture()
    let hub = Hub(endpoint: HubEndpoint(host: "hub.local"), user: "hubuser", password: "hunter2-secret", httpClient: AnsweringClient()).tracing(tracer)
    let encoded = Data("hubuser:hunter2-secret".utf8).base64EncodedString()

    try await hub.clearBuffer()
    try await hub.write([0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x11, 0xFF])
    _ = try await hub.readBuffer()

    #expect(lines.messages.count == 3)
    for line in lines.messages {
      for forbidden in ["hubuser", "hunter2", encoded, "Authorization", "Basic", "1A 2B 3C"] { #expect(!line.contains(forbidden)) }
    }

  }

  @Test func aTracerAboveTraceLevelIsNilSoNothingIsCalled() async throws {

    let counting = CountingTrace()

    let off = ServerLogging.gate(counting, level: .debug)
    let hub = Hub(endpoint: HubEndpoint(host: "hub.local"), httpClient: AnsweringClient()).tracing(off)
    try await hub.clearBuffer()
    _ = try await hub.readBuffer()

    #expect(off == nil)
    #expect(counting.count == 0)

    let on = Hub(endpoint: HubEndpoint(host: "hub.local"), httpClient: AnsweringClient()).tracing(ServerLogging.gate(counting, level: .trace))
    try await on.clearBuffer()
    #expect(counting.count == 1)

  }

  @Test(arguments: [Logger.Level.debug, .info, .notice, .warning, .error, .critical])
  func noLevelAboveTraceMakesALogger(_ level: Logger.Level) {

    #expect(ServerLogging.wireTrace(level: level, logger: Logger(label: "x"), maskAddresses: true) == nil)
    #expect(ServerLogging.wireTrace(level: .trace, logger: Logger(label: "x"), maskAddresses: true) != nil)

  }

  @Test func addressesAreMaskedUnlessTheAdministratorTurnsMaskingOff() throws {

    #expect(try ServerOptions(arguments: [], environment: [:]).traceAddresses == false)
    #expect(try ServerOptions(arguments: ["--trace-addresses"], environment: [:]).traceAddresses)
    #expect(try ServerOptions(arguments: [], environment: ["INSTEON_TRACE_ADDRESSES": "1"]).traceAddresses)
    #expect(try ServerOptions(arguments: [], environment: ["INSTEON_TRACE_ADDRESSES": "0"]).traceAddresses == false)

  }

  @Test func theOptionWinsOverTheEnvironmentAndABadValueIsRefused() throws {

    #expect(try ServerOptions(arguments: ["--trace-addresses"], environment: ["INSTEON_TRACE_ADDRESSES": "0"]).traceAddresses)
    #expect(throws: ServerOptionError.invalidTraceAddresses) { try ServerOptions(arguments: [], environment: ["INSTEON_TRACE_ADDRESSES": "yes"]) }
    #expect(ServerFailure(ServerOptionError.invalidTraceAddresses).code.rawValue == "trace_addresses_invalid")

  }

  @Test func theHelpNamesTheOptionAndWarnsThatItIsSensitive() {

    #expect(ServerRunner.help.contains("--trace-addresses"))
    #expect(ServerRunner.help.contains("INSTEON_TRACE_ADDRESSES"))
    #expect(ServerRunner.help.contains("sensitive"))

  }

}

/// Keeps what is logged.
final class LogLines: LogHandler, @unchecked Sendable {

  // `lock` guards `entries`.
  private let lock = NSLock()

  private var entries: [(Logger.Level, String)] = []

  var logLevel: Logger.Level = .trace

  var metadata: Logger.Metadata = [:]

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  var messages: [String] { lock.withLock { entries.map(\.1) } }

  var levels: [Logger.Level] { lock.withLock { entries.map(\.0) } }

  func log(event: LogEvent) {

    lock.withLock { entries.append((event.level, "\(event.message)")) }

  }

}

private final class CountingTrace: WireTrace, @unchecked Sendable {

  private let lock = NSLock()

  private var calls = 0

  var count: Int { lock.withLock { calls } }

  func trace(_ direction: WireTraceDirection, _ bytes: [UInt8], at instant: ContinuousClock.Instant) {

    lock.withLock { calls += 1 }

  }

}

/// Answers every request with an empty buffer page.
private struct AnsweringClient: HTTPClient {

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    HTTPResponse(statusCode: 200, body: Data("<response><BS>0000</BS></response>".utf8))

  }

}
