/// What a ``Device`` can do, as the Insteon device catalog describes it, for a front end to
/// decide what to show.
///
/// ```swift
/// let capabilities = try await network.device(lamp).capabilities()
///
/// if capabilities.canDim {
///   showSlider()
/// }
///
/// for setting in capabilities.settings where !setting.isAdvanced {
///   show(setting.label, setting.control)
/// }
/// ```
public struct DeviceCapabilities: Hashable, Sendable {

  /// Where a device's capabilities come from.
  public enum Source: Hashable, Sendable {

    /// The catalog's profile and command set for the device.
    case catalog

    /// The device's category, because the catalog gives no group types for the device: a
    /// device that reported dimmable lighting control, `0x01`, is controlled as a dimmer, and
    /// one that reported switched lighting control, `0x02`, as a relay.
    case categoryFallback

    /// Nothing says how to control the device, because its identity isn't known or neither
    /// the catalog nor its category says. It can still be pinged, and its status read as the
    /// raw byte Light Status Request reports.
    case uncontrolled

  }

  /// The product's name and model, as the catalog gives them, or `nil` if the catalog doesn't
  /// have the device.
  public var productName: String?

  /// Whether the device's identity is known.
  public var isIdentified: Bool

  /// Where the capabilities come from.
  public var source: Source

  /// The groups that can be controlled or read, in the profile's order.
  public var groups: [DeviceGroup]

  /// The number of the group an operation controls when it isn't given one, or `nil` if
  /// there are no groups.
  public var mainGroupNumber: Int?

  /// Whether the device's command set lists Beep. ``Device/beep()`` sends Beep either way.
  public var canBeep: Bool

  /// The settings the catalog describes, in the order a settings page shows them. Empty when
  /// the catalog doesn't describe the device's settings.
  public var settings: [DeviceSetting]

  /// Creates capabilities.
  ///
  /// - Parameters:
  ///   - productName: The product's name and model.
  ///   - isIdentified: Whether the device's identity is known.
  ///   - source: Where the capabilities come from.
  ///   - groups: The groups that can be controlled or read.
  ///   - mainGroupNumber: The group an operation controls when it isn't given one.
  ///   - canBeep: Whether the command set lists Beep.
  ///   - settings: The settings the catalog describes.
  public init(
    productName: String?,
    isIdentified: Bool,
    source: Source,
    groups: [DeviceGroup],
    mainGroupNumber: Int?,
    canBeep: Bool,
    settings: [DeviceSetting]
  ) {

    self.productName = productName
    self.isIdentified = isIdentified
    self.source = source
    self.groups = groups
    self.mainGroupNumber = mainGroupNumber
    self.canBeep = canBeep
    self.settings = settings

  }

  /// The group an operation controls when it isn't given one, if any.
  public var mainGroup: DeviceGroup? {

    groups.first { (group: DeviceGroup) -> Bool in group.number == mainGroupNumber }

  }

  /// Whether the main group takes a level when it's turned on.
  public var canDim: Bool {

    mainGroup?.canDim ?? false

  }

  /// Whether the main group can be turned on and off.
  public var canTurnOnAndOff: Bool {

    mainGroup?.canTurnOnAndOff ?? false

  }

}

/// One of a device's groups that can be controlled or read: a load, an outlet, a button.
public struct DeviceGroup: Hashable, Sendable {

  /// The group number, from 0 through 255.
  public var number: Int

  /// The group's name, such as `"Load"` or `"Top outlet"`.
  public var name: String

  /// What a control calls a group of its type, such as `"Light"`.
  public var typeLabel: String

  /// What the group is.
  public var kind: DeviceGroupKind

  /// Whether the group takes a level when it's turned on.
  public var canDim: Bool

  /// Whether the group can be turned on and off: its type has both actions, and each sends a
  /// message that reaches the group apart from the device's other groups.
  public var canTurnOnAndOff: Bool

  /// Whether the group's state can be read as its type says, with a command whose reply is
  /// about the group.
  public var hasStatus: Bool

  /// The names a control gives what the group can be told to do, such as `"On"` and `"Off"`,
  /// or a fan's speeds.
  public var actionLabels: [String]

