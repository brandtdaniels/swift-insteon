/// Common commands sent to a single device in a standard-length direct message.
///
/// ```swift
/// let message = StandardMessage(
///   to: InsteonAddress(0x1A, 0x2B, 0x3C),
///   command: StandardDirectCommand.on(level: 0xFF)
/// )
/// ```
public enum StandardDirectCommand: Hashable, Sendable {

  /// Requests the device's product data (cmd1 `0x03`, cmd2 `0x00`).
  case productDataRequest

  /// Puts the device into linking mode as a controller of `group` (cmd1 `0x09`).
  case enterLinkingMode(group: UInt8)

  /// Puts the device into unlinking mode for `group` (cmd1 `0x0A`).
  case enterUnlinkingMode(group: UInt8)

  /// Requests the device's INSTEON engine version (cmd1 `0x0D`).
  ///
  /// The acknowledgement's cmd2 identifies the engine, distinguishing i1, i2 and i2cs devices.
  case getEngineVersion

  /// Checks that the device is reachable (cmd1 `0x0F`).
  case ping

  /// Asks the device to broadcast its device category and firmware (cmd1 `0x10`).
  case idRequest

  /// Turns the device on at `level`, using its configured ramp rate (cmd1 `0x11`).
  ///
  /// `0x00` is off and `0xFF` is fully on. On/off devices treat any nonzero level as on.
  case on(level: UInt8)

  /// Turns the device on at `level` immediately, ignoring its ramp rate (cmd1 `0x12`).
  case fastOn(level: UInt8)

  /// Turns the device off, using its configured ramp rate (cmd1 `0x13`).
  case off

  /// Turns the device off immediately (cmd1 `0x14`).
  case fastOff

  /// Brightens the device by one of its 32 steps (cmd1 `0x15`).
  case brightenOneStep

  /// Dims the device by one of its 32 steps (cmd1 `0x16`).
  case dimOneStep

  /// Starts brightening or dimming until ``StandardDirectCommand/stopManualChange`` is sent (cmd1 `0x17`).
  case startManualChange(direction: ManualChangeDirection)

  /// Stops a change started with ``StandardDirectCommand/startManualChange(direction:)`` (cmd1 `0x18`).
  case stopManualChange

  /// Requests the device's current state (cmd1 `0x19`).
  ///
  /// For most devices, the acknowledgement's cmd2 is the current level and its cmd1 is the
  /// ALL-Link database delta. Some devices use `variant` to select other status, such as a
  /// second load; most expect `0x00`.
  case statusRequest(variant: UInt8 = 0x00)

  /// Requests the device's operating flags or other configuration (cmd1 `0x1F`).
  case getOperatingFlags(OperatingFlagsRequest)

  /// Sets or clears one of the device's operating flags (cmd1 `0x20`).
  ///
  /// `flag` selects the flag and the operation; its meaning varies by device.
  case setOperatingFlags(flag: UInt8)

  /// Changes the device to `level` instantly (cmd1 `0x21`).
  case instantChange(level: UInt8)

  /// Simulates tapping the device's SET button (cmd1 `0x25`).
  case remoteSetButtonTap(SetButtonTapCount)

  /// Turns the device on at an on-level and ramp rate given as 4-bit values (cmd1 `0x2E`).
  ///
  /// Both values use only their low four bits; higher bits are ignored. cmd2 holds
  /// `onLevel` in its high nibble and `rampRate` in its low nibble.
  case onAtRampRate(onLevel: UInt8, rampRate: UInt8)

  /// Turns the device off at a ramp rate given as a 4-bit value (cmd1 `0x2F`).
  ///
  /// Only the low four bits of `rampRate` are used.
  case offAtRampRate(rampRate: UInt8)

  /// Makes the device beep (cmd1 `0x30`).
  case beep

}

/// The direction of a manual brightness change.
public enum ManualChangeDirection: UInt8, Hashable, Sendable {

  /// Dim the device.
  case down = 0x00

  /// Brighten the device.
  case up = 0x01

}

/// The information requested by ``StandardDirectCommand/getOperatingFlags(_:)``.
public enum OperatingFlagsRequest: UInt8, Hashable, Sendable {

  /// The device's operating flags.
  case operatingFlags = 0x00

  /// The device's ALL-Link database delta, which changes whenever the database does.
  case allLinkDatabaseDelta = 0x01

  /// The device's measured signal-to-noise value.
  case signalToNoise = 0x02

}

/// The number of SET button taps simulated by ``StandardDirectCommand/remoteSetButtonTap(_:)``.
public enum SetButtonTapCount: UInt8, Hashable, Sendable {

  /// A single tap.
  case one = 0x01

  /// A double tap.
  case two = 0x02

}

// MARK: - CommandConvertible

extension StandardDirectCommand: CommandConvertible {

  /// The command's cmd1 and cmd2 bytes.
  public var command: Command {

    switch self {
    case .productDataRequest:
      Command(command1: 0x03)
    case let .enterLinkingMode(group):
      Command(command1: 0x09, command2: group)
    case let .enterUnlinkingMode(group):
      Command(command1: 0x0A, command2: group)
    case .getEngineVersion:
      Command(command1: 0x0D)
    case .ping:
      Command(command1: 0x0F)
    case .idRequest:
      Command(command1: 0x10)
    case let .on(level):
      Command(command1: 0x11, command2: level)
    case let .fastOn(level):
      Command(command1: 0x12, command2: level)
    case .off:
      Command(command1: 0x13)
    case .fastOff:
      Command(command1: 0x14)
    case .brightenOneStep:
      Command(command1: 0x15)
    case .dimOneStep:
      Command(command1: 0x16)
    case let .startManualChange(direction):
      Command(command1: 0x17, command2: direction.rawValue)
    case .stopManualChange:
      Command(command1: 0x18)
    case let .statusRequest(variant):
      Command(command1: 0x19, command2: variant)
    case let .getOperatingFlags(request):
      Command(command1: 0x1F, command2: request.rawValue)
    case let .setOperatingFlags(flag):
      Command(command1: 0x20, command2: flag)
    case let .instantChange(level):
      Command(command1: 0x21, command2: level)
    case let .remoteSetButtonTap(count):
      Command(command1: 0x25, command2: count.rawValue)
    case let .onAtRampRate(onLevel, rampRate):
      Command(command1: 0x2E, command2: (onLevel & 0x0F) << 4 | (rampRate & 0x0F))
    case let .offAtRampRate(rampRate):
      Command(command1: 0x2F, command2: rampRate & 0x0F)
    case .beep:
      Command(command1: 0x30)
    }

  }

}
