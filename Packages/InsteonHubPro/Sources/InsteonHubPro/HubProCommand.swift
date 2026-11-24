/// A command the Hub Pro runs on one of its devices, from the short list ``HubProTransport``
/// sends.
///
/// A command is built only from a key on the list, so a key that changes a device's links, such
/// as one that writes or clears a link, can't be sent: no value of this type names one.
///
/// ```swift
/// let command = HubProCommand.on(level: 128)
/// command.key     // "On"
/// ```
public struct HubProCommand: Hashable, Sendable {

  /// The key the Hub Pro runs the command by.
  public let key: String

  /// The level sent with the command, from 0 through 255, or `nil` when it sends none.
  public let level: UInt8?

  private init(_ key: String, level: UInt8? = nil) {

    self.key = key
    self.level = level

  }

  /// Reads the device's level.
  public static let statusRequest = HubProCommand("StatusRequest")

  /// Asks the device whether it answers.
  public static let ping = HubProCommand("Ping")

  /// Asks the device for its identity.
  public static let idRequest = HubProCommand("IDRequest")

  /// Turns the device off.
  public static let off = HubProCommand("Off")

  /// Turns the device off without ramping.
  public static let fastOff = HubProCommand("FastOff")

  /// Makes the device beep.
  public static let beep = HubProCommand("Beep")

  /// Turns the device on.
  ///
  /// - Parameter level: The level on the Hub Pro's scale, from 0 for off to 255 for fully on, or
  ///   `nil` to send none.
  public static func on(level: UInt8?) -> HubProCommand {

    HubProCommand("On", level: level)

  }

  /// Turns the device on without ramping.
  ///
  /// - Parameter level: The level on the Hub Pro's scale, or `nil` to send none.
  public static func fastOn(level: UInt8?) -> HubProCommand {

    HubProCommand("FastOn", level: level)

  }

  /// The name of the parameter that carries a level.
  public static let levelParameter = "OnLevel"

  /// The keys the transport sends, in the order the commands are declared.
  public static let allowedKeys: [String] = ["StatusRequest", "Ping", "IDRequest", "On", "Off", "FastOn", "FastOff", "Beep"]

  /// The keys that change a device's links or the Hub Pro's own device table. They are never
  /// sent.
  public static let refusedKeys: [String] = ["WriteLink", "ClearLink", "LinkPlm", "EnterLinkMode", "RemoveDeviceComplete", "SetX10Info"]

  /// Creates the command a key names, as the Hub Pro lists it for a device.
  ///
  /// On and FastOn take fully on, 255, as their level.
  ///
  /// - Parameter key: The key.
  /// - Returns: The command, or `nil` for any key but the ones in ``allowedKeys``.
  public init?(key: String) {

    switch key {
    case "StatusRequest": self = .statusRequest
    case "Ping": self = .ping
    case "IDRequest": self = .idRequest
    case "On": self = .on(level: 255)
    case "Off": self = .off
    case "FastOn": self = .fastOn(level: 255)
    case "FastOff": self = .fastOff
    case "Beep": self = .beep
    default: return nil
    }

  }

}
