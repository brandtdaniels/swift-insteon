/// What a device reported about one of its groups, read as the group's type in the Insteon
/// device catalog says.
///
/// ```swift
/// let status = try await network.device(lamp).status()
///
/// switch status.reading {
/// case let .percent(percent):
///   print("on at \(percent)%")
/// case let .onOff(isOn):
///   print(isOn ? "on" : "off")
/// case let .named(label):
///   print(label)
/// case .raw:
///   print("reports \(status.value)")
/// }
/// ```
public struct DeviceStatus: Hashable, Sendable {

  /// A status as the group's type reads it.
  public enum Reading: Hashable, Sendable {

    /// A level, from 0 through 100 percent, for a group that dims and whose state the catalog
    /// gives in percent.
    case percent(Int)

    /// On or off, for a group that only turns on and off, or one whose state is a bit of the
    /// reply.
    case onOff(Bool)

    /// The name the catalog gives the range the value is in, such as `"On"` or a fan's
    /// `"Low"`.
    case named(String)

    /// Just the byte, ``DeviceStatus/value``, because nothing says how to read it.
    case raw

  }

  /// The group the status is for, or `nil` for a device whose status was read with Light
  /// Status Request because nothing says how to read it.
  public var group: Int?

  /// The byte the acknowledgment carried in cmd2, from `0x00` through `0xFF`.
  public var value: UInt8

  /// The device's ALL-Link database delta, which the acknowledgment carried in cmd1.
  public var allLinkDatabaseDelta: UInt8

  /// The status as the group's type reads it.
  public var reading: Reading

  /// Whether the group is on: for ``DeviceStatus/Reading/onOff(_:)`` its value, and otherwise
  /// whether the group's byte isn't `0x00`.
  public var isOn: Bool

  /// Creates a status.
  ///
  /// - Parameters:
  ///   - group: The group the status is for.
  ///   - value: The byte the acknowledgment carried in cmd2.
  ///   - allLinkDatabaseDelta: The ALL-Link database delta from cmd1.
  ///   - reading: The status as the group's type reads it.
  ///   - isOn: Whether the group is on.
  public init(group: Int?, value: UInt8, allLinkDatabaseDelta: UInt8, reading: Reading, isOn: Bool) {

    self.group = group
    self.value = value
    self.allLinkDatabaseDelta = allLinkDatabaseDelta
    self.reading = reading
    self.isOn = isOn

  }

  /// The level in percent, for ``DeviceStatus/Reading/percent(_:)``, and otherwise `nil`.
  public var percent: Int? {

    if case let .percent(percent) = reading {

      return percent

    }

    return nil

  }

}

/// What ``Device/turnOn(level:group:)`` or ``Device/turnOnFast(level:)`` did.
///
/// A level means something only to a group that dims. A group that only turns on and off is
/// turned fully on, and the level asked for is in ``DeviceTurnOnResult/ignoredLevel``:
///
/// ```swift
/// let result = try await network.device(plug).turnOn(level: 50)
///
/// if let ignored = result.ignoredLevel {
///   print("on/off only, so \(ignored)% wasn't used")
/// }
/// ```
public struct DeviceTurnOnResult: Hashable, Sendable {

  /// The group that was turned on.
  public var group: Int

  /// The level the group was turned on at, from 0 through 100 percent, as the command sent
  /// it, when a level was asked for and the group dims; `nil` when it was turned fully on.
  public var level: Int?

  /// The level asked for when the group doesn't dim, so it was turned fully on instead;
  /// otherwise `nil`.
  public var ignoredLevel: Int?

  /// Whether the Insteon device catalog describes the command that was sent. When it doesn't
  /// describe the device's commands at all, the command the Insteon protocol defines was sent.
  public var isCommandDescribed: Bool

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - group: The group that was turned on.
  ///   - level: The level the group was turned on at.
  ///   - ignoredLevel: The level asked for that the group couldn't take.
  ///   - isCommandDescribed: Whether the catalog describes the command that was sent.
  ///     Defaults to `true`.
  public init(group: Int, level: Int?, ignoredLevel: Int?, isCommandDescribed: Bool = true) {

    self.group = group
    self.level = level
    self.ignoredLevel = ignoredLevel
    self.isCommandDescribed = isCommandDescribed

  }

}

/// What ``Device/turnOffFast()`` did.
public struct DeviceTurnOffResult: Hashable, Sendable {

  /// The group that was turned off.
  public var group: Int

