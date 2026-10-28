/// A controller's Success Report: the broadcast (cmd1 `0x06`) that ends a group command, once
/// the controller has sent its cleanups.
///
/// Insteon's command tables give its To address as the command, the number of group members
/// and the group number, and its cmd2 as the number of cleanups that failed. For example,
/// `13 02 08` in the To address reports that off (`0x13`) went to the 2 members of group 8.
public struct SuccessReport: Hashable, Sendable {

  /// The cmd1 of a Success Report: `0x06`.
  public static let command1: UInt8 = 0x06

  /// The controller that sent the group command.
  public var controller: InsteonAddress

  /// The command the controller sent.
  public var command: UInt8

  /// How many members the group has.
  public var memberCount: UInt8

  /// The group the command went to.
  public var group: AllLinkGroupNumber

  /// How many members didn't acknowledge their cleanup.
  public var failedCleanups: UInt8

  /// Creates a success report.
  ///
  /// - Parameters:
  ///   - controller: The controller that sent the group command.
  ///   - command: The command it sent.
  ///   - memberCount: How many members the group has.
  ///   - group: The group the command went to.
  ///   - failedCleanups: How many members didn't acknowledge their cleanup.
  public init(controller: InsteonAddress, command: UInt8, memberCount: UInt8, group: AllLinkGroupNumber, failedCleanups: UInt8) {

    self.controller = controller
    self.command = command
    self.memberCount = memberCount
    self.group = group
    self.failedCleanups = failedCleanups

  }

  /// Reads a success report from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is a standard ALL-Link broadcast with cmd1 `0x06`.
  public init?(_ message: ReceivedMessage) {

    guard message.isStandardBroadcast(command1: Self.command1, type: .allLinkBroadcast) else {

      return nil

    }

    self.init(
      controller: message.sender,
      command: message.destination.high,
      memberCount: message.destination.middle,
      group: AllLinkGroupNumber(rawValue: message.destination.low),
      failedCleanups: message.command.command2
    )

  }

}
