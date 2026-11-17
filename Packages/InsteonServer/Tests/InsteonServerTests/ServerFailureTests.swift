import Foundation
import InsteonCLISupport
import InsteonCore
import InsteonHubClient
import InsteonModem
import InsteonService
import Logging
import Testing
@testable import InsteonServerSupport
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Runs the real composition (options, environment, state file, service, router and listener)
/// against a scripted modem connection, then reads what the person running the server sees.
@Suite(.timeLimit(.minutes(1)))
struct ServerFailureTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let hubPassword = "hub-secret-pass"

  /// A scratch directory for the state and environment files.
  private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-server-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func environment(in directory: URL) -> [String: String] {
    [
      "HOME": directory.path,
      "INSTEON_GATEWAY_PASSWORD": gatewayPassword,
      "INSTEON_HUB_USERNAME": "hub-user",
      "INSTEON_HUB_PASSWORD": hubPassword
    ]
  }

  private func arguments(in directory: URL, port: Int = 18080, extra: [String] = ["--hub", "192.168.1.20"]) -> [String] {
    ["--state", directory.appendingPathComponent("state.json").path, "--port", String(port)] + extra
  }

  /// What the person sees when the server run fails, or nil if it ended without failing.
  private func failure(
    arguments: [String],
    environment: [String: String],
    logger: Logger = Logger(label: "test") { _ in SwiftLogNoOpLogHandler() },
    opener: @escaping ServerRunner.ModemOpener
  ) async -> ServerFailure? {
    do {
      try await ServerRunner.run(arguments: arguments, environment: environment, logger: logger, openModem: opener)
      return nil
    } catch {
      return ServerFailure(error)
    }
  }

  private func ephemeralPort() throws -> Int {
    let descriptor = try FreePort.bind()
    defer { close(descriptor.fileDescriptor) }
    return descriptor.port
  }

  // MARK: Startup causes

  @Test func aHubThatRejectsTheCredentialsNamesTheSettingsWithoutTheirValues() async throws {
    let directory = try scratch()
    let result = await failure(arguments: arguments(in: directory, port: 18080), environment: environment(in: directory)) { _, _, _, _ in
      throw HubError.unexpectedStatus(401)
    }
    #expect(result?.code == .hubCredentialsRejected)
    #expect(result?.message == "The Hub rejected its user name and password (HTTP 401). Check INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD in the environment file.")
    #expect(result?.exitStatus == ServerFailure.configurationStatus)
    #expect(result?.message.contains(hubPassword) == false)
  }

  @Test func aHubThatForbidsTheCredentialsIsReportedTheSameWay() async throws {
    let directory = try scratch()
    let result = await failure(arguments: arguments(in: directory, port: 18080), environment: environment(in: directory)) { _, _, _, _ in
      throw HubError.unexpectedStatus(403)
    }
    #expect(result?.code == .hubCredentialsRejected)
    #expect(result?.message.contains("HTTP 403") == true)
  }

  @Test func aHubThatDoesNotAnswerAtStartupNamesItsAddress() async throws {
    let directory = try scratch()
    let result = await failure(arguments: arguments(in: directory, port: 18080), environment: environment(in: directory)) { _, _, _, _ in
      throw URLError(.cannotConnectToHost)
    }
    #expect(result?.code == .hubUnreachable)
    #expect(result?.message == "The Hub at 192.168.1.20:25105 didn't answer. Check that it's powered on and on the same network, and that --hub or INSTEON_HUB_HOST is its address.")
    #expect(result?.exitStatus == ServerFailure.unavailableStatus)
  }

  @Test func aPortThatIsAlreadyInUseNamesTheListener() async throws {
    let directory = try scratch()
    let occupied = try FreePort.bind(listening: true)
    defer { close(occupied.fileDescriptor) }
    let result = await failure(arguments: arguments(in: directory, port: occupied.port), environment: environment(in: directory)) { _, catalog, snapshot, body in
      try await ScriptedModem.open(ScriptedModem.connection(), catalog: catalog, snapshot: snapshot, body: body)
    }
    #expect(result?.code == .portInUse)
    #expect(result?.message == "127.0.0.1:\(occupied.port) is already in use. Stop the other program or choose another port with --port.")
    #expect(result?.exitStatus == ServerFailure.unavailableStatus)
  }

  @Test func anEnvironmentFileOthersCanWriteIsRefusedWithTheFixToRun() async throws {
    let directory = try scratch()
    let file = directory.appendingPathComponent("env")
    try Data("INSTEON_GATEWAY_PASSWORD=\(gatewayPassword)\n".utf8).write(to: file)
    #expect(chmod(file.path, 0o666) == 0)
    let result = await failure(arguments: arguments(in: directory, extra: ["--hub", "192.168.1.20", "--env-file", file.path]), environment: ["HOME": directory.path]) { _, _, _, _ in
      Issue.record("no modem should open")
    }
    #expect(result?.code == .environmentFileUnsafe)
    #expect(result?.message == "Others can change the environment file \(file.path), so it wasn't read. Make it readable only by you: chmod 600 \(file.path)")
    #expect(result?.message.contains(gatewayPassword) == false)
  }

  @Test func anEnvironmentFileThatIsMissingNamesThePath() async throws {
    let directory = try scratch()
    let path = directory.appendingPathComponent("missing-env").path
    let result = await failure(arguments: arguments(in: directory, extra: ["--hub", "192.168.1.20", "--env-file", path]), environment: ["HOME": directory.path]) { _, _, _, _ in }
    #expect(result?.code == .environmentFileMissing)
    #expect(result?.message == "The environment file \(path) doesn't exist. Create it, or leave out --env-file to use the default.")
  }

  @Test func anEnvironmentFileOthersCanReadIsUsedAndWarnedAboutInTheLog() async throws {
    let directory = try scratch()
    let file = directory.appendingPathComponent("env")
    try Data("INSTEON_GATEWAY_PASSWORD=short\n".utf8).write(to: file)
    #expect(chmod(file.path, 0o644) == 0)
    let capture = ServerLogCapture()
    let result = await failure(arguments: arguments(in: directory, extra: ["--hub", "192.168.1.20", "--env-file", file.path]), environment: ["HOME": directory.path], logger: capture.logger) { _, _, _, _ in }
    #expect(result?.code == .gatewayPasswordInvalid)
    let warning = try #require(capture.records.first { $0.level == .warning })
    #expect(warning.message.contains("others can read the environment file \(file.path)"))
    #expect(!warning.rendered.contains("short"))
  }

  @Test func aSerialPathThatDoesNotExistNamesThePath() async throws {
    let directory = try scratch()
    let path = directory.appendingPathComponent("no-such-modem").path
    let result = await failure(arguments: arguments(in: directory, extra: ["--serial", path]), environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword]) { target, catalog, snapshot, body in
      throw SerialPortError.cannotOpen(path: path, code: ENOENT)
    }
    #expect(result?.code == .serialPathMissing)
    #expect(result?.message == "No serial device at \(path). Plug in the modem and check the path given to --serial.")
  }

  @Test func aSerialPortThatCannotBeOpenedForAnotherReasonSaysWhy() async throws {
    let directory = try scratch()
    let path = "/dev/example-modem"
    let result = await failure(arguments: arguments(in: directory, extra: ["--serial", path]), environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword]) { _, _, _, _ in
      throw SerialPortError.cannotOpen(path: path, code: EACCES)
    }
    #expect(result?.code == .serialPortUnavailable)
    #expect(result?.message.hasPrefix("The serial port \(path) couldn't be opened") == true)
    #expect(result?.message.hasSuffix("Check that this account may use the device and that no other program has it open.") == true)
  }

  @Test func aCorruptStateFileNamesThePathAndIsLeftAlone() async throws {
    let directory = try scratch()
    let state = directory.appendingPathComponent("state.json")
    try Data("not json".utf8).write(to: state)
    let result = await failure(arguments: arguments(in: directory), environment: environment(in: directory)) { _, _, _, _ in
      Issue.record("no modem should open")
    }
    #expect(result?.code == .stateFileUnusable)
    #expect(result?.message == "The state file \(state.path) isn't in a format this server reads, so it was left as it is. Move it aside and the server starts a fresh one.")
    #expect(try String(contentsOf: state, encoding: .utf8) == "not json")
  }

  @Test(arguments: [
    (["--listen", "0.0.0.0"], ServerFailure.Code.listenAddressInvalid),
    (["--listen", "8.8.8.8"], .listenAddressInvalid),
    (["--port", "70000"], .portInvalid),
    (["--unknown", "x"], .argumentsInvalid),
    (["--state", "relative.json"], .stateFileUnusable)
  ])
  func invalidOptionsNameTheOptionToChange(_ arguments: [String], _ code: ServerFailure.Code) async throws {
    let directory = try scratch()
    let result = await failure(arguments: arguments, environment: environment(in: directory)) { _, _, _, _ in }
    #expect(result?.code == code)
    #expect(result?.exitStatus == ServerFailure.configurationStatus)
    #expect(result?.message.contains("--") == true)
  }

  @Test func aMissingGatewayPasswordNamesTheSetting() async throws {
    let directory = try scratch()
    let result = await failure(arguments: arguments(in: directory), environment: ["HOME": directory.path]) { _, _, _, _ in }
    #expect(result?.code == .gatewayPasswordMissing)
    #expect(result?.message == "INSTEON_GATEWAY_PASSWORD isn't set. Add it to the environment file; it needs 32 through 1024 bytes with no control characters.")
  }

  @Test func anErrorTheServerDoesNotKnowReportsOnlyItsType() async throws {
    let directory = try scratch()
    struct Surprise: Error, CustomStringConvertible { var description: String { "carries hub-secret-pass" } }
    let result = await failure(arguments: arguments(in: directory, port: 18080), environment: environment(in: directory)) { _, _, _, _ in throw Surprise() }
    #expect(result?.code == .unexpected)
    #expect(result?.message == "The server stopped on an unexpected error (Surprise). Check the Hub or modem, the listener and the state file.")
    #expect(result?.exitStatus == 1)
  }

  // MARK: The modem ending

  @Test func aHubThatStopsAnsweringWhileServingIsReportedAsTheModemEndingWithItsCause() async throws {
    let directory = try scratch()
    let connection = ScriptedModem.connection(ending: .fails(HubStoppedAnswering(underlyingError: URLError(.timedOut))))
    let result = await failure(arguments: arguments(in: directory, port: try ephemeralPort()), environment: environment(in: directory)) { _, catalog, snapshot, body in
      try await ScriptedModem.open(connection, catalog: catalog, snapshot: snapshot, body: body)
    }
    #expect(result?.code == .modemConnectionEnded)
    #expect(result?.message == "The modem connection ended: \(InsteonErrorDescription.hubStoppedAnsweringInline). Restart the server after checking the Hub or modem.")
    #expect(result?.exitStatus == ServerFailure.unavailableStatus)
  }

  @Test func anyReaderFailureWhileServingIsReportedAsTheModemEndingWithItsCause() async throws {
    let directory = try scratch()
    let connection = ScriptedModem.connection(ending: .fails(HubError.unexpectedStatus(500)))
    let result = await failure(arguments: arguments(in: directory, port: try ephemeralPort()), environment: environment(in: directory)) { _, catalog, snapshot, body in
      try await ScriptedModem.open(connection, catalog: catalog, snapshot: snapshot, body: body)
    }
    #expect(result?.code == .modemConnectionEnded)
    #expect(result?.message == "The modem connection ended: The Hub answered with HTTP status 500. Restart the server after checking the Hub or modem.")
  }

  @Test func aConnectionThatClosesWithoutAnErrorIsReportedAsTheModemEnding() async throws {
    let directory = try scratch()
    let connection = ScriptedModem.connection(ending: .closes)
    let result = await failure(arguments: arguments(in: directory, port: try ephemeralPort()), environment: environment(in: directory)) { _, catalog, snapshot, body in
      try await ScriptedModem.open(connection, catalog: catalog, snapshot: snapshot, body: body)
    }
    #expect(result?.code == .modemConnectionEnded)
    #expect(result?.message == "The modem connection ended. Restart the server after checking the Hub or modem.")
  }

  // MARK: Log lines

  @Test func aFailureIsLoggedOnceWithItsCodeAndGuidedMessage() throws {
    let capture = ServerLogCapture()
    let failure = ServerFailure(HubError.unexpectedStatus(401))
    failure.record(in: capture.logger)
    let record = try #require(capture.records.first)
    #expect(capture.records.count == 1)
    #expect(record.level == .critical)
    #expect(record.message == failure.message)
    #expect(record.metadata["code"] == "hub_credentials_rejected")
    #expect(record.metadata["exit_status"] == "78")
  }
}

