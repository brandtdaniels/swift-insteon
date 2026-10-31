import InsteonLinking
import InsteonModem
import InsteonProtocol

/// One of the modem's scenes: an ALL-Link group the modem controls, whose responders turn on or
/// off together when the modem sends the group a command.
///
/// ```swift
/// let scene = ModemScene(group: group)
/// let responders = try await scene.responders(in: session)
/// let report = try await scene.send(turningOn: true, responderCount: responders.count, through: session)
///
/// print(report.acknowledged.count, "of", responders.count, "acknowledged")
/// ```
public struct ModemScene: Hashable, Sendable {

  /// The modem's ALL-Link group.
  public var group: AllLinkGroupNumber

  /// Creates a scene.
  ///
  /// - Parameter group: The modem's ALL-Link group.
  public init(group: AllLinkGroupNumber) {

    self.group = group

  }

  /// The devices the modem's ALL-Link database lists as the group's responders, each once,
  /// in the order of their addresses as text.
  ///
  /// The modem controls each of the group's devices, so it keeps a controller record for each
  /// in the group, and each device keeps a responder record for it.
  ///
  /// - Parameter modem: The modem, whose ALL-Link database is read.
  /// - Returns: The responders' addresses.
  /// - Throws: The modem's error, or `CancellationError` if the task is canceled.
  func responders(in modem: any LinkingModem) async throws -> [InsteonAddress] {

    let records: [AllLinkRecord] = try await modem.allLinkRecords()
    let members: [InsteonAddress] = records.filter { $0.flags.contains(.controller) && $0.group == group }.map(\.address)

    return Array(Set(members)).sorted { $0.description < $1.description }

  }

  /// How long to wait for the modem to send every responder its ALL-Link cleanup.
  ///
  /// The Insteon Developer's Guide gives up to 2.150 seconds to the first cleanup and 1.550
  /// seconds to each one after, so this allows 3 seconds and 2 more for each responder, and
  /// never less than 10 seconds.
  ///
  /// - Parameter responderCount: How many responders the group has.
  /// - Returns: The time to wait.
  public static func cleanupTimeout(responderCount: Int) -> Duration {

    .seconds(max(10, 3 + 2 * responderCount))

  }

  /// Sends the group Light On at full level, or Light Off, and waits for the modem's ALL-Link
  /// cleanups.
  ///
  /// - Parameters:
  ///   - isOn: Whether to turn the group's responders on, or off.
  ///   - responderCount: How many responders the group has, such as `responders(in:)`
  ///     gives, which sets how long to wait with ``cleanupTimeout(responderCount:)``.
  ///   - modem: The modem that sends the command.
  /// - Returns: Which responders acknowledged their cleanup, which didn't, and whether the
  ///   modem reached them all.
  /// - Throws: `ModemError.rejected` if the modem rejects the command, as it does for a group
  ///   it has no records for, the modem's other errors, or `CancellationError` if the task is
  ///   canceled.
  func send(turningOn isOn: Bool, responderCount: Int, through modem: Modem) async throws -> AllLinkCleanupReport {

    let command: Command = isOn ? StandardDirectCommand.on(level: .max).command : StandardDirectCommand.off.command

    return try await modem.sendAllLinkCommand(group: group, command: command, timeout: Self.cleanupTimeout(responderCount: responderCount))

  }

  /// The devices the modem's ALL-Link database lists as the group's responders, each once,
  /// in the order of their addresses as text.
  ///
  /// The modem controls each of the group's devices, so it keeps a controller record for each
  /// in the group, and each device keeps a responder record for it.
  ///
  /// - Parameter session: The session whose modem's ALL-Link database is read.
  /// - Returns: The responders' addresses.
  /// - Throws: The modem's error, or `CancellationError` if the task is canceled.
  public func responders(in session: ModemSession) async throws -> [InsteonAddress] {

    try await responders(in: session.modem)

  }

  /// Sends the group Light On at full level, or Light Off, through a session's modem, and
  /// waits for the modem's ALL-Link cleanups.
  ///
  /// - Parameters:
  ///   - isOn: Whether to turn the group's responders on, or off.
  ///   - responderCount: How many responders the group has, which sets how long to wait with
  ///     ``cleanupTimeout(responderCount:)``.
  ///   - session: The session whose modem sends the command.
  /// - Returns: Which responders acknowledged their cleanup, which didn't, and whether the
  ///   modem reached them all.
  /// - Throws: The modem's error, which ``SendFailure`` reads as
  ///   ``SendFailure/modemRejected`` for a group the modem has no records for, or
  ///   `CancellationError`.
  public func send(turningOn isOn: Bool, responderCount: Int, through session: ModemSession) async throws -> AllLinkCleanupReport {

    try await send(turningOn: isOn, responderCount: responderCount, through: session.modem)

  }

}
