import InsteonModem
import InsteonProtocol

/// What a device says about itself: the engine it runs, whether it's linked to the modem, and
/// its category, subcategory and firmware version.
///
/// Together these identify the device's product and say how to talk to it: the identity finds
/// its profile in a device catalog, and the engine decides whether its extended messages need
/// a checksum.
public struct DeviceIdentification: Hashable, Sendable {

  /// The device.
  public var device: InsteonAddress

  /// The engine the device runs, or `nil` if it reported an engine this package doesn't know.
  public var engine: InsteonEngine?

  /// Whether the device accepts requests from the modem. An i2cs device rejects a modem it
  /// isn't linked to, and then can't be asked for its identity until it's linked.
  public var acceptsModem: Bool

  /// The SET Button Pressed broadcast the device sent in reply to an ID request, which carries
  /// its category, subcategory and firmware version, or `nil` if it didn't send one.
  public var identity: SetButtonPressed?

  /// Creates an identification.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - engine: The engine the device runs, if known.
  ///   - acceptsModem: Whether the device accepts requests from the modem.
  ///   - identity: The device's reply to an ID request, if any.
  public init(device: InsteonAddress, engine: InsteonEngine?, acceptsModem: Bool, identity: SetButtonPressed?) {

    self.device = device
    self.engine = engine
    self.acceptsModem = acceptsModem
    self.identity = identity

  }

}

/// Asks devices what they are and how to talk to them.
///
/// ``DeviceIdentifier/identify(_:)`` asks a device for its engine with
/// `StandardDirectCommand.getEngineVersion`, then for its category, subcategory and firmware
/// version with `StandardDirectCommand.idRequest`, which the device answers with a SET Button
/// Pressed broadcast. An i2cs device that isn't linked to the modem rejects both, so it's
/// identified as i2cs without an identity; linking it with
/// ``Linker/linkRemotely(_:modemRole:modemGroup:deviceGroup:timeout:)`` reports its category and subcategory in `AllLinkingCompleted`.
///
/// ```swift
/// let identification = try await DeviceIdentifier(modem: modem).identify(lamp)
///
/// if let identity = identification.identity,
///    let profile = catalog.profile(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion) {
///   print(profile.name, identification.engine ?? profile.engine(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion))
/// }
/// ```
public struct DeviceIdentifier: Sendable {

  /// The modem the devices are asked through.
  public let modem: any LinkingModem

  /// How long to wait for each acknowledgement, and for the broadcast that answers an ID
  /// request.
  public let timeout: Duration

  /// The clock that times the wait for the broadcast.
  public let clock: any Clock<Duration>

  /// Creates an identifier.
  ///
  /// - Parameters:
  ///   - modem: The modem the devices are asked through.
  ///   - timeout: How long to wait for each acknowledgement, and for the broadcast that
  ///     answers an ID request. Defaults to `Modem.defaultRequestTimeout`.
  ///   - clock: The clock that times the wait for the broadcast. Defaults to a
  ///     `ContinuousClock`; tests can pass a clock they control.
  public init(modem: any LinkingModem, timeout: Duration = Modem.defaultRequestTimeout, clock: any Clock<Duration> = ContinuousClock()) {

    self.modem = modem
    self.timeout = timeout
    self.clock = clock

  }

  /// Asks a device for its engine and identity.
  ///
  /// - Parameter device: The device to ask.
  /// - Returns: What the device said. Its ``DeviceIdentification/identity`` is `nil` if the
  ///   device rejected the modem as not linked, or didn't broadcast its identity in time.
  /// - Throws: `ModemError` if the device doesn't acknowledge a request, or rejects one for a
  ///   reason other than not being linked.
  public func identify(_ device: InsteonAddress) async throws -> DeviceIdentification {

    let engine: InsteonEngine?

    do {

      let acknowledgement = try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.getEngineVersion), timeout: timeout)

      engine = InsteonEngine(rawValue: acknowledgement.command.command2)

    } catch let ModemError.deviceRejected(address, reason) where address == device && reason == .notLinked {

      // Only an i2cs device rejects a modem it isn't linked to.
      return DeviceIdentification(device: device, engine: .i2cs, acceptsModem: false, identity: nil)

    }

    return DeviceIdentification(device: device, engine: engine, acceptsModem: true, identity: try await identity(of: device))

  }

  /// Sends an ID request and waits for the device's SET Button Pressed broadcast.
  private func identity(of device: InsteonAddress) async throws -> SetButtonPressed? {

    // Listening starts before the request, so the broadcast can't be missed.
    let replies = await modem.replies()

    _ = try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.idRequest), timeout: timeout)

    let clock = clock
    let timeout = timeout

    return try await withThrowingTaskGroup(of: SetButtonPressed?.self) { group in

      group.addTask {

        for await reply in replies {

          if case let .messageReceived(message) = reply, let identity = SetButtonPressed(message), identity.sender == device {

            return identity

          }

        }

        // The stream ends early only when this task is canceled or the modem closes.
        try Task.checkCancellation()

        throw ModemError.connectionClosed

      }

      group.addTask {

        try await clock.sleep(for: timeout)

        return nil

      }

      defer { group.cancelAll() }

      return try await group.next() ?? nil

    }

  }

}
