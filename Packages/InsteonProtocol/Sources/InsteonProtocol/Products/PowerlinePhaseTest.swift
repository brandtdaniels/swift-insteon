/// A test powerline phase broadcast, which a dual-band device sends so devices that hear it
/// can show whether they're on the same phase of the home's wiring.
///
/// The Insteon Developer's Guide says it's "only sent by i2/RF devices, with Max Hops = 0", so only
/// devices in range hear it. A device on the same phase blinks its LED fast for 10 seconds,
/// and one on the opposite phase blinks slowly.
public struct PowerlinePhaseTest: Hashable, Sendable {

  /// A phase of a home's split-phase wiring.
  public enum Phase: UInt8, Hashable, Sendable {

    /// Phase A, the low cycle (cmd2 `0x00`).
    case a = 0x00

    /// Phase B, the high cycle (cmd2 `0x01`).
    case b = 0x01

  }

  /// The device that sent the broadcast.
  public var sender: InsteonAddress

  /// The phase the sender is on.
  public var phase: Phase

  /// Creates a test powerline phase broadcast.
  ///
  /// - Parameters:
  ///   - sender: The device that sent the broadcast.
  ///   - phase: The phase the sender is on.
  public init(sender: InsteonAddress, phase: Phase) {

    self.sender = sender
    self.phase = phase

  }

  /// Reads a test powerline phase broadcast from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is a standard-length broadcast with cmd1 `0x03` and
  ///   cmd2 `0x00` or `0x01`. A broadcast to `00.00.00` with cmd2 `0x00` is an i3 device's
  ///   ``RadioRangeTest`` instead.
  public init?(_ message: ReceivedMessage) {

    guard
      message.isStandardBroadcast(command1: 0x03),
      message.destination != RadioRangeTest.destination,
      let phase = Phase(rawValue: message.command.command2)
    else {

      return nil

    }

    self.init(sender: message.sender, phase: phase)

  }

}
