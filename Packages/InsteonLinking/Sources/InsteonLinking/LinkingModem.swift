import InsteonModem
import InsteonProtocol

/// What ``Linker`` and ``Unlinker`` need from a modem: sending commands and messages, reading
/// devices' ALL-Link databases, and hearing what the modem reports.
///
/// `Modem` from InsteonModem conforms, over a serial port or an INSTEON Hub. Tests can
/// conform a type that keeps databases in memory.
public protocol LinkingModem: Sendable {

  /// Sends a serial command and waits for the modem to accept it.
  func send(_ command: SerialCommand) async throws

  /// Sends an extended direct message to a device and waits for the device to acknowledge it.
  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage

  /// Sends an extended direct message to a device and waits for the reply the device sends
  /// after acknowledging it.
  func request<Reply: Sendable>(
    _ message: ExtendedMessage,
    awaitingReply reply: @escaping @Sendable (ReceivedMessage) -> Reply?,
    timeout: Duration
  ) async throws -> Reply

  /// Reads every record in a device's ALL-Link database, ending with the record that marks
  /// the end of the database.
  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse]

  /// Returns a stream of everything the modem sends after this call.
  func replies() async -> AsyncStream<ModemReply>

}

extension Modem: LinkingModem {}
