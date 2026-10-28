import InsteonModem
import InsteonProtocol

/// Removes the links between an ALL-Link group's controller and its responders.
///
/// The unlinker deletes each link's two records from the ALL-Link databases of the controller
/// and the responder, the reverse of ``Linker``. A device's record is deleted by clearing its
/// in-use bit, as the developer guide describes, so the space is reused by the next link.
///
/// ```swift
/// try await Unlinker(modem: modem).unlink(group)
/// ```
public struct Unlinker: Sendable {

  /// The modem the links were made through.
  public let modem: any LinkingModem

  /// How long to wait for each request to a device.
  public let timeout: Duration

  /// The clock that times the wait for a link.
  public let clock: any Clock<Duration>

  /// Creates an unlinker.
  ///
  /// - Parameters:
  ///   - modem: The modem the links were made through.
  ///   - timeout: How long to wait for each request to a device. Defaults to `Modem.defaultRequestTimeout`.
  ///   - clock: The clock that times the wait for a link. Defaults to a `ContinuousClock`;
  ///     tests can pass a clock they control.
  public init(
    modem: any LinkingModem,
    timeout: Duration = Modem.defaultRequestTimeout,
    clock: any Clock<Duration> = ContinuousClock()
  ) {

    self.modem = modem
    self.timeout = timeout
    self.clock = clock

  }

  /// Removes the links between a group's controller and each of its responders.
  ///
  /// Links that aren't there are skipped, so unlinking a group that's partly linked removes
  /// what's left. Only the records for the group's number and endpoints are deleted; the
  /// devices' other links stay. The responders' link data doesn't matter.
  ///
  /// - Parameter group: The group to unlink.
  /// - Throws: ``LinkingError`` if a deleted record doesn't read back as written, or the
  ///   modem's errors.
  public func unlink(_ group: AllLinkGroup) async throws {

    var editor = DatabaseEditor(modem: modem, timeout: timeout)
    let addresses = try await editor.addresses(for: group)
    let controller = addresses.address(of: group.controller)

    for responder in group.responders {

      // The controller's record goes first, so the controller stops cleaning up with a
      // responder that no longer answers to the group.
      try await editor.delete(
        group: group.number,
        address: addresses.address(of: responder.endpoint),
        isController: true,
        from: group.controller
      )

      try await editor.delete(
        group: group.number,
        address: controller,
        isController: false,
        from: responder.endpoint
      )

    }

  }

  // MARK: - Remote and manual unlinking

  /// Unlinks a device from the modem without anyone pressing its SET button.
  ///
  /// The controller goes into unlinking mode and the responder into linking mode, as with
  /// their SET buttons: when the modem is the controller, the modem enters unlinking mode and
  /// the device follows as the responder; when the modem is the responder, the device enters
  /// unlinking mode first and the modem follows. Each removes its record of the link, and the
  /// modem reports it. i1 devices can't be unlinked remotely; use
  /// ``Unlinker/unlinkManually(modemRole:group:timeout:)``.
  ///
  /// - Parameters:
  ///   - device: The device to unlink.
  ///   - modemRole: Whether the modem controls the device or responds to it.
  ///   - modemGroup: The modem's group in the link.
  ///   - deviceGroup: The device's group or button. Devices with only one group ignore it.
  ///   - timeout: How long to wait for the modem to report the link removed. Defaults to
  ///     `Linker.defaultRemoteLinkingTimeout`.
  /// - Returns: The removed link the modem reports.
  /// - Throws: ``LinkingError/remoteLinkingUnsupported(_:)`` for an i1 device,
  ///   ``LinkingError/linkingTimedOut`` if the modem doesn't report it in time, or the
  ///   modem's errors.
  @discardableResult
  public func unlinkRemotely(
    _ device: InsteonAddress,
    modemRole: ModemRole,
    modemGroup: AllLinkGroupNumber,
    deviceGroup: AllLinkGroupNumber,
    timeout linkingTimeout: Duration = Linker.defaultRemoteLinkingTimeout
  ) async throws -> AllLinkingCompleted {

    let session = LinkingSession(modem: modem, timeout: timeout, clock: clock)
    let engine = try await session.engine(of: device)

    guard engine >= .i2 else {

      throw LinkingError.remoteLinkingUnsupported(device)

    }

    return try await session.awaitLink(with: device, within: linkingTimeout) {

      switch modemRole {
      case .controller:
        try await modem.send(.startAllLinking(mode: .delete, group: modemGroup))
        try await session.send(.enterLinkingMode(group: deviceGroup), to: device, engine: engine)
      case .responder:
        try await session.send(.enterUnlinkingMode(group: deviceGroup), to: device, engine: engine)
        try await modem.send(.startAllLinking(mode: .responder, group: modemGroup))
      }

    }

  }

  /// Puts the modem into unlinking mode and waits for someone to press a device's SET button.
  ///
  /// When the modem is the controller, the modem enters unlinking mode and waits for the
  /// device's SET button. When the modem is the responder, put the device into unlinking mode
  /// with its SET button first; the modem then joins in linking mode as the responder.
  ///
  /// - Parameters:
  ///   - modemRole: Whether the modem controls the device or responds to it.
  ///   - group: The modem's group in the link.
  ///   - timeout: How long to wait. Defaults to `Linker.defaultManualLinkingTimeout`.
  /// - Returns: The removed link the modem reports, including the device's address.
  /// - Throws: ``LinkingError/linkingTimedOut`` if no device unlinks in time, or the modem's
  ///   errors.
  @discardableResult
  public func unlinkManually(
    modemRole: ModemRole,
    group: AllLinkGroupNumber,
    timeout linkingTimeout: Duration = Linker.defaultManualLinkingTimeout
  ) async throws -> AllLinkingCompleted {

    let session = LinkingSession(modem: modem, timeout: timeout, clock: clock)

    return try await session.awaitLink(with: nil, within: linkingTimeout) {

      let mode: AllLinkMode = modemRole == .controller ? .delete : .responder

      try await modem.send(.startAllLinking(mode: mode, group: group))

    }

  }

}
