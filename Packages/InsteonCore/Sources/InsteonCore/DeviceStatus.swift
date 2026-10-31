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

/// What ``Device/turnOn(level:group:)`` did.
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

  /// The level the group was turned on at, from 0 through 100 percent, when a level was asked
  /// for and the group dims; `nil` when it was turned fully on.
  public var level: Int?

  /// The level asked for, from 0 through 100 percent, when the group doesn't dim, so it was
  /// turned fully on instead; otherwise `nil`.
  public var ignoredLevel: Int?

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - group: The group that was turned on.
  ///   - level: The level the group was turned on at.
  ///   - ignoredLevel: The level asked for that the group couldn't take.
  public init(group: Int, level: Int?, ignoredLevel: Int?) {

    self.group = group
    self.level = level
    self.ignoredLevel = ignoredLevel

  }

}

/// Something a ``Device`` can be asked to do.
public enum DeviceOperation: String, Hashable, Sendable {

  /// Turning a group on.
  case turnOn

  /// Turning a group off.
  case turnOff

  /// Reading a group's state.
  case status

  /// Beep.
  case beep

  /// Reading or writing settings.
  case settings

}

/// Why a ``Device`` couldn't do what it was asked.
public enum DeviceControlError: Error, Hashable, Sendable {

  /// The device's identity isn't known, and it didn't report one when asked, so nothing says
  /// how to do the operation. It can still be pinged, and its status read as a raw byte.
  case notIdentified(DeviceOperation)

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

}
