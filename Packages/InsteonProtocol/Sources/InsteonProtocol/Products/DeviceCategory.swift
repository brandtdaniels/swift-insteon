/// A device's Insteon Device Category (DevCat), such as `0x01` for dimmable lighting control.
///
/// The category groups devices that share a family of commands: what a direct command means
/// depends on the category of the device that receives it. Together with the device
/// subcategory (SubCat), it identifies a kind of device.
///
/// The Insteon Developer's Guide defines categories `0x00` through `0x16`, each available as a
/// constant with its ``DeviceCategory/name``, and reserves `0x17` through `0xFE`. Names for
/// subcategories, which identify products, come from the Insteon device catalog rather than from this
/// package.
///
/// ```swift
/// let dimmable: DeviceCategory = 0x01
/// print(dimmable)                                      // "0x01"
/// print(dimmable == .dimmableLightingControl)          // "true"
/// print(dimmable.name ?? "Reserved")                   // "Dimmable Lighting Control"
/// ```
public struct DeviceCategory: RawRepresentable, Hashable, Sendable {

  /// The category number.
  public var rawValue: UInt8

  /// Creates a category from its number.
  ///
  /// - Parameter rawValue: The category number.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// Generalized Controllers (`0x00`): devices such as ControLinc, RemoteLinc and SignaLinc.
  public static let generalizedControllers = DeviceCategory(rawValue: 0x00)

  /// Dimmable Lighting Control (`0x01`): devices such as dimmable switches and plug-in modules.
  public static let dimmableLightingControl = DeviceCategory(rawValue: 0x01)

  /// Switched Lighting Control (`0x02`): devices such as relay switches and plug-in modules.
  public static let switchedLightingControl = DeviceCategory(rawValue: 0x02)

  /// Network Bridges (`0x03`): devices such as PowerLinc Modems and Controllers, and Hubs.
  public static let networkBridges = DeviceCategory(rawValue: 0x03)

  /// Irrigation Control (`0x04`): devices such as sprinkler controllers.
  public static let irrigationControl = DeviceCategory(rawValue: 0x04)

  /// Climate Control (`0x05`): devices such as heating, air conditioning and fans.
  public static let climateControl = DeviceCategory(rawValue: 0x05)

  /// Pool and Spa Control (`0x06`): devices such as pumps, heaters and chemical controls.
  public static let poolAndSpaControl = DeviceCategory(rawValue: 0x06)

  /// Sensors and Actuators (`0x07`): devices such as sensors and contact closures.
  public static let sensorsAndActuators = DeviceCategory(rawValue: 0x07)

  /// Home Entertainment (`0x08`): devices such as audio and video equipment.
  public static let homeEntertainment = DeviceCategory(rawValue: 0x08)

  /// Energy Management (`0x09`): devices such as electricity, water and gas monitors.
  public static let energyManagement = DeviceCategory(rawValue: 0x09)

  /// Built-In Appliance Control (`0x0A`): devices such as major appliances.
  public static let builtInApplianceControl = DeviceCategory(rawValue: 0x0A)

  /// Plumbing (`0x0B`): devices such as faucets, showers and toilets.
  public static let plumbing = DeviceCategory(rawValue: 0x0B)

  /// Communication (`0x0C`): devices such as telephone controls and intercoms.
  public static let communication = DeviceCategory(rawValue: 0x0C)

  /// Computer Control (`0x0D`): devices such as PC power, UPS and input device control.
  public static let computerControl = DeviceCategory(rawValue: 0x0D)

  /// Window Coverings (`0x0E`): devices such as drapes, blinds and awnings.
  public static let windowCoverings = DeviceCategory(rawValue: 0x0E)

  /// Access Control (`0x0F`): devices such as automatic doors, gates, windows and locks.
  public static let accessControl = DeviceCategory(rawValue: 0x0F)

  /// Security, Health, Safety (`0x10`): devices such as door, window and motion sensors.
  public static let securityHealthSafety = DeviceCategory(rawValue: 0x10)

  /// Surveillance (`0x11`): devices such as video camera control.
  public static let surveillance = DeviceCategory(rawValue: 0x11)

  /// Automotive (`0x12`): devices such as remote starters and car alarms.
  public static let automotive = DeviceCategory(rawValue: 0x12)

  /// Pet Care (`0x13`): devices such as pet feeders and trackers.
  public static let petCare = DeviceCategory(rawValue: 0x13)

  /// Toys (`0x14`): devices such as model trains and robots.
  public static let toys = DeviceCategory(rawValue: 0x14)

  /// Timekeeping (`0x15`): devices such as clocks, alarms and timers.
  public static let timekeeping = DeviceCategory(rawValue: 0x15)

  /// Holiday (`0x16`): devices such as holiday lights and displays.
  public static let holiday = DeviceCategory(rawValue: 0x16)

  /// Unassigned (`0xFF`): devices whose category and subcategory are assigned by software.
  public static let unassigned = DeviceCategory(rawValue: 0xFF)

  /// The category's name in the Insteon Developer's Guide, or `nil` for a reserved category.
  public var name: String? {

    switch rawValue {
    case 0x00: "Generalized Controllers"
    case 0x01: "Dimmable Lighting Control"
    case 0x02: "Switched Lighting Control"
    case 0x03: "Network Bridges"
    case 0x04: "Irrigation Control"
    case 0x05: "Climate Control"
    case 0x06: "Pool and Spa Control"
    case 0x07: "Sensors and Actuators"
    case 0x08: "Home Entertainment"
    case 0x09: "Energy Management"
    case 0x0A: "Built-In Appliance Control"
    case 0x0B: "Plumbing"
    case 0x0C: "Communication"
    case 0x0D: "Computer Control"
    case 0x0E: "Window Coverings"
    case 0x0F: "Access Control"
    case 0x10: "Security, Health, Safety"
    case 0x11: "Surveillance"
    case 0x12: "Automotive"
    case 0x13: "Pet Care"
    case 0x14: "Toys"
    case 0x15: "Timekeeping"
    case 0x16: "Holiday"
    case 0xFF: "Unassigned"
    default: nil
    }

  }

}

extension DeviceCategory: ExpressibleByIntegerLiteral {

  /// Creates a category from an integer literal, such as `0x01`.
  ///
  /// - Parameter value: The category number.
  public init(integerLiteral value: UInt8) {

    self.init(rawValue: value)

  }

}

extension DeviceCategory: CustomStringConvertible {

  /// The category number in hexadecimal, such as `"0x01"`.
  public var description: String {

    "0x" + rawValue.hexDigits

  }

}
