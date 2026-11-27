import InsteonLinking
import InsteonModem
import InsteonProtocol

extension DeviceNetwork {

  /// Sends one of the modem's scenes Light On at full level, or Light Off, and waits for the
  /// modem's ALL-Link cleanups.
  ///
  /// The network's copy of the modem's ALL-Link database, read from the modem only when the
  /// network holds none, says how many controller records the group has, which the result
  /// reports so a missing report can say how many responders were expected. Nothing is sent to a device, and the network's record of the devices' levels is left as it
  /// was, since a modem that passes no cleanup report up says nothing about each responder.
  ///
  /// ```swift
  /// let result = try await network.run(ModemScene(group: group), turningOn: true)
  ///
  /// print(result.acknowledged.count, "acknowledged,", result.isComplete ? "complete" : "incomplete")
  /// ```
  ///
  /// - Parameters:
  ///   - scene: The scene.
  ///   - isOn: Whether to turn the scene's responders on, or off.
  ///   - wait: How long to wait for the modem's echo and its cleanups.
  /// - Returns: Which responders acknowledged their cleanup, which didn't, and whether the modem
  ///   reached them all.
  /// - Throws: `ModemError.rejected` if the modem rejects the command, as it does for a group it
  ///   has no records for, the modem's other errors, or `CancellationError` if the task is
  ///   canceled.
  public func run(_ scene: ModemScene, turningOn isOn: Bool, wait: AllLinkCleanupWait = .standard) async throws -> SceneResult {

    let records: [AllLinkRecord] = try await cache.modemRecords()
    let responders: [InsteonAddress] = scene.responders(among: records)

    var result: SceneResult = SceneResult(try await scene.send(turningOn: isOn, through: modem, wait: wait))

    result.responderCount = responders.count

    return result

  }

}
