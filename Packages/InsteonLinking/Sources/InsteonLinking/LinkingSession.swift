import InsteonModem
import InsteonProtocol

/// Puts the modem and a device into linking or unlinking mode, and waits for the link the
/// modem reports.
struct LinkingSession: Sendable {

  let modem: any LinkingModem

  /// How long to wait for each request to a device.
  let timeout: Duration

  let clock: any Clock<Duration>

  /// The engine a device runs, which decides whether and how it can be linked remotely.
  ///
  /// An i2cs device rejects requests from a modem it isn't linked to, so a device that rejects
  /// the request as not linked runs i2cs. A device that reports an engine this package doesn't
  /// know is treated as i2cs too, whose extended messages earlier engines also accept.
  func engine(of device: InsteonAddress) async throws -> InsteonEngine {

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

  /// Sends a device Enter Linking Mode or Enter Unlinking Mode in the form its engine expects:
  /// standard for i2, and extended with a checksum for i2cs. i1 devices can't be put into
  /// either mode remotely.
  func send(_ command: StandardDirectCommand, to device: InsteonAddress, engine: InsteonEngine) async throws {

    switch engine {
    case .i1:
      throw LinkingError.remoteLinkingUnsupported(device)
    case .i2:
      _ = try await modem.request(StandardMessage(to: device, command: command), timeout: timeout)
    case .i2cs:
      _ = try await modem.request(ExtendedMessage(to: device, command: command), timeout: timeout)
    }

  }

  /// Runs `start`, which puts the modem and the device into linking or unlinking mode, then
  /// waits for the modem to report the link.
  ///
  /// When the wait fails, the modem is taken out of linking mode. A canceled wait can't send
  /// the modem anything, so the modem leaves linking mode on its own after 4 minutes.
  ///
  /// - Parameters:
  ///   - device: The device whose link to wait for, or `nil` for the first device that links.
  ///   - linkingTimeout: How long to wait for the link.
  ///   - start: Puts the modem and the device into linking or unlinking mode.
  func awaitLink(
    with device: InsteonAddress?,
    within linkingTimeout: Duration,
    starting start: () async throws -> Void
  ) async throws -> AllLinkingCompleted {

    // Listening starts before the modem enters linking mode, so the report can't be missed.
    let replies = await modem.replies()

    do {

      try await start()

      return try await firstLink(in: replies, with: device, within: linkingTimeout)

    } catch {

      if !(error is CancellationError) {

        _ = try? await modem.send(.cancelAllLinking)

      }

      throw error

    }

  }

  private func firstLink(
    in replies: AsyncStream<ModemReply>,
    with device: InsteonAddress?,
    within linkingTimeout: Duration
  ) async throws -> AllLinkingCompleted {

    let clock = clock

    return try await withThrowingTaskGroup(of: AllLinkingCompleted?.self) { group in

      group.addTask {

        for await reply in replies {

          if case let .allLinkingCompleted(link) = reply, device == nil || link.address == device {

            return link

          }

        }

        // The stream ends without a link only when the modem closes, or this task is canceled
        // because the timeout came first.
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
