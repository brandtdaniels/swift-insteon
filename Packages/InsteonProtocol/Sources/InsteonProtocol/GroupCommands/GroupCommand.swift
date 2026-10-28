/// A command a controller sent to one of its ALL-Link groups, such as a keypad button
/// turning on its scene or a motion sensor reporting motion.
///
/// A controller first broadcasts the command to the whole group, with the group number in the
/// To address and the command in cmd1, then sends each member a cleanup message, which carries
/// the command in cmd1 and the group number in cmd2. Either one can be read as the command;
/// ``GroupCommandFilter`` turns the stream of both into one command per press.
///
/// ```swift
/// if case let .messageReceived(message) = reply, let command = GroupCommand(message) {
///   print(command.controller, command.group, command.command1)
/// }
/// ```
public struct GroupCommand: Hashable, Sendable {

  /// Whether the command was read from the broadcast or from a cleanup.
  public enum Source: Hashable, Sendable {

    /// The ALL-Link broadcast to the whole group.
    case broadcast

    /// A cleanup message to one member, which arrives when the broadcast was missed.
    case cleanup

  }

  /// The device that sent the command.
  public var controller: InsteonAddress

  /// The controller's group the command was sent to.
  public var group: AllLinkGroupNumber

  /// The command, such as `0x11` for on or `0x13` for off.
  public var command1: UInt8

  /// The broadcast's cmd2, or `nil` for a command read from a cleanup, whose cmd2 carries the
  /// group number instead.
  public var command2: UInt8?

  /// Where the command was read from.
  public var source: Source

  /// Creates a group command.
  ///
  /// - Parameters:
  ///   - controller: The device that sent the command.
  ///   - group: The controller's group.
  ///   - command1: The command.
  ///   - command2: The broadcast's cmd2, or `nil` for a cleanup.
  ///   - source: Where the command was read from.
  public init(controller: InsteonAddress, group: AllLinkGroupNumber, command1: UInt8, command2: UInt8?, source: Source) {

    self.controller = controller
    self.group = group
    self.command1 = command1
    self.command2 = command2
    self.source = source

  }

  /// Reads a group command from an ALL-Link broadcast or ALL-Link cleanup message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is a standard ALL-Link broadcast, other than a
  ///   ``SuccessReport``, or a standard ALL-Link cleanup.
  public init?(_ message: ReceivedMessage) {

    guard !message.flags.isExtended else {

      return nil

    }

    switch message.flags.messageType {
    case .allLinkBroadcast:
      // The guide: the To address holds the group number in its low byte.
      guard
        message.destination.high == 0x00,
        message.destination.middle == 0x00,
        message.command.command1 != SuccessReport.command1
      else {

        return nil

      }

      self.init(
        controller: message.sender,
        group: AllLinkGroupNumber(rawValue: message.destination.low),
        command1: message.command.command1,
        command2: message.command.command2,
        source: .broadcast
      )
    case .allLinkCleanup:
      self.init(
        controller: message.sender,
        group: AllLinkGroupNumber(rawValue: message.command.command2),
        command1: message.command.command1,
        command2: nil,
        source: .cleanup
      )
    default:
      return nil
    }

  }

}
