import InsteonProtocol

/// The state a device is put in before it links as a responder.
///
/// A responder that links with its SET button, or remotely with Enter Linking Mode, memorizes
/// its current state as the link's data: a light's level becomes Data 1 of its responder
/// record, its on-level for the group. A device linked while it's off records an on-level of
/// `0x00`, so the controller's On then leaves it off. Turning it on first records `0xFF`.
public enum ResponderState: Hashable, Sendable {

  /// On, at a level from `0x01` to `0xFF`, sent with Light On. A level of `0x00` is off, sent
  /// with Light Off, as ``ResponderState/off`` is.
  case on(level: UInt8)

  /// Off, sent with Light Off.
  case off

  /// Fully on: Light On at `0xFF`. On/off devices treat any level as on.
  public static let fullyOn: ResponderState = .on(level: 0xFF)

}

extension Linker {

  /// Puts a device into the state it should memorize before it links as a responder.
  ///
  /// Call this before a link in which the device responds, such as
  /// ``Linker/linkRemotely(_:modemRole:modemGroup:deviceGroup:timeout:)`` with the modem as
  /// the controller, or a manual link the device joins with its SET button. The device is
  /// sent Light On or Light Off as a standard message, which every engine accepts.
  ///
  /// An i2CS device rejects requests from a modem it isn't linked to, so a device that isn't
  /// linked yet throws `ModemError.deviceRejected`; it then links with whatever state it's in.
  ///
  /// ```swift
  /// let linker = Linker(modem: modem)
  ///
  /// try await linker.prepareResponder(lamp)
  /// try await linker.linkRemotely(lamp, modemRole: .controller, modemGroup: 0, deviceGroup: 1)
  /// ```
  ///
  /// - Parameters:
  ///   - device: The device that will respond.
  ///   - state: Its state. Defaults to ``ResponderState/fullyOn``.
  /// - Throws: The modem's errors, such as `ModemError.deviceRejected`.
  public func prepareResponder(_ device: InsteonAddress, state: ResponderState = .fullyOn) async throws {

    let command: StandardDirectCommand

    switch state {
    case .on(level: 0x00), .off:
      command = .off
    case let .on(level):
      command = .on(level: level)
    }

    _ = try await modem.request(StandardMessage(to: device, command: command), timeout: timeout)

  }

}