private enum FreePort {
  /// A loopback TCP socket bound to an ephemeral port, optionally listening.
  static func bind(listening: Bool = false) throws -> (fileDescriptor: Int32, port: Int) {
    #if canImport(Darwin)
    let stream = SOCK_STREAM
    #else
    let stream = Int32(SOCK_STREAM.rawValue)
    #endif
    let descriptor = socket(AF_INET, stream, 0)
    guard descriptor >= 0 else { throw POSIXError(.EIO) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin_or_Glibc_bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard bound == 0 else { close(descriptor); throw POSIXError(.EADDRINUSE) }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
    }
    if listening { _ = listen(descriptor, 1) }
    return (descriptor, Int(UInt16(bigEndian: address.sin_port)))
  }

  private static func Darwin_or_Glibc_bind(_ descriptor: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    #if canImport(Darwin)
    Darwin.bind(descriptor, address, length)
    #else
    Glibc.bind(descriptor, address, length)
    #endif
  }
}

/// A modem connection that answers Get IM Info and an empty ALL-Link database, then fails as told.
enum ScriptedModem {
  private static let identity: [UInt8] = [0x3A, 0x4B, 0x41, 0x03, 0x77, 0x45]

  /// How the stream of received bytes ends once the last startup answer is sent.
  enum Ending {
    case staysOpen
    case closes
    case fails(any Error)
  }

