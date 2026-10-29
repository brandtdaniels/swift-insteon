import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonCLICore
import InsteonDeviceCatalog
import InsteonHubClient
import InsteonHubDiscovery
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// Finds products in the Insteon device catalog that ships with the package.
struct ProductNames: Sendable {

  /// The catalog, or `nil` if it couldn't be loaded, in which case no names are shown.
  let catalog: DeviceCatalog?

  /// Loads the catalog from beside the command, warning once on standard error if it isn't
  /// there.
  init() {

    catalog = CatalogLoader.load()

  }

  /// The product a device's identity names, such as "Dimmer Switch 2477D (SwitchLinc Dimmer)".
  func name(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String? {

    catalog?.profile(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion).map(ProductName.of)

  }

  /// What the catalog says about a device with a known identity.
  func device(_ identity: KnownIdentity) -> KnownDevice {

    KnownDevice(identity: identity, catalog: catalog)

  }

  /// A profile's name and model, then its first alias, as the docs name products.
  static func name(of profile: DeviceProfile) -> String {

    ProductName.of(profile)

  }

}

/// Loads the Insteon device catalog from the bundle beside the command, without
/// `DeviceCatalog.bundled()`, which stops the process when the bundle is missing, as it is when
/// only the executable was copied.
enum CatalogLoader {

  /// The catalog, or `nil` after a one-line warning if it isn't beside the command or can't
  /// be read.
  static func load() -> DeviceCatalog? {

    let paths = CatalogLocation.candidatePaths(nextTo: executableDirectories())

    guard let path = paths.first(where: { FileManager.default.isReadableFile(atPath: $0) }) else {

      Output.note(
        "insteon: warning: the Insteon device catalog (\(CatalogLocation.bundleNames[0])) isn't next to the command, "
          + "so products aren't named. Scripts/install-insteon.sh installs the command with it."
      )

      return nil

    }

    do {

      return try DeviceCatalog(json: Data(contentsOf: URL(fileURLWithPath: path)))

    } catch {

      Output.note("insteon: warning: the Insteon device catalog at \(path) couldn't be read, so products aren't named.")

      return nil

    }

  }

  /// The directories the Swift Package Manager's resource accessor looks in for a command:
  /// the main bundle's, which is the executable's directory, and the executable's directory
  /// with symbolic links resolved, for a command linked into a directory on `PATH`.
  private static func executableDirectories() -> [String] {

    var directories = [Bundle.main.bundlePath]

    if let executable = Bundle.main.executablePath {

      directories.append(Paths.directory(of: executable))

      if let resolved = Paths.resolved(executable) {

        directories.append(Paths.directory(of: resolved))

      }

    }

    return directories

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

  /// An engine as the docs name it: i1, i2 or i2CS.
  static func engine(_ engine: InsteonEngine?) -> String {

    switch engine {
    case .i1: "i1"
    case .i2: "i2"
    case .i2cs: "i2CS"
    case nil: "unknown"
    }

  }

  /// The modem's role in a link it reported.
  static func mode(_ mode: AllLinkMode?) -> String {

    switch mode {
    case .controller: "controller"
    case .responder: "responder"
    case .controllerOrResponder: "controller or responder"
    case .delete: "deleted"
    case nil: "unknown"
    }

  }

  /// The common commands in cmd1, as the Insteon Developer's Guide names them.
  static func command1(_ command1: UInt8) -> String? {

    switch command1 {
    case 0x03: "Product Data Request"
    case 0x0D: "Get Insteon Engine Version"
    case 0x0F: "Ping"
    case 0x10: "ID Request"
    case 0x11: "Light On"
    case 0x12: "Light On Fast"
    case 0x13: "Light Off"
    case 0x14: "Light Off Fast"
    case 0x15: "Light Brighten One Step"
    case 0x16: "Light Dim One Step"
    case 0x17: "Light Start Manual Change"
    case 0x18: "Light Stop Manual Change"
    case 0x19: "Light Status Request"
    default: nil
    }

  }

  /// A message's type, in words.
  static func messageType(_ type: MessageFlags.MessageType) -> String {

    switch type {
    case .direct: "direct"
    case .directAcknowledgment: "ACK"
    case .directNegativeAcknowledgment: "NAK"
    case .broadcast: "broadcast"
    case .allLinkBroadcast: "ALL-Link broadcast"
    case .allLinkCleanup: "ALL-Link cleanup"
    case .allLinkCleanupAcknowledgment: "ALL-Link cleanup ACK"
    case .allLinkCleanupNegativeAcknowledgment: "ALL-Link cleanup NAK"
    }

  }

  /// Why a device rejected a message, in words.
  static func nakReason(_ reason: NAKReason) -> String {

    switch reason {
    case .notLinked: "it isn't linked to the modem"
    case .noLoad: "it has no load connected"
    case .invalidCommand: "it doesn't support the command"
    case .databaseSearchPending: "it's still searching its ALL-Link database"
    case .illegalValue: "a value is out of range"
    case .groupZeroCommand: "the command isn't allowed for group 0"
    case .databaseFull: "its ALL-Link database is full"
    case .noHardware: "it lacks the hardware for the command"
    default: "NAK reason \(Hex.byte(reason.rawValue))"
    }

  }

  /// The kind of a reply the modem sent, as `insteon watch --raw` names a reply that isn't a
  /// message from a device.
  static func replyKind(_ reply: ModemReply) -> String {

    switch reply {
    case .messageReceived: "Insteon message"
    case .x10Received: "X10 received"
    case .allLinkingCompleted: "ALL-Linking Completed"
    case .buttonEvent: "button event"
    case .userReset: "user reset"
    case .allLinkCleanupFailed: "ALL-Link cleanup failure"
    case .allLinkRecord: "ALL-Link record"
    case .allLinkCleanupStatus: "ALL-Link cleanup status"
    case .databaseRecord: "database record"
    case .diagnosticRecord: "diagnostic record"
    case .deviceRecordFound: "device record"
    case .radioStatus: "radio status"
    case .modemInfo: "Get IM Info reply"
    case .modemConfiguration: "configuration"
    case let .echo(echo): "echo of \(serialCommand(echo.number))\(echo.isAccepted ? "" : ", NAK")"
    case .negativeAcknowledgment: "NAK"
    }

  }

  /// A serial command, as the Insteon Modem Developer's Guide names it.
  static func serialCommand(_ number: SerialCommandNumber) -> String {

    switch number {
    case .getModemInfo: "Get IM Info"
    case .sendMessage: "Send Insteon Standard or Extended Message"
    case .startAllLinking: "Start ALL-Linking"
    case .cancelAllLinking: "Cancel ALL-Linking"
    case .getFirstAllLinkRecord: "Get First ALL-Link Record"
    case .getNextAllLinkRecord: "Get Next ALL-Link Record"
    default: "serial command \(Hex.byte(number.rawValue))"
    }

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
    case let error as InsteonConnectError:
      return describe(error)
    case let error as LocalNetworkError:
      return describe(error)
    case let error as CommandFailure:
      return error.description
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

  private static func describe(_ error: ModemError) -> String {

    switch error {
    case let .rejected(number):
      "The modem rejected \(serialCommand(number)) every time it was sent."
    case let .timedOut(number):
      "The modem didn't answer \(serialCommand(number)). Check that it's connected and powered."
    case .connectionClosed:
      "The connection to the modem closed."
    case let .deviceRejected(device, reason):
      "Device \(device) rejected the command: \(nakReason(reason))."
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
