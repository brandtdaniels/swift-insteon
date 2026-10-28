/// A Test RF broadcast, which an i3 device sends once a second to show which devices are within
/// radio range of it.
///
/// The i3 developer specifications describe it: pressing the device's SET button three times
/// while its Programming Lock is set starts the broadcasts, and a fourth press stops them. The
/// device sends them by radio only, never over the powerline, and they're never hopped; a
/// device that hears one flashes its LED once.
///
/// It has the same cmd1 and cmd2 as a ``PowerlinePhaseTest`` for phase A. Its To address is
/// `00.00.00`, where a phase test's, like any broadcast's, holds the sender's category,
/// subcategory and firmware version.
public struct RadioRangeTest: Hashable, Sendable {

  /// The device that sent the broadcast.
  public var sender: InsteonAddress

  /// Creates a Test RF broadcast.
  ///
  /// - Parameter sender: The device that sent the broadcast.
  public init(sender: InsteonAddress) {

    self.sender = sender

  }

  /// Reads a Test RF broadcast from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is a standard-length broadcast to `00.00.00` with
  ///   cmd1 `0x03` and cmd2 `0x00`.
  public init?(_ message: ReceivedMessage) {

    guard
      message.isStandardBroadcast(command1: 0x03),
      message.command.command2 == 0x00,
      message.destination == RadioRangeTest.destination
    else {

      return nil

    }

    self.init(sender: message.sender)

  }

  /// The To address of a Test RF broadcast.
  static let destination = InsteonAddress(0x00, 0x00, 0x00)

}
