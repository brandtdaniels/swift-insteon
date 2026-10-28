import InsteonModem
import InsteonProtocol

/// Puts the modem and a device into linking or unlinking mode, and waits for the link the
/// modem reports.
struct LinkingSession: Sendable {

  let modem: any LinkingModem

  /// How long to wait for each request to a device.
  let timeout: Duration

  let clock: any Clock<Duration>

  /// Links or unlinks a device without anyone pressing its SET button.
  ///
  /// The device is asked for its engine, then the modem and the device enter their modes in
  /// the given order, and the modem's report of the link is awaited. If the wait fails, the
  /// modem is taken out of linking mode and the device is sent Exit Linking Mode, so neither
  /// is left open to linking.
  ///
  /// - Parameters:
  ///   - device: The device to link or unlink.
  ///   - deviceCommand: Enter Linking Mode or Enter Unlinking Mode.
  ///   - modemMode: The modem's linking mode.
  ///   - modemGroup: The modem's group.
  ///   - deviceFirst: Whether the device enters its mode before the modem.
  ///   - expectedMode: The mode the modem reports for the link: its role, or `AllLinkMode.delete`.
  ///   - linkingTimeout: How long to wait for the modem's report.
  func remote(
    _ device: InsteonAddress,
    deviceCommand: StandardDirectCommand,
    modemMode: AllLinkMode,
    modemGroup: AllLinkGroupNumber,
    deviceFirst: Bool,
    expecting expectedMode: AllLinkMode,
    within linkingTimeout: Duration
  ) async throws -> AllLinkingCompleted {

    let engine = try await engine(of: device)

    // i1 devices don't accept Enter Linking Mode or Enter Unlinking Mode.
    guard let minimum = deviceCommand.minimumEngine, engine >= minimum else {

      throw LinkingError.remoteLinkingUnsupported(device)

    }

    let modem = modem
    let timeout = timeout

    return try await awaitLink(
      with: device,
      expecting: expectedMode,
      within: linkingTimeout,
      cleanUp: {

        // Exit Linking Mode is accepted as a standard message by every engine that has it.
        _ = try? await modem.request(StandardMessage(to: device, command: StandardDirectCommand.exitLinkingMode), timeout: timeout)

      },
      starting: {

        if deviceFirst {

          try await send(deviceCommand, to: device, engine: engine)
          try await modem.send(.startAllLinking(mode: modemMode, group: modemGroup))

        } else {

          try await modem.send(.startAllLinking(mode: modemMode, group: modemGroup))
          try await send(deviceCommand, to: device, engine: engine)

        }

      }
    )

  }

  /// Puts the modem into a linking mode and waits for whichever device a person links with
  /// its SET button.
  func manual(
    modemMode: AllLinkMode,
    group: AllLinkGroupNumber,
    expecting expectedMode: AllLinkMode,
    within linkingTimeout: Duration
  ) async throws -> AllLinkingCompleted {

    try await awaitLink(with: nil, expecting: expectedMode, within: linkingTimeout, cleanUp: {}) {

      try await modem.send(.startAllLinking(mode: modemMode, group: group))

    }

  }

  // MARK: - Engines

  /// The engine a device runs, which decides whether and how it can be linked remotely.
  ///
  /// An i2cs device rejects requests from a modem it isn't linked to, so a device that rejects
  /// the request as not linked runs i2cs. A device that reports an engine this package doesn't
  /// know is treated as i2cs too, whose extended messages earlier engines also accept.
  private func engine(of device: InsteonAddress) async throws -> InsteonEngine {

    do {

      let acknowledgement = try await modem.request(
        StandardMessage(to: device, command: StandardDirectCommand.getEngineVersion),
        timeout: timeout
      )

      return InsteonEngine(rawValue: acknowledgement.command.command2) ?? .i2cs

    } catch let ModemError.deviceRejected(address, reason) where address == device && reason == .notLinked {

      return .i2cs

    }

  }

  /// Sends a device a command in the form its engine expects: standard for i1 and i2, and
  /// extended with a checksum for i2cs, as Insteon's command sheet gives for Enter Linking
  /// Mode and Enter Unlinking Mode.
  private func send(_ command: StandardDirectCommand, to device: InsteonAddress, engine: InsteonEngine) async throws {

    if engine >= .i2cs {

      _ = try await modem.request(ExtendedMessage(to: device, command: command), timeout: timeout)

    } else {

      _ = try await modem.request(StandardMessage(to: device, command: command), timeout: timeout)

    }

  }

  // MARK: - Waiting

  /// Runs `start`, which puts the modem and the device into their modes, then waits for the
  /// modem to report the link.
  ///
  /// When the wait fails, the modem is taken out of linking mode and `cleanUp` runs. A
  /// canceled task can't send anything, so then a task of its own does both, rather than
  /// leaving the modem open to any device that's linked for 4 minutes.
  private func awaitLink(
    with device: InsteonAddress?,
    expecting expectedMode: AllLinkMode,
    within linkingTimeout: Duration,
    cleanUp: @escaping @Sendable () async -> Void,
    starting start: () async throws -> Void
  ) async throws -> AllLinkingCompleted {

    // Listening starts before the modem enters linking mode, so the report can't be missed.
    let replies = await modem.replies()

    do {

      try await start()

      return try await firstLink(in: replies, with: device, expecting: expectedMode, within: linkingTimeout)

    } catch {

      let modem = modem
      let restore: @Sendable () async -> Void = {

        _ = try? await modem.send(.cancelAllLinking)
        await cleanUp()

      }

      if error is CancellationError {

        Task { await restore() }

      } else {

        await restore()

      }

      throw error

    }

  }

  private func firstLink(
    in replies: AsyncStream<ModemReply>,
    with device: InsteonAddress?,
    expecting expectedMode: AllLinkMode,
    within linkingTimeout: Duration
  ) async throws -> AllLinkingCompleted {

    let clock = clock

    return try await withThrowingTaskGroup(of: AllLinkingCompleted?.self) { group in

      group.addTask {

        for await reply in replies {

          guard case let .allLinkingCompleted(link) = reply else {

            continue

          }

          // Another device linked while the modem was waiting, or the modem made a different
          // kind of link than asked, so the caller has to know.
          guard device == nil || link.address == device, link.mode == expectedMode else {

            throw LinkingError.unexpectedLink(link)

          }

          return link

        }

        // The stream ends early only when this task is canceled or the modem closes.
        try Task.checkCancellation()

        throw ModemError.connectionClosed

      }

      group.addTask {

        try await clock.sleep(for: linkingTimeout)

        return nil

      }

      defer { group.cancelAll() }

      guard let link = try await group.next() ?? nil else {

        throw LinkingError.linkingTimedOut

      }

      return link

    }

  }

}
