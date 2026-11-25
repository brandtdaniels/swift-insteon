import Foundation
import InsteonCore
import InsteonHubPro

/// What `insteon` says when the unit it's pointed at is a Hub Pro.
///
/// A Hub Pro's devices are read and controlled over its local HTTP interface, one command at a
/// time. Everything that works on a modem's ALL-Link database, its groups or its settings has no
/// counterpart there, so each of those commands is refused, with a sentence that says so, before
/// anything is sent.
public enum HubProText {

  /// Whether a command runs on a Hub Pro.
  ///
  /// - Parameter subcommand: The command.
  /// - Returns: `true` for the reads and controls a Hub Pro offers, and for the commands that
  ///   need no modem.
  public static func runsOnAHubPro(_ subcommand: Subcommand) -> Bool {

    switch subcommand {
    case .help, .discover, .hubs, .info, .observe, .backup, .backupCheck, .transferPlan, .catalog, .catalogUpdate:
      true
    case let .device(_, action):
      switch action {
      case .id, .ping, .on, .onFast, .off, .offFast, .beep, .status:
        true
      case .instant, .settings, .set, .send, .links, .selfTest:
        false
      }
    case .links, .link, .cancelLinking, .unlink, .remove, .watch, .beep, .scene, .modemSend:
      false
    }

  }

  /// The sentence that says a Hub Pro can't do a command.
  ///
  /// Adding and removing devices points to the SET buttons, as the Hub Pro's manual describes.
  ///
  /// - Parameters:
  ///   - subcommand: The command.
  ///   - host: The Hub Pro's host.
  /// - Returns: The sentence, then what a Hub Pro can be asked.
  public static func cannot(_ subcommand: Subcommand, host: String) -> String {

    var message = "A Hub Pro can't \(phrase(for: subcommand))."

    if changesDevices(subcommand) {

      message += " Add and remove devices with the SET buttons, as the Hub Pro's manual describes."

    }

    return message + " " + offered(host: host)

  }

  /// What a Hub Pro can be asked.
  ///
  /// - Parameter host: The Hub Pro's host.
  public static func offered(host: String) -> String {

    "'insteon' reads and controls the devices a Hub Pro already has: device ADDRESS status, on, off (each with --fast), ping, beep and id, "
      + "and info and observe. Use --hub \(host) with them. No user name or password is needed or sent."

  }

  private static func changesDevices(_ subcommand: Subcommand) -> Bool {

    switch subcommand {
    case .link, .unlink, .remove, .cancelLinking:
      true
    default:
      false
    }

  }

  private static func phrase(for subcommand: Subcommand) -> String {

    switch subcommand {
    case .links: "read an ALL-Link database"
    case .link: "link a device"
    case .cancelLinking: "cancel linking"
    case .unlink: "unlink a device"
    case .remove: "remove a device"
    case .watch: "watch what its modem hears"
    case .beep: "beep its modem"
    case .scene: "send a scene command"
    case .modemSend: "send a message as given"
    case let .device(_, action):
      switch action {
      case .instant: "change a device to a level at once"
      case .settings, .set: "read or change a device's settings"
      case .send: "send a device a message as given"
      case .links: "read a device's ALL-Link database"
      case .selfTest: "run a self-test of a device"
      case .id, .ping, .on, .onFast, .off, .offFast, .beep, .status: "do that"
      }
    case .help, .discover, .hubs, .info, .observe, .backup, .backupCheck, .transferPlan, .catalog, .catalogUpdate: "do that"
    }

  }

  // MARK: - Failures

  /// What to say when a Hub Pro didn't answer, or answered with something unusable.
  ///
  /// - Parameters:
  ///   - error: What the request threw.
  ///   - host: The Hub Pro's host.
  /// - Returns: The sentence, or `nil` for an error that isn't about the Hub Pro's answer, such
  ///   as a canceled task.
  public static func failure(_ error: any Error, host: String) -> String? {

    if HubFailure(error) == .unanswered {

      return "The Hub Pro at \(host) didn't answer. Check that it has power and is on this network."

    }

    switch error {
    case let HubProError.unexpectedStatus(status):
      return "The Hub Pro at \(host) answered with HTTP status \(status)."
    case HubProError.malformedResponse:
      return "The Hub Pro at \(host) sent an answer 'insteon' can't read."
    default:
      return nil
    }

  }

  /// What to say when a Hub Pro didn't confirm a command it was sent.
  ///
  /// - Parameter device: The device the command was for.
  public static func unconfirmed(_ device: InsteonAddress) -> String {

    "The Hub Pro didn't confirm that \(device) took the command, which may have reached it. Read its status before sending the command again."

  }

  // MARK: - info

  /// The rows of the table `insteon info` prints for a Hub Pro's devices.
  ///
  /// - Parameter devices: The devices it lists, apart from its own modem, each with the product
  ///   the catalog names for it, if it names one.
  /// - Returns: The rows of a table whose first row is its heading.
  public static func devices(_ devices: [(device: HubProListedDevice, product: String?)]) -> [[String]] {

    let rows = devices.map { entry -> [String] in

      [entry.device.address.description, entry.device.name, entry.device.deviceType, entry.product ?? ""]

    }

    return [["ADDRESS", "NAME", "TYPE", "PRODUCT"]] + rows

  }

  /// The line that tells the Hub Pro's software versions.
  ///
  /// - Parameter versions: The versions the Hub Pro reported.
  public static func versionLine(_ versions: HubProVersions) -> String {

    "Hub Pro: configuration \(versions.config.version), server \(versions.server.version)."

  }

  // MARK: - id

  /// The rows `insteon device ADDRESS id` prints for a device a Hub Pro lists.
  ///
  /// - Parameters:
  ///   - description: What the Hub Pro reports about the device.
  ///   - product: The product the catalog names for it, if it names one.
  /// - Returns: The rows of a table of two columns.
  public static func identityRows(_ description: HubProDescription, product: String?) -> [[String]] {

    var rows: [[String]] = [["Address", description.address.description], ["Name", description.name], ["Type", description.deviceType]]

    if let product {

      rows.append(["Product", product])

    }

    rows.append(["Category", description.category.map(Hex.byte) ?? "not reported"])
    rows.append(["Subcategory", description.subcategory.map(Hex.byte) ?? "not reported"])
    rows.append(["Firmware", description.firmwareVersion.map(Hex.byte) ?? "not reported"])
    rows.append(["SKU", description.sku ?? "not reported"])
    rows.append(["Engine", "not reported"])
    rows.append(["Commands", description.commandNames.joined(separator: ", ")])

    return rows

  }

}
