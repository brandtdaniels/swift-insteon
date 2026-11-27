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

    // ALL-Link Cleanup Failure Report: 02 56 data group address.
    #expect(masker.mask([0x02, 0x56, 0x01, 0x05, 0xAA, 0xBB, 0xCC], in: .inbound) == "02 56 01 05 \(a)")
    // ALL-Link Cleanup Status Report carries no address.
    #expect(masker.mask([0x02, 0x58, 0x06], in: .inbound) == "02 58 06")
    // Extended message: from and to.
    #expect(masker.mask([0x02, 0x51, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x1B, 0x2E, 0x00] + [UInt8](repeating: 0, count: 14), in: .inbound).hasPrefix("02 51 \(a) \(b) 1B 2E 00"))
    // ALL-Link record response, and Manage ALL-Link Record.
    #expect(masker.mask([0x02, 0x57, 0xE2, 0x01, 0xDD, 0xEE, 0xFF, 0x00, 0x00, 0x00], in: .inbound) == "02 57 E2 01 \(b) 00 00 00")
    #expect(masker.mask([0x02, 0x6F, 0x40, 0xE2, 0x01, 0xAA, 0xBB, 0xCC, 0x00, 0x00, 0x00], in: .outbound) == "02 6F 40 E2 01 \(a) 00 00 00")

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
