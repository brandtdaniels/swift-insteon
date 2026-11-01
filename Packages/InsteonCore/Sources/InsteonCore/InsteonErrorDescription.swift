import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonHubClient
import InsteonHubDiscovery
import InsteonLinking
import InsteonModem
import InsteonNetworking
import InsteonProtocol

/// One-line English descriptions of the errors InsteonCore's operations throw from the
/// lower-level modules: the modem's, the Hub's, linking's, discovery's and the network's.
///
/// A description never carries the Hub's credentials. A front end shows it as it is, or adds
/// its own hint, such as where the Hub's user name and password are set:
///
/// ```swift
/// do {
///   try await ModemSession.withHub(host: host, port: HubLocation.defaultPort, user: user, password: password) { session in
///     print(try await session.info())
///   }
/// } catch {
///   print(InsteonErrorDescription.message(for: error) ?? error.localizedDescription)
/// }
/// ```
public enum InsteonErrorDescription {

  /// A one-line description of an error from the libraries, or `nil` for any other error,
  /// such as `CancellationError` or a front end's own.
  ///
  /// - Parameter error: The error.
  /// - Returns: The description, without credentials.
  public static func message(for error: any Error) -> String? {

    switch error {
    case let error as ModemError:
      return describe(error)
    case let error as ModemStoppedEchoing:
      return didntConfirmSending(to: error.device)
    case let error as ModemRecordsNotRestored:
      return describe(error)
    case let error as HubError:
      return describe(error)
    case let error as LinkingError:
      return describe(error)
    case let error as LinkMismatch:
      return explanation(of: error)
    case let error as InsteonConnectError:
      return describe(error)
    case let error as LocalNetworkError:
      return describe(error)
    case let error as HTTPClientError:
      return error.description
    case is HubStoppedAnswering:
      return hubStoppedAnsweringInline
    case let error as HubAddressRefused:
      return error.description
    case let error as DatabaseLinkRefusal:
      return error.description
    default:
      break
    }

    #if os(macOS) || os(Linux)
    if let error = error as? SerialPortError {

      return describe(error)

    }
    #endif

    return nil

  }

  /// Whether an error is the Hub rejecting its user name and password with HTTP 401, so a
  /// front end can say where they're set.
  ///
  /// - Parameter error: The error.
  /// - Returns: `true` for the Hub's 401.
  public static func isRejectedHubCredentials(_ error: any Error) -> Bool {

    if case .unexpectedStatus(401)? = error as? HubError {

      return true

    }

    return false

  }

  /// Why a link the modem reported isn't the one asked for, or `nil` if it is.
  ///
  /// - Parameters:
  ///   - link: The modem's report.
  ///   - direction: Whether a link was being made or removed.
  ///   - device: The device asked for, or `nil` for any device.
  /// - Returns: A message that says what happened and what to do, or `nil` if the link is the
  ///   one asked for.
  public static func linkMismatch(_ link: LinkMade, direction: LinkingDirection, device: InsteonAddress?) -> String? {

    LinkMismatch(link.allLinkingCompleted, direction: direction, device: device).map(explanation(of:))

  }

  /// The text for a Hub that answered earlier requests and then stopped, written to follow a
  /// colon in a longer message that gives the Hub's address and device elsewhere.
  public static let hubStoppedAnsweringInline: String = "the Hub stopped answering, most likely while a device that's out of range didn't answer; try again"

  /// For a modem that didn't echo a command, when nothing suggests it's busy, as when it's
  /// disconnected or off.
  ///
  /// - Parameter command: The command's name, such as "Get IM Info".
  /// - Returns: A message that says to check the modem's connection and power.
  public static func modemUnanswered(command: String) -> String {

    "The modem didn't answer \(command). Check that it's connected and powered."

  }

  /// For a modem that answered earlier commands and then didn't echo a message to a device, as
  /// when it's still sending an earlier message to a device that doesn't answer.
  ///
  /// - Parameter device: The device the message was addressed to.
  /// - Returns: A message that names the device and says to try again.
  public static func didntConfirmSending(to device: InsteonAddress) -> String {

    "The modem didn't confirm sending to \(device); it may still be busy with a device that isn't answering. Check that \(device) is powered and in range, then try again."

  }

  /// What to tell the person about a link the modem reported that isn't the one asked for.
  static func explanation(of mismatch: LinkMismatch) -> String {

    let link: AllLinkingCompleted = mismatch.link

    switch mismatch.reason {
    case let .otherDevice(device):
      let change: String = link.mode == .delete ? "removed its link" : "linked"

      return "The modem reported \(link.address), not \(device): another device's SET button was pressed, "
        + "and the modem \(change) with it in group \(link.group). Run the command again for \(device)."
    case .linkedInsteadOfUnlinking:
      return "\(link.address) linked again in group \(link.group) instead of unlinking: it was in linking mode, not unlinking mode. "
        + "Put it into unlinking mode (on most devices, hold its SET button until it beeps, then hold it again until it beeps again) "
        + "and run the command again."
    case .unlinkedInsteadOfLinking:
      return "\(link.address) removed its link in group \(link.group) instead of linking: it was in unlinking mode, not linking mode. "
        + "Run the command again, and hold its SET button only until it first beeps."
    }

  }

  private static func describe(_ error: ModemError) -> String {

    switch error {
    case let .rejected(number):
      "The modem rejected \(number.name) every time it was sent."
    case let .timedOut(number):
      modemUnanswered(command: number.name)
    case .connectionClosed:
      "The connection to the modem closed."
    case let .deviceRejected(device, reason):
      "Device \(device) rejected the command: \(reason.summary)."
    case let .deviceTimedOut(device):
      "Device \(device) didn't answer. Check its address, and that it's powered and in range."
    }

  }

