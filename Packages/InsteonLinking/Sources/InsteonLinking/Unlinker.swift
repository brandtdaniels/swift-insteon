import InsteonModem
import InsteonProtocol

/// Removes the links between an ALL-Link group's controller and its responders.
///
/// The unlinker deletes each link's two records from the ALL-Link databases of the controller
/// and the responder, the reverse of ``Linker``. A device's record is deleted by clearing its
/// in-use bit, as the Insteon Developer's Guide describes, so the space is reused by the next link.
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

  /// The cache databases are read through and kept in, if any.
  public let cache: AllLinkDatabaseCache?

  /// Creates an unlinker.
  ///
  /// - Parameters:
  ///   - modem: The modem the links were made through.
  ///   - timeout: How long to wait for each request to a device. Defaults to
  ///     `Modem.defaultExtendedRequestTimeout`, since most of the requests are extended.
  ///   - clock: The clock that times the wait for a link. Defaults to a `ContinuousClock`;
  ///     tests can pass a clock they control.
  ///   - cache: A cache to read databases through and keep what's written in, so a database
  ///     is read again only when it has changed. Defaults to `nil`, which reads each database
  ///     once per call.
  public init(
    modem: any LinkingModem,
    timeout: Duration = Modem.defaultExtendedRequestTimeout,
    clock: any Clock<Duration> = ContinuousClock(),
    cache: AllLinkDatabaseCache? = nil
  ) {

    self.modem = modem
    self.timeout = timeout
    self.clock = clock
    self.cache = cache

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

    var editor = DatabaseEditor(modem: modem, timeout: timeout, cache: cache)
    let addresses = try await editor.addresses(for: group)
    let controller = addresses.address(of: group.controller)

    for responder in group.responders {

      // The controller's record goes first, so the controller stops cleaning up with a
      // responder that doesn't answer to the group.
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
  /// their SET buttons, and each removes its record of the link. When the modem is the
  /// controller, the modem enters unlinking mode and the device follows as the responder.
  /// When the modem is the responder, the device enters unlinking mode first and the modem
  /// follows.
  ///
  /// The modem reports the removed link. A modem that removes a responder record may not
  /// report it, so in that role the modem's own database is checked for the record before and,
  /// when no report arrives, after: the unlink succeeds if the record was there and is gone.
  /// i1 devices can't be unlinked remotely; use
  /// ``Unlinker/unlinkManually(modemRole:group:timeout:)``. To remove every link between the
  /// modem and a device, in both directions, use
  /// ``Unlinker/unlinkAllRemotely(_:unlinkingMode:timeout:willUnlink:)``.
  ///
  /// - Parameters:
  ///   - device: The device to unlink.
  ///   - modemRole: Whether the modem controls the device or responds to it.
  ///   - modemGroup: The modem's group in the link.
  ///   - deviceGroup: The device's group or button. Devices with only one group ignore it.
  ///   - linkingTimeout: How long to wait for the modem to report the link removed. Defaults to
  ///     `Linker.defaultRemoteLinkingTimeout`.
  /// - Throws: ``LinkingError/remoteLinkingUnsupported(_:)`` for an i1 device,
  ///   ``LinkingError/linkingTimedOut`` if the link isn't removed in time,
  ///   ``LinkingError/unexpectedLink(_:)`` if the modem reports a different link, or the
  ///   modem's errors. When the unlink fails, the modem and the device are taken out of their
  ///   modes.
  public func unlinkRemotely(
    _ device: InsteonAddress,
    modemRole: ModemRole,
    modemGroup: AllLinkGroupNumber,
    deviceGroup: AllLinkGroupNumber,
    timeout linkingTimeout: Duration = Linker.defaultRemoteLinkingTimeout
  ) async throws {

    let session = LinkingSession(modem: modem, timeout: timeout, clock: clock, cache: cache)
    let hadResponderRecord = if modemRole == .responder { try await hasResponderRecord(of: device, in: deviceGroup) } else { false }

    do {

      _ = try await session.remote(
        device,
        deviceCommand: modemRole == .controller ? .enterLinkingMode(group: deviceGroup) : .enterUnlinkingMode(group: deviceGroup),
        modemMode: modemRole.unlinkingMode,
        modemGroup: modemGroup,
        // The controller enters unlinking mode first and the responder joins it.
        deviceFirst: modemRole == .responder,
        expecting: .delete,
        within: linkingTimeout
      )

    } catch LinkingError.linkingTimedOut where hadResponderRecord {

      guard try await hasResponderRecord(of: device, in: deviceGroup) else {

        return

      }

      throw LinkingError.linkingTimedOut

    }

  }

  /// Whether the modem has a responder record of `device`, which is kept in the device's group.
  func hasResponderRecord(of device: InsteonAddress, in group: AllLinkGroupNumber) async throws -> Bool {

    try await modem.allLinkRecords(group: group, device: device).contains { !$0.flags.contains(.controller) }

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
  ///   - linkingTimeout: How long to wait. Defaults to `Linker.defaultManualLinkingTimeout`.
  /// - Returns: The removed link the modem reports, including the device's address.
  /// - Throws: ``LinkingError/linkingTimedOut`` if no device unlinks in time,
  ///   ``LinkingError/unexpectedLink(_:)`` if the modem reports a new link instead, or the
  ///   modem's errors. When the unlink fails, the modem is taken out of its mode.
  @discardableResult
  public func unlinkManually(
    modemRole: ModemRole,
    group: AllLinkGroupNumber,
    timeout linkingTimeout: Duration = Linker.defaultManualLinkingTimeout
  ) async throws -> AllLinkingCompleted {

    try await LinkingSession(modem: modem, timeout: timeout, clock: clock, cache: cache).manual(
      modemMode: modemRole.unlinkingMode,
      group: group,
      expecting: .delete,
      within: linkingTimeout
    )

  }

}
