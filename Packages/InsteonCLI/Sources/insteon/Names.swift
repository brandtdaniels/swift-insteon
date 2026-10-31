import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonCLICore
import InsteonCore
import InsteonDeviceCatalog
import InsteonHubClient
import InsteonHubDiscovery
import InsteonLinking
import InsteonModem
import InsteonNetworking
import InsteonProtocol

/// Finds products in the Insteon device catalog: the copy that ships with the package, or a
/// newer one `insteon catalog update` downloaded.
struct ProductNames: Sendable {

  /// The catalog, or `nil` if it couldn't be loaded, in which case no names are shown.
  let catalog: DeviceCatalog?

  /// Loads the catalog: the copy `insteon catalog update` downloaded, when it's in the format
  /// the command reads and at least as new as the bundled copy, or else the bundled copy. A
  /// copy that can't be read gets a one-line warning on standard error.
  init() {

    catalog = Self.loadCatalog()

  }

  /// The catalog `CatalogStore.load()` chooses, or `nil` after a one-line warning if neither
  /// copy can be read, as when only the executable was copied.
  private static func loadCatalog() -> DeviceCatalog? {

    CatalogStore.load()?.catalog

  }

  /// The product a device's identity names, such as "Dimmer Switch 2477D (SwitchLinc Dimmer)".
  func name(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String? {

    catalog?.profile(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)?.displayName

  }

}

/// A command that couldn't do what was asked, with a message that says why and what to do.
struct CommandFailure: Error, CustomStringConvertible {

  /// The message for the person who typed the command.
  let description: String

}

/// Names for the values the command prints.
enum Names {

  /// A category with its name, such as "0x01 (Dimmable Lighting Control)".
  static func category(_ category: DeviceCategory) -> String {

    category.name.map { "\(category) (\($0))" } ?? "\(category)"

  }

  /// An engine as Insteon's documents name it, or "unknown".
  static func engine(_ engine: InsteonEngine?) -> String {

    engine?.name ?? "unknown"

  }

  /// The modem's role in a link it reported, or "unknown".
  static func mode(_ mode: AllLinkMode?) -> String {

    mode?.name ?? "unknown"

  }

  /// The kind of a reply the modem sent, as `insteon modem send` names a reply that isn't a
  /// message from a device.
  static func replyKind(_ reply: ModemReply) -> String {

    DeviceMonitor.replyKind(reply)

  }

  /// An error as a one-line message, without credentials.
  static func message(for error: any Error) -> String {

    switch error {
    case let error as ArgumentError:
      return error.description
    case let error as ConfigurationError:
      return error.description
    case let error as DotEnvError:
      return error.description
    case let error as EnvironmentFileError:
      return error.description
    case is CancellationError:
      return "Interrupted."
    case let error as ModemError:
      return describe(error)
    case let error as HubError:
      return describe(error)
    case let error as LinkingError:
      return describe(error)
    case let error as LinkMismatch:
      return LinkOutcome.explanation(of: error)
    case let error as InsteonConnectError:
      return describe(error)
    case let error as LocalNetworkError:
      return describe(error)
    case let error as CommandFailure:
      return error.description
    case let error as HTTPClientError:
      return error.description
    case is HubStoppedAnswering:
      return HubText.stoppedAnsweringInline
    default:
      break
    }

    #if os(macOS) || os(Linux)
    if let error = error as? SerialPortError {

      return describe(error)

    }
    #endif

    return error.localizedDescription

  }

  /// What to say when a request to the Hub got no answer, such as when it timed out or the
  /// host couldn't be reached, or `nil` for any other error.
  ///
  /// - Parameters:
  ///   - error: The error a request to the Hub threw.
  ///   - endpoint: The Hub's host and port. Its credentials aren't part of it.
  /// - Returns: A message that names the Hub's address and how to find it again.
  static func hubUnanswered(_ error: any Error, endpoint: HubEndpoint) -> String? {

    guard HubStoppedAnswering.isUnanswered(error) else {

      return nil

    }

    return HubText.unanswered(host: endpoint.host, port: endpoint.port)

  }

  private static func describe(_ error: ModemError) -> String {

    switch error {
    case let .rejected(number):
      "The modem rejected \(number.name) every time it was sent."
    case let .timedOut(number):
      "The modem didn't answer \(number.name). Check that it's connected and powered."
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
      "The Hub rejected its user name and password (HTTP 401). Check INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD."
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

  private static func describe(_ error: LinkingError) -> String {

    switch error {
    case .linkingTimedOut:
      "No device's SET button was pressed in time. The modem has left linking mode."
    case let .unexpectedLink(link):
      "The modem reported a different link: \(link.address), group \(link.group), \(mode(link.mode))."
    case let .remoteLinkingUnsupported(device):
      "Device \(device) runs i1, so it can be linked only with its SET button."
    case let .databaseFull(device):
      "The ALL-Link database of \(device) is full."
    case let .recordNotWritten(device, address):
      "A record written to the ALL-Link database of \(device) at \(Hex.address(address)) didn't read back as written."
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

}
