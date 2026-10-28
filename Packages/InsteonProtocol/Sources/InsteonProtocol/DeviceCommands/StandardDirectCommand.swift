/// Common commands sent to a single device in a standard-length direct message.
///
/// ```swift
/// let message = StandardMessage(
///   to: InsteonAddress(0x1A, 0x2B, 0x3C),
///   command: StandardDirectCommand.on(level: 0xFF)
/// )
/// ```
public enum StandardDirectCommand: Hashable, Sendable {

  /// Tells a responder to join a controller's `group` (cmd1 `0x01`).
  ///
  /// In i1 SET button linking, a controller in linking mode sends this to a device that
  /// broadcast ``SetButtonPressed`` as a responder, and the device acknowledges once it has
  /// joined.
  case assignToAllLinkGroup(group: AllLinkGroupNumber)

  /// Tells a responder to leave a controller's `group` (cmd1 `0x02`).
  ///
  /// The unlinking counterpart of ``StandardDirectCommand/assignToAllLinkGroup(group:)``.
  case deleteFromAllLinkGroup(group: AllLinkGroupNumber)

  /// Requests the device's product data (cmd1 `0x03`, cmd2 `0x00`).
  ///
  /// The device answers with an extended message; read it with ``ProductData``.
  case productDataRequest

  /// Takes the device out of linking or unlinking mode (cmd1 `0x08`).
  ///
  /// Devices also leave linking mode on their own after a timeout. Insteon's documents disagree
  /// on which devices accept the command: one command table lists it for every i2 device,
  /// another says only SmartLinc and i2cs products support it, and the Developer's Guide
  /// reserves cmd1 `0x08`. The i2cs command sheet says an i2cs device always acts on it, as a
  /// standard or extended message, even when it NAKs it because the sender isn't in its
  /// ALL-Link database.
  case exitLinkingMode

  /// Puts the device into linking mode for `group`, as if its SET button were held (cmd1 `0x09`).
  ///
  /// Sending it is remote linking, which links a device without anyone pressing its SET
  /// button. Like the SET button, it doesn't choose the device's role: the device becomes the
  /// controller of a device that's waiting to respond, and a responder to a controller that's
  /// already in linking mode, such as a modem started with
  /// ``SerialCommand/startAllLinking(mode:group:)``. Devices with only one group ignore `group`.
  /// i2cs devices expect it in an extended message with a checksum. i1 devices don't accept it,
  /// so they're linked with their SET button.
  case enterLinkingMode(group: AllLinkGroupNumber)

  /// Puts the device into unlinking mode for `group` (cmd1 `0x0A`).
  ///
  /// Devices with only one group ignore `group`. i1 devices don't accept it.
  case enterUnlinkingMode(group: AllLinkGroupNumber)

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
  /// `flag` selects the flag and the operation; its meaning varies by device. i2cs devices
  /// accept it only in an extended message, which carries a checksum, so send it to them with
  /// `ExtendedMessage`.
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

/// The information requested by ``StandardDirectCommand/getOperatingFlags(_:)``, sent as cmd2.
///
/// The developer guide defines `0x00` through `0x02`. Devices define other requests for their
/// own data, such as `0x05` and `0x06` for more flags on KeypadLinc and SwitchLinc dimmers;
/// create those from their byte. What each request returns depends on the product.
///
/// ```swift
/// let moreFlags: OperatingFlagsRequest = 0x05
/// ```
public struct OperatingFlagsRequest: RawRepresentable, Hashable, Sendable {

  /// The request's byte.
  public let rawValue: UInt8

  /// Creates a request from its byte.
  ///
  /// - Parameter rawValue: The request's byte.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// The device's operating flags (`0x00`).
  public static let operatingFlags = OperatingFlagsRequest(rawValue: 0x00)

  /// The device's ALL-Link database delta, which changes whenever the database does (`0x01`).
  public static let allLinkDatabaseDelta = OperatingFlagsRequest(rawValue: 0x01)

  /// The device's measured signal-to-noise value (`0x02`).
  public static let signalToNoise = OperatingFlagsRequest(rawValue: 0x02)

}

extension OperatingFlagsRequest: ExpressibleByIntegerLiteral {

  /// Creates a request from an integer literal.
  ///
  /// - Parameter value: The request's byte.
  public init(integerLiteral value: UInt8) {

    self.init(rawValue: value)

  }

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
    case let .assignToAllLinkGroup(group):
      Command(command1: 0x01, command2: group.rawValue)
    case let .deleteFromAllLinkGroup(group):
      Command(command1: 0x02, command2: group.rawValue)
    case .productDataRequest:
      Command(command1: 0x03)
    case .exitLinkingMode:
      Command(command1: 0x08)
    case let .enterLinkingMode(group):
      Command(command1: 0x09, command2: group.rawValue)
    case let .enterUnlinkingMode(group):
      Command(command1: 0x0A, command2: group.rawValue)
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
  /// Every device accepts the base commands, such as on, off, ping and the ALL-Link group
  /// commands. The i2 engine adds remote linking, which i1 devices don't accept, along with setting
  /// operating flags, operating flags requests `0x00` through `0x02` and status request variants
  /// `0x01` through `0x04`, which some i1 devices also accept. What a request, variant or flag
  /// reports still depends on the product. Other requests and commands, such as
  /// ``StandardDirectCommand/beep`` and the ramp rate commands, are specific to certain products
  /// and firmware versions; look those up in a device database.
  public var minimumEngine: InsteonEngine? {

    switch self {
    case .assignToAllLinkGroup, .deleteFromAllLinkGroup, .getEngineVersion, .ping, .idRequest, .on,
         .fastOn, .off, .fastOff, .brightenOneStep, .dimOneStep, .startManualChange,
         .stopManualChange:
      .i1
    case let .statusRequest(variant):
      switch variant {
      case 0x00: .i1
      case 0x01...0x04: .i2
      default: nil
      }
    case let .getOperatingFlags(request):
      request.rawValue <= OperatingFlagsRequest.signalToNoise.rawValue ? .i2 : nil
    case .exitLinkingMode, .enterLinkingMode, .enterUnlinkingMode, .setOperatingFlags:
      .i2
    case .productDataRequest, .instantChange, .remoteSetButtonTap, .onAtRampRate, .offAtRampRate,
         .beep:
      nil
    }

  }

}