  static func connection(ending: Ending = .staysOpen) -> ScriptingConnection {
    ScriptingConnection(identity: identity, ending: ending)
  }

  static func open(_ connection: ScriptingConnection, catalog: ProductCatalog, snapshot: NetworkSnapshot, body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    try await Modem.withConnection(connection) { modem in
      try await body(DeviceNetwork(modem: modem, catalog: nil, snapshot: snapshot, hub: HubLocation(host: "192.168.1.20", port: HubLocation.defaultPort)))
    }
  }
}

final class ScriptingConnection: ModemConnection, @unchecked Sendable {
  private let stream: AsyncThrowingStream<[UInt8], any Error>
  private let incoming: AsyncThrowingStream<[UInt8], any Error>.Continuation
  private let identity: [UInt8]
  private let ending: ScriptedModem.Ending

  init(identity: [UInt8], ending: ScriptedModem.Ending) {
    var continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation!
    stream = AsyncThrowingStream { continuation = $0 }
    incoming = continuation
    self.identity = identity
    self.ending = ending
  }

  func write(_ bytes: [UInt8]) async throws {
    switch bytes.count > 1 ? bytes[1] : 0 {
    case 0x60: incoming.yield([0x02, 0x60] + identity + [0x06])
    case 0x69:
      // Get First ALL-Link Record: NAK, so the database is empty. It's the last startup command.
      incoming.yield([0x02, 0x69, 0x15])
      switch ending {
      case .staysOpen: break
      case .closes: incoming.finish()
      case let .fails(error): incoming.finish(throwing: error)
      }
    default: incoming.yield(bytes + [0x06])
    }
  }

  func receive() -> AsyncThrowingStream<[UInt8], any Error> { stream }
}

final class ServerLogCapture: @unchecked Sendable {
  struct Record {
    let level: Logger.Level
    let message: String
    let metadata: Logger.Metadata
    var rendered: String { "\(level) \(message) \(metadata)" }
  }
  private let lock = NSLock()
  private var stored: [Record] = []
  var records: [Record] { lock.withLock { stored } }
  var logger: Logger { Logger(label: "test") { _ in Handler(capture: self) } }
  fileprivate func append(_ record: Record) { lock.withLock { stored.append(record) } }

  private struct Handler: LogHandler {
    let capture: ServerLogCapture
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
      get { metadata[key] }
      set { metadata[key] = newValue }
    }
    func log(event: LogEvent) {
      capture.append(Record(level: event.level, message: event.message.description, metadata: metadata.merging(event.metadata ?? [:]) { $1 }))
    }
  }
}