  private static func describe(_ error: HubError) -> String {

    switch error {
    case .unexpectedStatus(401):
      "The Hub rejected its user name and password (HTTP 401)."
    case let .unexpectedStatus(status):
      "The Hub answered with HTTP status \(status)."
    case let .invalidEndpoint(endpoint):
      "'\(endpoint.host):\(endpoint.port)' isn't a valid address for a Hub."
    case .malformedBuffer:
      "The Hub's reply couldn't be read. Check that the address is a Hub 2245 or Hub 2242."
    case .malformedSlotPage:
      "The Hub's timer page couldn't be read."
    case let .reservedSlot(slot):
      "The Hub's slot \(slot) is reserved."
    }

  }

  private static func describe(_ error: ModemRecordsNotRestored) -> String {

    let records: String = error.records.map { (record: AllLinkRecord) -> String in "\(record.address), group \(record.group)" }.joined(separator: "; ")

    return "Removing a link also removed the modem's \(error.records.count == 1 ? "record" : "records") of \(records), which couldn't be added back. Link them again."

  }

  private static func describe(_ error: LinkingError) -> String {

    switch error {
    case .linkingTimedOut:
      "No device's SET button was pressed in time. The modem has left linking mode."
    case let .unexpectedLink(link):
      "The modem reported a different link: \(link.address), group \(link.group), \(link.mode?.name ?? "unknown")."
    case let .remoteLinkingUnsupported(device):
      "Device \(device) runs i1, so it can be linked only with its SET button."
    case let .databaseFull(device):
      "The ALL-Link database of \(device) is full."
    case let .recordNotWritten(device, address):
      "A record written to the ALL-Link database of \(device) at \(hexAddress(address)) didn't read back as written."
    }

  }

  private static func describe(_ error: InsteonConnectError) -> String {

    switch error {
    case let .unexpectedStatus(status):
      "Insteon Connect answered with HTTP status \(status)."
    case .unrecognizedPage:
      "Insteon Connect's page couldn't be read; its format may have changed."
    }

  }

  private static func describe(_ error: LocalNetworkError) -> String {

    switch error {
    case let .interfacesUnavailable(code):
      "The network interfaces couldn't be listed (error \(code))."
    }

  }

  #if os(macOS) || os(Linux)
  private static func describe(_ error: SerialPortError) -> String {

    switch error {
    case let .cannotOpen(path, code):
      "The serial port \(path) couldn't be opened: \(String(cString: strerror(code)))."
    case let .cannotConfigure(path, code):
      "The serial port \(path) couldn't be configured: \(String(cString: strerror(code)))."
    case let .writeFailed(code):
      "Writing to the serial port failed: \(String(cString: strerror(code)))."
    case let .readFailed(code):
      "Reading from the serial port failed: \(String(cString: strerror(code)))."
    case .closed:
      "The serial port is closed."
    }

  }
  #endif

  /// A two-byte address in an ALL-Link database as `0x` and four uppercase digits, such as
  /// `0x0FFF`.
  private static func hexAddress(_ value: UInt16) -> String {

    let digits: String = String(value, radix: 16, uppercase: true)

    return "0x" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits

  }

}

/// What went wrong with a command the modem was asked to send, read from the error a send
/// threw, so a front end can word it without the modem's own error type.
///
/// ```swift
/// do {
///   _ = try await lamp.beep()
/// } catch {
///   if case let .deviceRejected(_, reason)? = SendFailure(error) {
///     print("NAK: \(reason.summary)")
///   }
/// }
/// ```
public enum SendFailure: Hashable, Sendable {

  /// The modem rejected the command every time it was sent.
  case modemRejected

  /// The modem didn't answer the command.
  case modemUnanswered

  /// A device rejected a message, for a reason its NAK gives.
  case deviceRejected(InsteonAddress, NAKReason)

  /// A device didn't answer a message.
  case deviceUnanswered(InsteonAddress)

  /// Reads a failure from an error a send threw.
  ///
  /// - Parameter error: The error.
  /// - Returns: `nil` for an error that isn't one of these, such as the connection closing.
  public init?(_ error: any Error) {

    guard let error = error as? ModemError else {

      return nil

    }

    switch error {
    case .rejected:
      self = .modemRejected
    case .timedOut:
      self = .modemUnanswered
    case let .deviceRejected(device, reason):
      self = .deviceRejected(device, reason)
    case let .deviceTimedOut(device):
      self = .deviceUnanswered(device)
    case .connectionClosed:
      return nil
    }

  }

}

/// How a Hub stopped answering, read from the error a session with it threw.
public enum HubFailure: Hashable, Sendable {

  /// The Hub answered earlier requests and then stopped, most likely while its modem waited
  /// for a device that doesn't answer.
  case stoppedAnswering

  /// A request to the Hub got no answer, as when it timed out or the host couldn't be reached.
  case unanswered

  /// Reads a failure from an error a session with a Hub threw.
  ///
  /// - Parameter error: The error.
  /// - Returns: `nil` for any other error.
  public init?(_ error: any Error) {

    if error is HubStoppedAnswering {

      self = .stoppedAnswering

    } else if HubStoppedAnswering.isUnanswered(error) {

      self = .unanswered

    } else {

      return nil

    }

  }

}
