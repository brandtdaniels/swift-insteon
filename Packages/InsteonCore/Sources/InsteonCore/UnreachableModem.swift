import InsteonLinking
import InsteonModem
import InsteonProtocol

/// A modem that is never there: every operation fails with `ModemError.connectionClosed`
/// before anything is sent, and it reports nothing.
struct UnreachableModem: LinkingModem {

  func send(_ command: SerialCommand) async throws {

    throw ModemError.connectionClosed

  }

  func modemInfo() async throws -> ModemInfo {

    throw ModemError.connectionClosed

  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    throw ModemError.connectionClosed

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    throw ModemError.connectionClosed

  }

  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    throw ModemError.connectionClosed

  }

  func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    throw ModemError.connectionClosed

  }

  func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    throw ModemError.connectionClosed

  }

  func allLinkRecords() async throws -> [AllLinkRecord] {

    throw ModemError.connectionClosed

  }

  func sendAllLinkCommand(group: AllLinkGroupNumber, command: Command, timeout: Duration) async throws -> AllLinkCleanupReport {

    throw ModemError.connectionClosed

  }

  func replies() async -> AsyncStream<ModemReply> {

    AsyncStream { $0.finish() }

  }

}