  /// Creates a group.
  ///
  /// - Parameters:
  ///   - number: The group number.
  ///   - name: The group's name.
  ///   - typeLabel: What a control calls a group of its type.
  ///   - kind: What the group is.
  ///   - canDim: Whether the group takes a level when it's turned on.
  ///   - canTurnOnAndOff: Whether the group can be turned on and off.
  ///   - hasStatus: Whether the group's state can be read.
  ///   - actionLabels: The names of what the group can be told to do.
  public init(
    number: Int,
    name: String,
    typeLabel: String,
    kind: DeviceGroupKind,
    canDim: Bool,
    canTurnOnAndOff: Bool,
    hasStatus: Bool,
    actionLabels: [String]
  ) {

    self.number = number
    self.name = name
    self.typeLabel = typeLabel
    self.kind = kind
    self.canDim = canDim
    self.canTurnOnAndOff = canTurnOnAndOff
    self.hasStatus = hasStatus
    self.actionLabels = actionLabels

  }

}

/// What a ``DeviceGroup`` is, as the Insteon device catalog names it.
public struct DeviceGroupKind: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

  /// The kind as the catalog writes it, such as `"dimmer"`.
  public let rawValue: String

  /// Creates a kind from the catalog's name for it.
  ///
  /// - Parameter rawValue: The kind as the catalog writes it.
  public init(rawValue: String) {

    self.rawValue = rawValue

  }

  /// A load that dims.
  public static let dimmer = DeviceGroupKind(rawValue: "dimmer")

  /// A relay or outlet, switched on and off.
  public static let relay = DeviceGroupKind(rawValue: "relay")

  /// A fan with speeds.
  public static let fan = DeviceGroupKind(rawValue: "fan")

  /// A sensor or input that only reports.
  public static let sensor = DeviceGroupKind(rawValue: "sensor")

  /// A button that controls other devices.
  public static let button = DeviceGroupKind(rawValue: "button")

  /// A window covering or other motorized cover that opens and closes.
  public static let windowCovering = DeviceGroupKind(rawValue: "windowCovering")

  /// An alarm that sounds when a linked device triggers it while the device is armed.
  public static let alarm = DeviceGroupKind(rawValue: "alarm")

  /// A group that arms the device.
  public static let arming = DeviceGroupKind(rawValue: "arming")

  /// The kind as the catalog writes it.
  public var description: String { rawValue }

}

/// One of a device's settings the Insteon device catalog describes, with the control a
/// settings page shows for it.
public struct DeviceSetting: Hashable, Sendable {

  /// The setting's key in the catalog, such as `"rampRate"`, which
  /// ``Device/writeSetting(_:to:button:)`` takes.
  public var key: String

  /// What a settings page calls the setting, such as `"Ramp rate"`.
  public var label: String

  /// The heading to show the setting under, such as `"Load"`, or `nil` if the catalog gives
  /// none.
  public var section: String?

  /// What the setting is.
  public var summary: String

  /// Whether a settings page keeps the setting out of sight unless asked.
  public var isAdvanced: Bool

  /// Whether the catalog gives a way to change the setting.
  public var isWritable: Bool

  /// Whether the setting has a value for each button or group, rather than one for the whole
  /// device.
  public var isPerButton: Bool

  /// The control a settings page shows for the setting.
  public var control: DeviceSettingControl

  /// Creates a setting.
  ///
  /// - Parameters:
  ///   - key: The setting's key in the catalog.
  ///   - label: What a settings page calls the setting.
  ///   - section: The heading to show the setting under.
  ///   - summary: What the setting is.
  ///   - isAdvanced: Whether a settings page keeps the setting out of sight unless asked.
  ///   - isWritable: Whether the setting can be changed.
  ///   - isPerButton: Whether the setting has a value for each button or group.
  ///   - control: The control a settings page shows for the setting.
  public init(
    key: String,
    label: String,
    section: String?,
    summary: String,
    isAdvanced: Bool,
    isWritable: Bool,
    isPerButton: Bool,
    control: DeviceSettingControl
  ) {

    self.key = key
    self.label = label
    self.section = section
    self.summary = summary
    self.isAdvanced = isAdvanced
    self.isWritable = isWritable
    self.isPerButton = isPerButton
    self.control = control

  }

}

/// The control a settings page shows for a ``DeviceSetting``.
public enum DeviceSettingControl: Hashable, Sendable {

  /// A switch, for a flag that's on or off.
  case toggle

  /// A choice of named values, such as ramp rates, in the catalog's order.
  case choice([String])

  /// A choice of buttons, any number of them.
  case buttons

  /// A number in a unit, such as `"%"` or `" s"`, between the bounds the catalog gives, if any.
  case number(range: ClosedRange<Double>?, unit: String?)

  /// A byte, shown in hexadecimal, between the bounds the catalog gives, if any.
  case byte(range: ClosedRange<UInt8>?)

  /// A number the device reports, such as a count, which can't be changed.
  case reading

}
