import InsteonModem
import InsteonProtocol

/// Links an ALL-Link group's controller to its responders.
///
/// The linker writes each link's two records directly into the ALL-Link databases of the
/// controller and the responder: a controller record in the controller, and a responder record
/// holding the responder's link data in the responder. Writing the records sets each
/// responder's link data exactly, where linking with the SET button records whatever state the
/// responder is in at the time.
///
/// Devices with an i2 or i2CS engine accept database writes. An i2CS device accepts them only
/// from a modem it's already linked to, and rejects them with `NAKReason.notLinked`
/// otherwise. i1 devices don't have database writes.
///
/// ```swift
/// let linker = Linker(modem: modem)
///
/// try await linker.link(AllLinkGroup(
///   controller: .modem,
///   number: 0x05,
///   responders: [.init(.device(lamp), data1: 0xFF, data2: 0x1F, data3: 0x01)]
/// ))
/// ```
public struct Linker: Sendable {

  /// The modem the links are made through.
  public let modem: any LinkingModem

  /// How long to wait for each request to a device.
  public let timeout: Duration

  /// The clock that times the wait for a link.
  public let clock: any Clock<Duration>

  /// The cache databases are read through and kept in, if any.
  public let cache: AllLinkDatabaseCache?

  /// Creates a linker.
  ///
  /// - Parameters:
  ///   - modem: The modem the links are made through.
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

  /// Links a group's controller to each of its responders by writing their records.
  ///
  /// A responder record that already links the same devices in the same group is updated with
  /// the group's link data, so linking a group again changes its responders' data in place. A
  /// controller record that's already there stays as it is, since its data belongs to the
  /// controller; a new one has all-zero data. Links are made one responder at a time, each
  /// responder's record before the controller's, and those already made stay made if a later
  /// one fails.
  ///
  /// - Parameter group: The group to link.
  /// - Throws: ``LinkingError`` if a device's database is full or a record doesn't read back
  ///   as written, or the modem's errors, such as `ModemError.deviceRejected` from an i2CS
  ///   device that isn't linked to the modem.
  public func link(_ group: AllLinkGroup) async throws {

    var editor = DatabaseEditor(modem: modem, timeout: timeout, cache: cache)
    let addresses = try await editor.addresses(for: group)
    let controller = addresses.address(of: group.controller)

    for responder in group.responders {

      // The responder's record goes first, so a responder that rejects it, such as an i2CS
      // device that isn't linked to the modem, doesn't leave the controller with a link to it.
      try await editor.write(
        AllLinkRecord(
          flags: DatabaseEditor.flags(isController: false),
          group: group.number,
          address: controller,
          data1: responder.data1,
          data2: responder.data2,
          data3: responder.data3
        ),
        into: responder.endpoint
      )

      try await editor.write(
        AllLinkRecord(
          flags: DatabaseEditor.flags(isController: true),
          group: group.number,
          address: addresses.address(of: responder.endpoint)
        ),
        into: group.controller
      )

    }

  }

  // MARK: - Remote and manual linking

  /// How long ``Linker/linkRemotely(_:modemRole:modemGroup:deviceGroup:timeout:)`` waits for
  /// the modem to report the link by default: 30 seconds.
  public static let defaultRemoteLinkingTimeout: Duration = .seconds(30)

  /// How long ``Linker/linkManually(modemRole:group:timeout:)`` waits for someone to press a
  /// device's SET button by default: 4 minutes, the time the modem stays in linking mode.
  public static let defaultManualLinkingTimeout: Duration = .seconds(240)

  /// Links a device to the modem without anyone pressing its SET button.
  ///
  /// The linker asks the device for its engine, then puts the modem and the device into
  /// linking mode, as their SET buttons would, and waits for the modem to report the link.
  /// When the modem is the controller, the modem goes first and the device joins its group as
  /// a responder; when the modem is the responder, the device goes first as the controller of
  /// its group. The device memorizes its current state as its link data, so a dimmable device
  /// should be fully on the first time it links, as the Insteon Developer's Guide advises:
  /// call ``Linker/prepareResponder(_:state:)`` first when the device is the responder.
  ///
  /// Devices with an i2 engine are sent the standard Enter Linking Mode, and i2CS devices the
  /// extended one with a checksum. i1 devices can't be linked remotely; use
  /// ``Linker/linkManually(modemRole:group:timeout:)``.
  ///
  /// - Parameters:
  ///   - device: The device to link.
  ///   - modemRole: Whether the modem controls the device or responds to it.
  ///   - modemGroup: The modem's group: the group the device joins, or the group the modem
  ///     joins it in.
  ///   - deviceGroup: The device's group or button. Devices with only one group ignore it.
  ///   - linkingTimeout: How long to wait for the modem to report the link. Defaults to
  ///     ``Linker/defaultRemoteLinkingTimeout``.
  /// - Returns: The link the modem reports.
  /// - Throws: ``LinkingError/remoteLinkingUnsupported(_:)`` for an i1 device,
  ///   ``LinkingError/linkingTimedOut`` if the modem doesn't report the link in time,
  ///   ``LinkingError/unexpectedLink(_:)`` if it reports a different link, or the modem's
  ///   errors. When the link fails, the modem and the device are taken out of linking mode.
  @discardableResult
  public func linkRemotely(
    _ device: InsteonAddress,
    modemRole: ModemRole,
    modemGroup: AllLinkGroupNumber,
    deviceGroup: AllLinkGroupNumber,
    timeout linkingTimeout: Duration = Linker.defaultRemoteLinkingTimeout
  ) async throws -> AllLinkingCompleted {

    try await LinkingSession(modem: modem, timeout: timeout, clock: clock, cache: cache).remote(
      device,
      deviceCommand: .enterLinkingMode(group: deviceGroup),
      modemMode: modemRole.linkingMode,
      modemGroup: modemGroup,
      // The controller enters linking mode first and the responder joins it.
      deviceFirst: modemRole == .responder,
      expecting: modemRole.linkingMode,
      within: linkingTimeout
    )

  }

  /// Puts the modem into linking mode and waits for someone to press a device's SET button.
  ///
  /// This works with devices of every engine, and is how an i1 device is linked. When the
  /// modem is the responder, put the device into linking mode with its SET button first, so
  /// it's waiting as the controller when the modem joins. To tell a person when to press the
  /// SET button, to let the device choose the modem's role, or to accept only one device's
  /// link, use ``Linker/linkManually(as:group:device:timeout:ready:)``.
  ///
  /// - Parameters:
  ///   - modemRole: Whether the modem controls the device or responds to it.
  ///   - group: The modem's group.
  ///   - linkingTimeout: How long to wait. Defaults to ``Linker/defaultManualLinkingTimeout``.
  /// - Returns: The link the modem reports, including the device's address.
  /// - Throws: ``LinkingError/linkingTimedOut`` if no device links in time,
  ///   ``LinkingError/unexpectedLink(_:)`` if the modem reports a different kind of link, or
  ///   the modem's errors. When the link fails, the modem is taken out of linking mode.
  @discardableResult
  public func linkManually(
    modemRole: ModemRole,
    group: AllLinkGroupNumber,
    timeout linkingTimeout: Duration = Linker.defaultManualLinkingTimeout
  ) async throws -> AllLinkingCompleted {

    try await LinkingSession(modem: modem, timeout: timeout, clock: clock, cache: cache).manual(
      modemMode: modemRole.linkingMode,
      group: group,
      expecting: modemRole.linkingMode,
      within: linkingTimeout
    )

  }

}
