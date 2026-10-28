/// Turns the broadcasts and cleanups a modem hears into one ``GroupCommand`` per command a
/// controller sends.
///
/// A controller sends each group command several times: once as an ALL-Link broadcast, then as
/// a cleanup to each member, and sensors send each broadcast twice. The filter passes a command
/// on once:
///
/// - A cleanup repeats the broadcast before it, so, as the Developer's Guide says a member
///   does, the filter ignores a cleanup for the command it last passed on for that controller
///   and group. A cleanup for a different command means the broadcast was missed, so it's
///   passed on.
/// - A broadcast that repeats the command last passed on for that controller and group within
///   ``GroupCommandFilter/duplicateWindow`` is a repeat of the same press, and is ignored. A
///   repeat after the window is a new press.
///
/// The filter keeps no clock of its own: give it the time each message arrived, from any
/// clock, so tests can use one they control.
///
/// ```swift
/// var filter = GroupCommandFilter<ContinuousClock.Instant>()
///
/// for await reply in await modem.replies() {
///   if case let .messageReceived(message) = reply, let command = filter.command(from: message, at: .now) {
///     print(command.controller, command.group, command.command1)
///   }
/// }
/// ```
///
/// A command repeated through cleanups alone, without its broadcast, such as a second press
/// whose broadcast was also missed, can't be told from the first one's cleanups, so it's
/// passed on once.
public struct GroupCommandFilter<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration, Instant: Sendable {

  /// How long after a broadcast the same broadcast counts as a repeat by default: 1 second.
  ///
  /// The Developer's Guide doesn't give a time, so this is chosen to cover a device sending a
  /// broadcast twice in a row while letting a person's second press through.
  public static var defaultDuplicateWindow: Duration { .seconds(1) }

  /// The last command passed on for a controller's group.
  private struct Last: Sendable {

    let command1: UInt8

    let broadcastAt: Instant?

  }

  /// A controller's group.
  private struct Key: Hashable, Sendable {

    let controller: InsteonAddress

    let group: AllLinkGroupNumber

  }

  /// How long after a broadcast the same broadcast counts as a repeat.
  public let duplicateWindow: Duration

  private var last: [Key: Last] = [:]

  /// Creates a filter that has heard nothing yet.
  ///
  /// - Parameter duplicateWindow: How long after a broadcast the same broadcast counts as a
  ///   repeat. Defaults to ``GroupCommandFilter/defaultDuplicateWindow``.
  public init(duplicateWindow: Duration = Self.defaultDuplicateWindow) {

    self.duplicateWindow = duplicateWindow

  }

  /// The group command a message carries, unless it repeats one already passed on.
  ///
  /// - Parameters:
  ///   - message: A message the modem received.
  ///   - instant: When the message arrived.
  /// - Returns: The command, or `nil` if the message isn't a group command or repeats one.
  public mutating func command(from message: ReceivedMessage, at instant: Instant) -> GroupCommand? {

    guard let command = GroupCommand(message) else {

      return nil

    }

    let key = Key(controller: command.controller, group: command.group)
    let previous = last[key]

    switch command.source {
    case .broadcast:
      if let previous, previous.command1 == command.command1, let at = previous.broadcastAt, at.duration(to: instant) < duplicateWindow {

        return nil

      }

      last[key] = Last(command1: command.command1, broadcastAt: instant)
    case .cleanup:
      if previous?.command1 == command.command1 {

        return nil

      }

      last[key] = Last(command1: command.command1, broadcastAt: nil)
    }

    return command

  }

}
