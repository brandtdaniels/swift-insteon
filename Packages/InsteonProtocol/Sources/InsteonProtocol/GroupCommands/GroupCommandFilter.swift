/// Turns the broadcasts and cleanups a modem hears into one ``GroupCommand`` per command a
/// controller sends.
///
/// A controller sends each group command several times: once as an ALL-Link broadcast, then as
/// a cleanup to each member, and sensors send each broadcast twice. The filter passes a command
/// on once:
///
/// - A broadcast that repeats one passed on for the same controller and group, with the same
///   cmd1 and cmd2, within ``GroupCommandFilter/duplicateWindow`` is a repeat of the same press.
/// - A cleanup repeats a command the controller sent shortly before, so, as the Developer's
///   Guide says a member does, the filter ignores a cleanup for any command it passed on for
///   that controller and group within ``GroupCommandFilter/cleanupWindow``. That includes a late
///   cleanup for an earlier command than the last. A cleanup for a command it hasn't seen in
///   that time means the broadcast was missed, so it's passed on.
/// - A controller's ``SuccessReport`` says its cleanups are over, so after one, a cleanup for
///   that group is a new command.
///
/// The filter keeps no clock of its own: give it the time each message arrived, from any
/// clock, so tests can use one they control. A message stamped earlier than one before it
/// counts as arriving at the same time.
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
public struct GroupCommandFilter<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration, Instant: Sendable {

  /// How long after a broadcast the same broadcast counts as a repeat by default: 1 second.
  ///
  /// The Insteon Developer's Guide doesn't give a time, so this is chosen to cover a device sending
  /// a broadcast twice in a row while letting a person's second press through.
  public static var defaultDuplicateWindow: Duration { .seconds(1) }

  /// How long after a command its cleanups are expected by default: 10 seconds.
  ///
  /// The Insteon Developer's Guide gives the worst case as 2.150 seconds from the broadcast to the
  /// first member's cleanup and 1.550 seconds to each one after, so 10 seconds covers a group
  /// of up to six members that all need every retry.
  public static var defaultCleanupWindow: Duration { .seconds(10) }

  /// A command passed on for a controller's group, and when.
  private struct Sent: Sendable {

    let command1: UInt8

    /// The broadcast's cmd2, or `nil` for a command passed on from a cleanup.
    let command2: UInt8?

    let instant: Instant

  }

  /// A controller's group.
  private struct Key: Hashable, Sendable {

    let controller: InsteonAddress

    let group: AllLinkGroupNumber

  }

  /// How long after a broadcast the same broadcast counts as a repeat.
  public let duplicateWindow: Duration

  /// How long after a command its cleanups are expected.
  public let cleanupWindow: Duration

  /// The commands passed on for each controller's group within the longer window, oldest first.
  private var recent: [Key: [Sent]] = [:]

  /// Creates a filter that has heard nothing yet.
  ///
  /// - Parameters:
  ///   - duplicateWindow: How long after a broadcast the same broadcast counts as a repeat.
  ///     Defaults to ``GroupCommandFilter/defaultDuplicateWindow``.
  ///   - cleanupWindow: How long after a command its cleanups are expected. Defaults to
  ///     ``GroupCommandFilter/defaultCleanupWindow``.
  public init(duplicateWindow: Duration = Self.defaultDuplicateWindow, cleanupWindow: Duration = Self.defaultCleanupWindow) {

    self.duplicateWindow = duplicateWindow
    self.cleanupWindow = cleanupWindow

  }

  /// The group command a message carries, unless it repeats one already passed on.
  ///
  /// - Parameters:
  ///   - message: A message the modem received.
  ///   - instant: When the message arrived.
  /// - Returns: The command, or `nil` if the message isn't a group command or repeats one.
  public mutating func command(from message: ReceivedMessage, at instant: Instant) -> GroupCommand? {

    if let report = SuccessReport(message) {

      recent[Key(controller: report.controller, group: report.group)] = nil

      return nil

    }

    guard let command = GroupCommand(message) else {

      return nil

    }

    let key = Key(controller: command.controller, group: command.group)

    // Only what's within the longer window can make a message a repeat.
    let longest = max(duplicateWindow, cleanupWindow)
    var sent = (recent[key] ?? []).filter { age(of: $0, at: instant) < longest }

    let isRepeat: Bool

    switch command.source {
    case .broadcast:
      isRepeat = sent.contains { earlier in

        earlier.command1 == command.command1 && earlier.command2 == command.command2
          && age(of: earlier, at: instant) < duplicateWindow

      }
    case .cleanup:
      isRepeat = sent.contains { $0.command1 == command.command1 && age(of: $0, at: instant) < cleanupWindow }
    }

    if !isRepeat {

      sent.append(Sent(command1: command.command1, command2: command.command2, instant: instant))

    }

    recent[key] = sent

    return isRepeat ? nil : command

  }

  /// How long ago a command was passed on, or zero if it was stamped later than `instant`.
  private func age(of sent: Sent, at instant: Instant) -> Duration {

    max(.zero, sent.instant.duration(to: instant))

  }

}
