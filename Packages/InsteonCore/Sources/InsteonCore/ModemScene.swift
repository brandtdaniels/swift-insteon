import InsteonLinking
import InsteonModem
import InsteonProtocol

/// One of the modem's scenes: an ALL-Link group the modem controls, whose responders turn on or
/// off together when the modem sends the group a command.
///
/// ```swift
/// let scene = ModemScene(group: group)
/// let responders = try await scene.responders(in: session)
/// let report = try await scene.send(turningOn: true, through: session)
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

    responders(among: try await modem.allLinkRecords())

  }

  /// The devices a copy of the modem's ALL-Link database lists as the group's responders, each
  /// once, in the order of their addresses as text.
  ///
  /// - Parameter records: The modem's records.
  /// - Returns: The responders' addresses.
  func responders(among records: [AllLinkRecord]) -> [InsteonAddress] {

    let members: [InsteonAddress] = records.filter { $0.flags.contains(.controller) && $0.group == group }.map(\.address)

    return Array(Set(members)).sorted { $0.description < $1.description }

  }

  /// Sends the group Light On at full level, or Light Off, and waits for the modem's ALL-Link
  /// cleanups.
  ///
  /// - Parameters:
  ///   - isOn: Whether to turn the group's responders on, or off.
  ///   - modem: The modem that sends the command.
  ///   - wait: How long to wait for the modem's echo and its cleanups.
  /// - Returns: Which responders acknowledged their cleanup, which didn't, and whether the
  ///   modem reached them all.
  /// - Throws: `ModemError.rejected` if the modem rejects the command, as it does for a group
  ///   it has no records for, the modem's other errors, or `CancellationError` if the task is
  ///   canceled.
  func send(turningOn isOn: Bool, through modem: any LinkingModem, wait: AllLinkCleanupWait = .standard) async throws -> AllLinkCleanupReport {

    let command: Command = isOn ? StandardDirectCommand.on(level: .max).command : StandardDirectCommand.off.command

    return try await modem.sendAllLinkCommand(group: group, command: command, wait: wait)

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
  ///   - session: The session whose modem sends the command.
  ///   - wait: How long to wait for the modem's echo and its cleanups.
  /// - Returns: Which responders acknowledged their cleanup, which didn't, and whether the
  ///   modem reached them all.
  /// - Throws: The modem's error, which ``SendFailure`` reads as
  ///   ``SendFailure/modemRejected`` for a group the modem has no records for, or
  ///   `CancellationError`.
  public func send(turningOn isOn: Bool, through session: ModemSession, wait: AllLinkCleanupWait = .standard) async throws -> SceneResult {

    let report: AllLinkCleanupReport = try await send(turningOn: isOn, through: session.modem, wait: wait)

    return SceneResult(report)

  }

}
