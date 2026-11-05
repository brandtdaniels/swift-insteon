import InsteonLinking
import InsteonModem
import InsteonProtocol

/// A modem that passes each call to another and lists the calls in order, with everything
/// each one sends, so a test can pin the exact traffic a piece of code makes.
///
/// Listening with ``replies()`` sends nothing, so it isn't listed.
public actor RecordingModem: LinkingModem {

  /// One call to the modem and what it carried.
  public enum Call: Hashable, Sendable {

    /// A serial command.
    case send(SerialCommand)

    /// A request for the modem's own information.
    case modemInfo

    /// A standard message to a device.
    case standardRequest(StandardMessage, timeout: Duration)

    /// An extended message to a device.
    case extendedRequest(ExtendedMessage, timeout: Duration)

    /// A read of a device's whole ALL-Link database.
    case readAllLinkDatabase(InsteonAddress, timeout: Duration)

    /// A read of one record of a device's ALL-Link database.
    case readAllLinkRecord(InsteonAddress, address: UInt16, timeout: Duration)

    /// A read of the modem's records for a group and device.
    case readModemRecords(group: AllLinkGroupNumber, device: InsteonAddress)

    /// A read of the modem's whole ALL-Link database.
    case readModemDatabase

  }

  /// The modem each call goes to.
  public let base: any LinkingModem

  /// The calls so far, in order.
  public private(set) var calls: [Call] = []

  /// Creates a modem that records the calls it passes to `base`.
  ///
  /// - Parameter base: The modem each call goes to.
  public init(_ base: any LinkingModem) {

    self.base = base

  }

  /// Forgets the calls so far, so a test lists only what follows.
  public func clear() {

    calls.removeAll()

  }

  /// Records the command and sends it to the base modem.
  public func send(_ command: SerialCommand) async throws {

    calls.append(.send(command))
    try await base.send(command)

  }

  /// Records the request and asks the base modem.
  public func modemInfo() async throws -> ModemInfo {

    calls.append(.modemInfo)

    return try await base.modemInfo()

  }

  /// Records the message and sends it through the base modem.
  public func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    calls.append(.standardRequest(message, timeout: timeout))

    return try await base.request(message, timeout: timeout)

  }

  /// Records the message and sends it through the base modem.
  public func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    calls.append(.extendedRequest(message, timeout: timeout))

    return try await base.request(message, timeout: timeout)

  }

  /// Records the read and reads through the base modem.
  public func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    calls.append(.readAllLinkDatabase(device, timeout: timeout))

    return try await base.readAllLinkDatabase(of: device, timeout: timeout)

  }

  /// Records the read and reads through the base modem.
  public func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    calls.append(.readAllLinkRecord(device, address: address, timeout: timeout))

    return try await base.readAllLinkRecord(of: device, at: address, timeout: timeout)

  }

  /// Records the read and reads through the base modem.
  public func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    calls.append(.readModemRecords(group: group, device: device))

    return try await base.allLinkRecords(group: group, device: device)

  }

  /// Records the read and reads through the base modem.
  public func allLinkRecords() async throws -> [AllLinkRecord] {

    calls.append(.readModemDatabase)

    return try await base.allLinkRecords()

  }

  /// The base modem's replies, unrecorded.
  public func replies() async -> AsyncStream<ModemReply> {

    await base.replies()

  }

}
