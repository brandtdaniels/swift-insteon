import InsteonProtocol

/// One of the links between the modem and a device: the modem's role in it and the group.
///
/// The modem keeps one record for each: a controller record for a link in one of the modem's
/// groups, which the device responds to, and a responder record for a link in one of the
/// device's groups, which the device controls.
public struct ModemLink: Hashable, Sendable {

  /// Whether the modem controls the device or responds to it.
  public var modemRole: ModemRole

  /// The group: the modem's when it's the controller, the device's when it's the responder.
  public var group: AllLinkGroupNumber

  /// Creates a link.
  ///
  /// - Parameters:
  ///   - modemRole: Whether the modem controls the device or responds to it.
  ///   - group: The controller's group.
  public init(modemRole: ModemRole, group: AllLinkGroupNumber) {

    self.modemRole = modemRole
    self.group = group

  }

  /// The links a device's records in the modem's database describe, each once.
  ///
  /// The links the device controls come first, in the modem's order, then those the modem
  /// controls, so a device is unlinked as a controller before it's taken out of the modem's
  /// groups.
  ///
  /// - Parameter records: The modem's records for one device, such as
  ///   ``AllLinkDatabaseCache/modemLinks(of:)`` returns.
  /// - Returns: The links, without duplicates.
  public static func links(in records: [AllLinkRecord]) -> [ModemLink] {

    var responderLinks: [ModemLink] = []
    var controllerLinks: [ModemLink] = []

    for record in records where record.flags.contains(.inUse) {

      if record.flags.contains(.controller) {

        let link = ModemLink(modemRole: .controller, group: record.group)

        if !controllerLinks.contains(link) {

          controllerLinks.append(link)

        }

      } else {

        let link = ModemLink(modemRole: .responder, group: record.group)

        if !responderLinks.contains(link) {

          responderLinks.append(link)

        }

      }

    }

    return responderLinks + controllerLinks

  }

}

/// How a device is sent Enter Unlinking Mode when the modem responds in the link being
/// removed.
public enum UnlinkingModeMessage: Hashable, Sendable {

  /// A standard message, whatever the device's engine, as most devices take it.
  case standard

  /// An extended message with a checksum for an i2CS device, as battery-powered i2CS devices
  /// take it, and a standard message otherwise.
  case extendedForI2cs

}

extension Unlinker {

  /// The device group sent with Enter Linking Mode when a device leaves one of the modem's
  /// groups: group 1, a single-group device's only group and a multi-group device's first.
  static let respondingDeviceGroup: AllLinkGroupNumber = 0x01

  /// Removes every link between the modem and a device, in both directions, without anyone
  /// pressing its SET button.
  ///
  /// The modem's database says which links there are, as ``ModemLink/links(in:)`` reads it.
  /// Each is removed in turn, the links the device controls first:
  ///
  /// - **The device controls the modem.** The device is asked for its engine and sent Enter
  ///   Unlinking Mode for its group, then the modem starts ALL-Linking as the responder and
  ///   waits for the device's report. A modem that removes a responder record may not report
  ///   it, so when no report arrives, the link counts as removed if the modem's record is gone.
  /// - **The modem controls the device.** The modem starts ALL-Linking in unlinking mode for
  ///   its group, then the device is asked for its engine and sent Enter Linking Mode for
  ///   group 1, extended for i2CS, and the modem's report is awaited.
  ///
  /// Nothing is written to either database directly. Links removed before one fails stay
  /// removed; read the modem's links again to see which are left. i1 devices can't be unlinked
  /// remotely; use ``Unlinker/unlinkManually(as:group:device:timeout:ready:)``.
  ///
  /// ```swift
  /// let removed = try await Unlinker(modem: modem).unlinkAllRemotely(lamp) { link in
  ///   print("Removing group \(link.group)...")
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - device: The device to unlink.
  ///   - unlinkingMode: How the device is sent Enter Unlinking Mode. Defaults to
  ///     ``UnlinkingModeMessage/standard``; pass ``UnlinkingModeMessage/extendedForI2cs``
  ///     for a battery-powered i2CS device.
  ///   - linkingTimeout: How long to wait for the modem to report each link removed.
  ///     Defaults to `Linker.defaultRemoteLinkingTimeout`.
  ///   - willUnlink: Called before each link is removed.
  /// - Returns: The links removed, in order, or an empty array if the modem had none with the
  ///   device.
  /// - Throws: ``LinkingError/remoteLinkingUnsupported(_:)`` for an i1 device,
  ///   ``LinkingError/linkingTimedOut`` if a link isn't removed in time,
  ///   ``LinkingError/unexpectedLink(_:)`` if the modem reports a different link, or the
  ///   modem's errors. When a link fails, the modem and the device are taken out of their
  ///   modes.
  @discardableResult
  public func unlinkAllRemotely(
    _ device: InsteonAddress,
    unlinkingMode: UnlinkingModeMessage = .standard,
    timeout linkingTimeout: Duration = Linker.defaultRemoteLinkingTimeout,
    willUnlink: @escaping @Sendable (ModemLink) async -> Void = { _ in }
  ) async throws -> [ModemLink] {

    let records: [AllLinkRecord]

    if let databaseCache: AllLinkDatabaseCache = cache {

      records = try await databaseCache.modemLinks(of: device)

    } else {

      let all: [AllLinkRecord] = try await modem.allLinkRecords()

      records = all.filter { (record: AllLinkRecord) -> Bool in record.address == device }

    }

    let links: [ModemLink] = ModemLink.links(in: records)
    var removed: [ModemLink] = []

    for link in links {

      await willUnlink(link)

      try await unlinkRemotely(device, link: link, unlinkingMode: unlinkingMode, within: linkingTimeout)

      removed.append(link)

    }

    return removed

  }

  /// Removes one link between the modem and a device without its SET button.
  private func unlinkRemotely(
    _ device: InsteonAddress,
    link: ModemLink,
    unlinkingMode: UnlinkingModeMessage,
    within linkingTimeout: Duration
  ) async throws {

    let session = LinkingSession(modem: modem, timeout: timeout, clock: clock, cache: cache)

    switch link.modemRole {
    case .controller:
      _ = try await session.remote(
        device,
        deviceCommand: .enterLinkingMode(group: Self.respondingDeviceGroup),
        modemMode: .delete,
        modemGroup: link.group,
        deviceFirst: false,
        expecting: .delete,
        within: linkingTimeout
      )
    case .responder:
      do {

        _ = try await session.remote(
          device,
          deviceCommand: .enterUnlinkingMode(group: link.group),
          modemMode: .responder,
          modemGroup: link.group,
          deviceFirst: true,
          expecting: .delete,
          within: linkingTimeout,
          extendsForI2cs: unlinkingMode == .extendedForI2cs
        )

      } catch LinkingError.linkingTimedOut {

        // A modem that removes a responder record may not report it.
        let left: [AllLinkRecord] = try await modem.allLinkRecords(group: link.group, device: device)

        guard left.contains(where: { (record: AllLinkRecord) -> Bool in !record.flags.contains(.controller) }) else {

          return

        }

        throw LinkingError.linkingTimedOut

      }
    }

  }

}
