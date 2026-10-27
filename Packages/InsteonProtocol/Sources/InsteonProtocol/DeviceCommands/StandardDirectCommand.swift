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
  ///
  /// The device answers with an extended message; read it with ``ProductData``.
  case productDataRequest

  /// Takes the device out of linking or unlinking mode (cmd1 `0x08`).
  ///
  /// Devices also leave linking mode on their own after a timeout.
  case exitLinkingMode

  /// Puts the device into linking mode as a controller of `group` (cmd1 `0x09`).
  case enterLinkingMode(group: UInt8)

  /// Puts the device into unlinking mode for `group` (cmd1 `0x0A`).
  case enterUnlinkingMode(group: UInt8)

  /// Requests the device's INSTEON engine version (cmd1 `0x0D`).
  ///
  /// The acknowledgement's cmd2 identifies the engine; read it with ``InsteonEngine``.
  case getEngineVersion

  /// Checks that the device is reachable (cmd1 `0x0F`).
  case ping

  /// Asks the device to identify itself (cmd1 `0x10`).
  ///
  /// The device answers with a broadcast; read it with ``SetButtonPressed``.
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

  /// Simulates tapping the SET button of a dimmable device (cmd1 `0x25`).
  ///
  /// One tap makes the device's current level its on-level; two taps make its current ramp
  /// rate the default.
  case remoteSetButtonTap(SetButtonTapCount)

  /// Turns the device on at an on-level and ramp rate given as 4-bit values (cmd1 `0x2E`).
  ///
  /// cmd2 holds `onLevel` in its high nibble and `rampRate` in its low nibble; higher bits of
  /// each are ignored. The device turns on to level `16 × onLevel + 0x0F` at ramp rate
  /// `2 × rampRate + 1`, on the scale from `0x00`, about nine minutes, to `0x1F`, 0.1 second.
  /// So `onLevel: 0xF, rampRate: 0xF` turns fully on at ramp rate `0x1F`, the fastest. The
  /// ramp rate applies to dimmable devices only.
  case onAtRampRate(onLevel: UInt8, rampRate: UInt8)

  /// Turns the device off at a ramp rate given as a 4-bit value (cmd1 `0x2F`).
  ///
  /// Only the low four bits of `rampRate` are used; the device ramps off at rate
  /// `2 × rampRate + 1`.
  case offAtRampRate(rampRate: UInt8)

  /// Makes the device beep for its standard duration, if it has a beeper (cmd1 `0x30`).
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

  /// A single tap, which sets the device's on-level to its current level.
  case one = 0x01

  /// A double tap, which sets the device's default ramp rate to its current ramp rate.
  case two = 0x02

}

// MARK: - StandardCommandConvertible

extension StandardDirectCommand: StandardCommandConvertible {

  /// The command's cmd1 and cmd2 bytes.
  public var command: Command {

    switch self {
    case .productDataRequest:
      Command(command1: 0x03)
    case .exitLinkingMode:
      Command(command1: 0x08)
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

// MARK: - Engine support

extension StandardDirectCommand {

  /// The earliest engine on which every device accepts the command, or `nil` when that
  /// depends on the product.
  ///
  /// Every device accepts the base commands, such as on, off, ping and linking. The i2 engine
  /// adds exit linking mode, the operating flags and status request variants `0x01` through
  /// `0x04`, which some i1 devices also accept. What a variant or flag reports still depends on
  /// the product. Other commands, such as ``StandardDirectCommand/beep`` and the ramp rate
  /// commands, are specific to certain products and firmware versions; look those up in a
  /// product database.
  public var minimumEngine: InsteonEngine? {

    switch self {
    case .enterLinkingMode, .enterUnlinkingMode, .getEngineVersion, .ping, .idRequest, .on, .fastOn,
         .off, .fastOff, .brightenOneStep, .dimOneStep, .startManualChange, .stopManualChange:
      .i1
    case let .statusRequest(variant):
      switch variant {
      case 0x00: .i1
      case 0x01...0x04: .i2
      default: nil
      }
    case .exitLinkingMode, .getOperatingFlags, .setOperatingFlags:
      .i2
    case .productDataRequest, .instantChange, .remoteSetButtonTap, .onAtRampRate, .offAtRampRate,
         .beep:
      nil
    }

  }

}