  /// Whether the Insteon device catalog describes the command that was sent. When it doesn't
  /// describe the device's commands at all, the command the Insteon protocol defines was sent.
  public var isCommandDescribed: Bool

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - group: The group that was turned off.
  ///   - isCommandDescribed: Whether the catalog describes the command that was sent.
  public init(group: Int, isCommandDescribed: Bool) {

    self.group = group
    self.isCommandDescribed = isCommandDescribed

  }

}

/// What ``Device/changeInstantly(to:)`` did.
///
/// A group that dims goes to the level at once. A group that only turns on and off is turned
/// off for 0% and fully on for any other level.
public struct DeviceInstantChangeResult: Hashable, Sendable {

  /// The group that was changed.
  public var group: Int

  /// The level asked for, from 0 through 100 percent.
  public var level: Int

  /// Whether the group only turns on and off, so it was turned off for 0% and otherwise fully
  /// on.
  public var isOnOffOnly: Bool

  /// Whether the Insteon device catalog describes the command that was sent. When it doesn't
  /// describe the device's commands at all, the command the Insteon protocol defines was sent.
  public var isCommandDescribed: Bool

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - group: The group that was changed.
  ///   - level: The level asked for.
  ///   - isOnOffOnly: Whether the group only turns on and off.
  ///   - isCommandDescribed: Whether the catalog describes the command that was sent.
  public init(group: Int, level: Int, isOnOffOnly: Bool, isCommandDescribed: Bool) {

    self.group = group
    self.level = level
    self.isOnOffOnly = isOnOffOnly
    self.isCommandDescribed = isCommandDescribed

  }

}

/// What ``Device/beep()`` did.
///
/// Beep is sent whether or not the Insteon device catalog lists it for the device, since it's
/// harmless and the catalog doesn't list it for every device that beeps.
public struct DeviceBeepResult: Hashable, Sendable {

  /// Whether the device's command set lists Beep. When it doesn't, the Beep the Insteon
  /// protocol defines was sent.
  public var isListed: Bool

  /// Creates a result.
  ///
  /// - Parameter isListed: Whether the device's command set lists Beep.
  public init(isListed: Bool) {

    self.isListed = isListed

  }

}

/// Something a ``Device`` can be asked to do.
public enum DeviceOperation: String, Hashable, Sendable {

  /// Turning a group on.
  case turnOn

  /// Turning a group off.
  case turnOff

  /// Turning the main group on with Light On Fast.
  case turnOnFast

  /// Turning the main group off with Light Off Fast.
  case turnOffFast

  /// Changing the main group's level at once, with Light Instant Change.
  case instantChange

  /// Reading a group's state.
  case status

  /// Beep.
  case beep

  /// Reading or writing settings.
  case settings

  /// Keeping a battery-powered device awake while it links, or letting it sleep again.
  case keepAwake

}

/// Why a ``Device`` couldn't do what it was asked.
public enum DeviceControlError: Error, Hashable, Sendable {

  /// The device's identity isn't known, and it didn't report one when asked, so nothing says
  /// how to do the operation. It can still be pinged, and its status read as a raw byte.
  case notIdentified(DeviceOperation)

  /// The device rejected the modem when asked for its identity, as an i2CS device does when it
  /// isn't linked to the modem, so it can't be asked or controlled until it's linked.
  case notLinked

  /// Neither the Insteon device catalog nor the device's category gives a way to do the
  /// operation. The associated values are the operation and the product, as a sentence names
  /// it, such as `"Dimmer Switch 2477D (SwitchLinc Dimmer)"` or
  /// `"category 0x07, subcategory 0x1A"`.
  case unsupported(DeviceOperation, product: String)

  /// The device has no group with the number that can be controlled or read. The associated
  /// values are the group and the product.
  case noSuchGroup(Int, product: String)

  /// The group's type names a command its command set doesn't describe. The associated values
  /// are the command's name and the product.
  case missingCommand(String, product: String)

  /// The group's command doesn't reach the group apart from the device's other groups: it
  /// sends the same message as another group's, such as Light On without a group, which
  /// reaches the main group, or no message at all. The associated values are the operation,
  /// the group and the product.
  case unaddressable(DeviceOperation, group: Int, product: String)

  /// The group has no output by the name given, or its type names none. The associated values
  /// are the name asked for, the group and the product.
  case noSuchOutput(String, group: Int, product: String)

  /// The group's load isn't its outputs while the operating flag its type names isn't in the
  /// state it names, such as a ballast dimmer that's not in relay mode, so an output can't be
  /// switched on its own. The associated values are the group and the product.
  case outputsInactive(group: Int, product: String)

}
