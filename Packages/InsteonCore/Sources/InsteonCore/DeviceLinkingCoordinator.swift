import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// Links devices to a network's modem, unlinks them and removes them from the network, with
/// the Insteon device catalog deciding what each device needs, and a ``LinkingObserver`` for
/// what a person sees and does.
///
/// Get one from ``DeviceNetwork/linking``. Every coordinator of a network takes turns with the
/// others, so one link or unlink runs at a time, the modem is in one linking mode at a time,
/// and the network's cache of ALL-Link databases has one writer. After each link or unlink, the
/// network's ``DeviceNetwork/registry`` holds the identity the device reported, the copies of
/// the device's and the modem's ALL-Link databases are forgotten, since both changed, and the
/// modem's records are read again when the coordinator needs them, so the network's
/// ``DeviceNetwork/snapshot()`` holds them. A link or unlink that throws forgets them too: the
/// device's, and those of another device the modem reported instead, such as one whose SET
/// button was pressed by mistake.
///
/// The catalog decides:
///
/// - whether a device is turned fully on with Light On before it links as a responder, so it
///   records full on as its on-level: only a light or switched load the registry knows;
/// - the steps a person takes on the device when it's linked or unlinked with its SET button;
/// - whether a device is linked back after the modem links as its controller, by its address
///   or its SET button, and in which of its groups: group 1 when the catalog says the device
///   controls it, or else the first group the catalog lists that the device controls, so a
///   device whose group 1 only responds is linked back in a group the modem can hear;
/// - which of the device's groups the modem joins when it links by the device's address as
///   the responder: the same group a link back uses, rather than the modem's group, since
///   the device is the controller and the group is its own;
/// - the links made when a device is linked by its address, from its linking from a Hub:
///   its legs, in order, whether Enter Linking Mode works for it, and whether it goes first;
/// - how a device is sent Enter Unlinking Mode when its links are removed without its SET
///   button: extended for a battery-powered i2CS device;
/// - the steps to restore a removed device's factory settings, which a person follows.
///
/// Operating flags aren't read or written around a link or unlink: a device keeps whatever
/// flags linking leaves it with.
///
/// Canceling the task stops a link or unlink cleanly, as the linking primitives do: the modem
/// is sent Cancel ALL-Linking, and a device sent Enter Linking Mode is sent Exit Linking Mode.
///
/// ```swift
/// let result = try await network.linking.link(lamp, as: .controller, group: 0, observer: prompter)
///
/// for link in result.links {
///   print(link.address, link.group)
/// }
/// ```
public struct DeviceLinkingCoordinator: Sendable {

  /// The modem's group when none is given: group 0, as Insteon's own apps link devices.
  public static let defaultModemGroup: AllLinkGroupNumber = 0

  /// The device's group sent with Enter Linking Mode when it joins one of the modem's groups:
  /// group 1, a single-group device's only group and a multi-group device's first.
  public static let respondingDeviceGroup: AllLinkGroupNumber = 1

  /// The network whose devices are linked.
  public let network: DeviceNetwork

  /// Creates a coordinator for a network. ``DeviceNetwork/linking`` creates one too.
  ///
  /// - Parameter network: The network.
  public init(network: DeviceNetwork) {

    self.network = network

  }

  // MARK: - Linking

  /// Links whichever device's SET button a person presses.
  ///
  /// As the controller, or in either role, the modem enters linking mode first, then the
  /// observer is told to have the SET button pressed. As the responder, the observer is asked
  /// to have the device put into linking mode first, then the modem joins it. The device's
  /// identity comes from the link, or else from ID Request, and the registry records it.
  ///
  /// - Parameters:
  ///   - role: The modem's role, or `ManualLinkingRole.either` to let the device choose.
  ///   - group: The modem's group. Defaults to ``DeviceLinkingCoordinator/defaultModemGroup``.
  ///   - twoWay: Whether to link the device back when the modem is its controller. Defaults to
  ///     ``TwoWayLinking/whenDeviceControls``.
  ///   - timeout: How long the modem waits for the SET button. Defaults to
  ///     `Linker.defaultManualLinkingTimeout`.
  ///   - observer: What a person is told and asked.
  /// - Returns: The links made and the device.
  /// - Throws: `LinkingError.linkingTimedOut` if no device links in time, `LinkMismatch` if
  ///   the device unlinked instead, the observer's errors, the modem's errors, and
  ///   `CancellationError` if the task is canceled. A link back that fails doesn't throw; the
  ///   result says why.
  public func linkBySETButton(
    as role: ManualLinkingRole,
    group: AllLinkGroupNumber = DeviceLinkingCoordinator.defaultModemGroup,
    twoWay: TwoWayLinking = .whenDeviceControls,
    timeout: Duration = Linker.defaultManualLinkingTimeout,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    try await inTurn(changing: nil) { () async throws -> DeviceLinkingResult in

      let linker: Linker = makeLinker()
      let first: AllLinkingCompleted

      switch role {
      case .responder:
        try await observer.waitUntilDeviceIsReady(DeviceFirstPrompt(direction: .linking, device: nil, deviceDescription: nil, steps: []))
        await observer.linking(.modemJoining(timeout: timeout))

        first = try await linker.linkManually(as: .responder, group: group, timeout: timeout)
      case .controller, .either:
        let prompt = SETButtonPrompt(direction: .linking, group: group, timeout: timeout, device: nil, deviceDescription: nil, steps: [])

        first = try await linker.linkManually(as: role, group: group, timeout: timeout, ready: { () async -> Void in

          await observer.linking(.pressSETButton(prompt))

        })
      }

      return try await finishLink(first, twoWay: twoWay, observer: observer)

    }

  }

  /// Links a device by its address, without its SET button, or with it when that fails.
  ///
  /// A device the registry doesn't know is asked for its identity with ID Request first, as
  /// ``DeviceNetwork/identify(_:)`` does, so the catalog can describe it. When it doesn't
  /// report one, as an i2CS device that isn't linked to the modem doesn't, the observer gets
  /// ``LinkingEvent/notIdentifiedBeforeLinking(_:because:)`` and the device is linked as one
  /// the catalog doesn't describe.
  ///
  /// When the registry knows the device, the catalog gives its linking from a Hub, the caller
  /// asks for the defaults, the modem as controller in
  /// ``DeviceLinkingCoordinator/defaultModemGroup`` with ``TwoWayLinking/whenDeviceControls``,
  /// and `usesCatalogLegs` is `true`, the catalog's legs are linked instead, in the catalog's order, one ALL-Linking session
  /// each: the modem starts ALL-Linking first in the leg's role and group, the device joins
  /// with Enter Linking Mode for the leg's device group, or with its SET button when the
  /// catalog says Enter Linking Mode doesn't work for it, and the coordinator waits for
  /// ALL-Linking Completed (`0x53`) before the next leg. A device the catalog says goes first
  /// is put in linking mode by a person, with the catalog's steps, before the first leg. When
  /// Enter Linking Mode fails for the first leg, the device is linked with its SET button
  /// instead, and the observer is told whether the catalog expected Enter Linking Mode to work.
  /// A later leg that fails stops the legs after it without throwing; the result's
  /// ``DeviceLinkingResult/legs`` say what became of each.
  ///
  /// Otherwise the device is linked as follows.
  ///
  /// When the modem is the controller, a light or switched load the registry knows is turned
  /// fully on with Light On first, so it records full on as its on-level. The modem starts
  /// ALL-Linking in its role and the device is sent Enter Linking Mode, extended for i2CS. A
  /// device that doesn't link that way, such as an i2CS device that isn't linked to the modem
  /// yet, is linked with its SET button instead, with the catalog's steps, and only its link is
  /// accepted.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - role: The modem's role.
  ///   - group: The modem's group when it's the controller. As the responder, the modem joins
  ///     the device's group a link back uses instead: group 1 when the catalog says the device
  ///     controls it, or else the first group the catalog lists that it controls. Defaults to
  ///     ``DeviceLinkingCoordinator/defaultModemGroup``.
  ///   - twoWay: Whether to link the device back when the modem is its controller. Defaults to
  ///     ``TwoWayLinking/whenDeviceControls``.
  ///   - setButtonTimeout: How long the modem waits for the SET button when the device is
  ///     linked with it. Defaults to `Linker.defaultManualLinkingTimeout`.
  ///   - usesCatalogLegs: Whether the catalog's legs may be linked, when the other options are
  ///     the defaults. Pass `false` when a person asked for a role or group of their own, even
  ///     one equal to the default, such as the modem in either role or group 0 given
  ///     explicitly. Defaults to `true`.
  ///   - observer: What a person is told and asked.
  /// - Returns: The links made and the device.
  /// - Throws: `LinkMismatch` when the modem reports another device's link or a removed link,
  ///   `LinkingError.unexpectedLink(_:)` when it reports another kind of link,
  ///   `LinkingError.linkingTimedOut` if the device isn't linked in time, the observer's
  ///   errors, the modem's errors, and `CancellationError` if the task is canceled. A first
  ///   leg of the catalog's linking from a Hub that fails throws its error. A link back, or a
  ///   later leg, that fails doesn't throw; the result says why.
  public func link(
    _ device: InsteonAddress,
    as role: ModemRole,
    group: AllLinkGroupNumber = DeviceLinkingCoordinator.defaultModemGroup,
    twoWay: TwoWayLinking = .whenDeviceControls,
    setButtonTimeout: Duration = Linker.defaultManualLinkingTimeout,
    usesCatalogLegs: Bool = true,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    try await inTurn(changing: device) { () async throws -> DeviceLinkingResult in

      let linker: Linker = makeLinker()
      var description: DeviceDescription? = await network.registry.device(device)?.deviceDescription

      if description == nil {

        description = try await identifyBeforeLinking(device, observer: observer)

      }

      if usesCatalogLegs, role == .controller, group == Self.defaultModemGroup, twoWay == .whenDeviceControls, let legs = HubLinkingLeg.legs(of: description, device: device) {

        return try await linkByLegs(device, legs: legs, description: description, setButtonTimeout: setButtonTimeout, observer: observer)

      }

      let deviceGroup: AllLinkGroupNumber = role == .responder ? Self.controllingGroup(of: description) : Self.respondingDeviceGroup
      let modemGroup: AllLinkGroupNumber = role == .responder ? deviceGroup : group

      if role == .controller {

        try await turnOnBeforeLinking(device, description: description, linker: linker, observer: observer)

      }

      await observer.linking(.linkingRemotely(device, modemRole: role))

      var first: AllLinkingCompleted?

      do {

        first = try await linker.linkRemotely(device, modemRole: role, modemGroup: modemGroup, deviceGroup: deviceGroup)

      } catch let error as CancellationError {

        // The turn records the change on the way out.
        throw error

      } catch let LinkingError.unexpectedLink(link) {

        if let mismatch = LinkMismatch(link, direction: .linking, device: device) {

          throw mismatch

        }

        throw LinkingError.unexpectedLink(link)

      } catch {

        await observer.linking(.fallback(.setButtonLinking(device, reason: error)))

      }

      let made: AllLinkingCompleted

      if let first {

        made = first

      } else {

        let steps: [DeviceLifecycle.Step] = Self.deviceSteps(of: description?.profile?.lifecycle?.linking)

        if role == .responder {

          try await observer.waitUntilDeviceIsReady(DeviceFirstPrompt(direction: .linking, device: device, deviceDescription: description, steps: steps))
          await observer.linking(.modemJoining(timeout: setButtonTimeout))

          made = try await linker.linkManually(as: .responder, group: modemGroup, device: device, timeout: setButtonTimeout)

        } else {

          let prompt = SETButtonPrompt(
            direction: .linking,
            group: modemGroup,
            timeout: setButtonTimeout,
            device: device,
            deviceDescription: description,
            steps: steps
          )

          made = try await linker.linkManually(as: .controller, group: modemGroup, device: device, timeout: setButtonTimeout, ready: { () async -> Void in

            await observer.linking(.pressSETButton(prompt))

          })

        }

      }

      return try await finishLink(made, twoWay: twoWay, observer: observer)

    }

  }

  /// Asks a device the registry doesn't know for its identity before it's linked by its
  /// address, and tells the observer when it doesn't report one.
  ///
  /// - Returns: What the catalog says about the device, or `nil` if it didn't report an
  ///   identity.
  /// - Throws: `CancellationError` if the task is canceled while the device is asked.
  private func identifyBeforeLinking(_ device: InsteonAddress, observer: any LinkingObserver) async throws -> DeviceDescription? {

    await observer.linking(.identifying(device))

    let reason: UnidentifiedReason

    do {

      let identification: DeviceIdentification = try await network.identify(device)

      if let known = await network.registry.device(device) {

        return known.deviceDescription

      }

      reason = identification.acceptsModem ? .noIdentity : .notLinked

    } catch let error as CancellationError {

      throw error

    } catch {

      reason = .failed(error)

    }

    await observer.linking(.notIdentifiedBeforeLinking(device, because: reason))

    return nil

  }

  // MARK: - Unlinking

  /// Removes one link with a device's SET button.
  ///
  /// When the modem is the controller, it enters unlinking mode, then the observer is told to
  /// have the device's SET button pressed, as for linking. When the modem is the responder, the
  /// observer is asked to have the device put into unlinking mode first, with the catalog's
  /// steps, then the modem joins it. Afterward the modem's ALL-Link database is read again for
  /// the device's other links.
  ///
  /// - Parameters:
  ///   - device: The device whose unlink to accept, or `nil` for whichever device's SET button
  ///     is pressed.
  ///   - role: The modem's role in the link.
  ///   - group: The modem's group in the link, or `nil` for the group of the modem's records
  ///     for the device in its role, or ``DeviceLinkingCoordinator/defaultModemGroup`` when there's no device or it has
  ///     none.
  ///   - timeout: How long the modem waits for the SET button. Defaults to
  ///     `Linker.defaultManualLinkingTimeout`.
  ///   - observer: What a person is told and asked.
  /// - Returns: The removed link and the links left.
  /// - Throws: `LinkingError.linkingTimedOut` if no device unlinks in time, `LinkMismatch` if
  ///   another device unlinked or the device linked instead, the observer's errors, the
  ///   modem's errors, and `CancellationError` if the task is canceled.
  public func unlink(
    _ device: InsteonAddress?,
    as role: ModemRole,
    group: AllLinkGroupNumber? = nil,
    timeout: Duration = Linker.defaultManualLinkingTimeout,
    observer: any LinkingObserver
  ) async throws -> DeviceUnlinkingResult {

    try await inTurn(changing: device) { () async throws -> DeviceUnlinkingResult in

      var known: RegisteredDevice?

      if let device {

        known = await network.registry.device(device)

      }

      let description: DeviceDescription? = known?.deviceDescription
      let unlinker: Unlinker = makeUnlinker()
      let modemGroup: AllLinkGroupNumber = try await unlinkGroup(group, of: device, role: role, observer: observer)
      let link: AllLinkingCompleted

      if role == .responder {

        // The device is the controller, so it goes into unlinking mode first, then the modem
        // joins as its responder.
        let steps: [DeviceLifecycle.Step] = Self.deviceSteps(of: description?.profile?.lifecycle?.unlinking)

        try await observer.waitUntilDeviceIsReady(DeviceFirstPrompt(direction: .unlinking, device: device, deviceDescription: description, steps: steps))
        await observer.linking(.modemJoining(timeout: timeout))

        link = try await unlinker.unlinkManually(as: .responder, group: modemGroup, device: device, timeout: timeout)

      } else {

        // A responder leaves a controller's group the way it joins one, so the device's
        // linking steps apply.
        let prompt = SETButtonPrompt(
          direction: .unlinking,
          group: modemGroup,
          timeout: timeout,
          device: device,
          deviceDescription: description,
          steps: Self.deviceSteps(of: description?.profile?.lifecycle?.linking)
        )

        link = try await unlinker.unlinkManually(as: .controller, group: modemGroup, device: device, timeout: timeout, ready: { () async -> Void in

          await observer.linking(.pressSETButton(prompt))

        })

      }

      // A removed link carries no identity, so the device is named only if it was known.
      let removed = UnlinkedLink(link: link, device: await network.registry.device(link.address))

      await network.recordLinkChange(of: link.address, answered: true)
      await observer.linking(.unlinked(removed))

      let remaining: [ModemLink]? = try await remainingLinks(of: link.address, observer: observer)

      return DeviceUnlinkingResult(link: removed, remainingLinks: remaining)

    }

  }

  /// Removes every link between the modem and a device, in both directions, without its SET
  /// button, as `Unlinker.unlinkAllRemotely(_:unlinkingMode:timeout:willUnlink:)` does.
  ///
  /// The links the device controls go first, and the link in the modem's group 0 last. A
  /// battery-powered i2CS device is sent Enter Unlinking Mode extended. When a link can't be
  /// removed, the observer is told which links are left and how to remove them with the
  /// device's SET button, with the catalog's steps, and ``RemoteUnlinkingError`` is thrown.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - timeout: How long to wait for the modem to report each link removed. Defaults to
  ///     `Linker.defaultRemoteLinkingTimeout`.
  ///   - observer: What a person is told.
  /// - Returns: The links removed and the links left.
  /// - Throws: ``RemoteUnlinkingError`` when a link can't be removed, and `CancellationError` if
  ///   the task is canceled.
  public func unlinkAll(
    _ device: InsteonAddress,
    timeout: Duration = Linker.defaultRemoteLinkingTimeout,
    observer: any LinkingObserver
  ) async throws -> DeviceUnlinkingAllResult {

    try await inTurn(changing: device) { () async throws -> DeviceUnlinkingAllResult in

      let unlinked: RemovedAllLinks = try await removeAllLinks(of: device, timeout: timeout, reportsLinksLeft: true, observer: observer)

      return DeviceUnlinkingAllResult(removed: unlinked.removed, remainingLinks: unlinked.left.links)

    }

  }

  // MARK: - Removing

  /// Removes a device from the network: every link between it and the modem, then what the
  /// network knows about it, and gives the catalog's steps to restore its factory settings.
  ///
  /// The links are removed without the device's SET button, as
  /// ``DeviceLinkingCoordinator/unlinkAll(_:timeout:observer:)`` removes them: the links the
  /// device controls first, and the link in the modem's group 0 last. When a link can't be
  /// removed that way, the observer is told which links are left and how to remove them with
  /// the device's SET button, with the catalog's steps, and ``RemoteUnlinkingError`` is
  /// thrown; the device isn't forgotten then.
  ///
  /// A device that's gone, such as one thrown away or a battery-powered device whose batteries
  /// are dead, can't answer. Pass `forceModemSide` only once a person confirms that: when the
  /// links can't be removed through the device, or the modem still has links with it
  /// afterward, the modem's own records that name it are deleted directly with Manage
  /// ALL-Link Record instead, and the observer is told why. The links left aren't reported as
  /// ones to unlink then, and there are no SET button steps. The device's own records stay,
  /// so a device that comes back still holds them.
  ///
  /// The modem's ALL-Link database is then read again, and the device is forgotten only when
  /// it has no links with the device. Otherwise the device is kept: the observer gets
  /// ``LinkingEvent/kept(_:because:)``, and the result's
  /// ``DeviceRemovalResult/keptBecause`` says why, with no forgotten device, scan or reset
  /// steps. That's so when links are left, when the database can't be read again, or when the
  /// modem rejects deleting one of its records.
  ///
  /// A device forgotten is gone from the registry, from its state in the snapshot, such as its
  /// ALL-Link database copy, level and when it last answered, and from the snapshot's copy of
  /// the modem's ALL-Link database. Other devices may still hold records that name it, such as
  /// in a scene. With `scan`, the ALL-Link databases of the other devices the network knows
  /// are read, from the network's copies while they're current, and each record that names
  /// the device is reported; none is changed. Last, the observer is given the catalog's
  /// factory reset steps, for a person to follow. The device is never reset.
  ///
  /// ```swift
  /// let result = try await network.linking.remove(lamp, scan: true, observer: prompter)
  ///
  /// for holder in result.leftoverRecords?.holders ?? [] {
  ///   print(holder.address, holder.records.count)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - scan: Whether to look for records that name the device in other devices' ALL-Link
  ///     databases. Defaults to `false`.
  ///   - forceModemSide: Whether to delete the modem's records that name the device directly
  ///     when its links can't be removed through it, because a person confirmed it's gone.
  ///     Defaults to `false`.
  ///   - timeout: How long to wait for the modem to report each link removed. Defaults to
  ///     `Linker.defaultRemoteLinkingTimeout`.
  ///   - observer: What a person is told.
  /// - Returns: What was removed, and either the device forgotten, what other devices still
  ///   hold and the reset steps, or why the device was kept.
  /// - Throws: ``RemoteUnlinkingError`` when a link can't be removed through the device and
  ///   `forceModemSide` is `false`, and `CancellationError` if the task is canceled. A device whose database can't be read
  ///   during the scan doesn't throw; the scan lists it.
  public func remove(
    _ device: InsteonAddress,
    scan: Bool = false,
    forceModemSide: Bool = false,
    timeout: Duration = Linker.defaultRemoteLinkingTimeout,
    observer: any LinkingObserver
  ) async throws -> DeviceRemovalResult {

    try await inTurn(changing: device) { () async throws -> DeviceRemovalResult in

      let description: DeviceDescription? = await network.registry.device(device)?.deviceDescription
      let removed: RemovedLinks
      var left: ModemLinksLeft
      var remoteFailure: (any Error)?
      var deleted: [AllLinkRecord] = []
      var deletionFailure: (any Error)?

      do {

        // When the device may be gone, the links left aren't reported as ones to unlink, since
        // the modem's records are deleted next.
        let unlinked: RemovedAllLinks = try await removeAllLinks(
          of: device,
          timeout: timeout,
          reportsLinksLeft: !forceModemSide,
          observer: observer
        )

        removed = unlinked.removed
        left = unlinked.left

      } catch let failure as RemoteUnlinkingError where forceModemSide {

        remoteFailure = failure.underlying
        removed = RemovedLinks(address: device, device: await network.registry.device(device), links: [])
        left = .unreadable(failure.underlying)

      }

      if forceModemSide, remoteFailure != nil || left.links?.isEmpty != true {

        let reason: ModemRecordDeletionReason

        if let remoteFailure {

          reason = Self.deletionReason(for: remoteFailure)

        } else if let links = left.links {

          reason = .linksLeft(links)

        } else if case let .unreadable(error) = left {

          reason = .modemLinksUnreadable(error)

        } else {

          reason = .linksLeft([])

        }

        await observer.linking(.deletingModemRecords(device, reason: reason))

        do {

          deleted = try await makeUnlinker().deleteModemRecords(of: device)

        } catch let error as CancellationError {

          // The turn records the change on the way out.
          throw error

        } catch {

          deletionFailure = error

        }

        await network.recordLinkChange(of: device, answered: false)

        if deletionFailure == nil {

          await observer.linking(.modemRecordsDeleted(device, deleted.map { (record: AllLinkRecord) -> LinkRecord in LinkRecord(record) }))

        }

        left = try await modemLinksLeft(of: device)

      }

      let keptBecause: DeviceKeptReason? = Self.keptReason(left: left, deletionFailure: deletionFailure)

      if let keptBecause {

        await observer.linking(.kept(device, because: keptBecause))

        return DeviceRemovalResult(
          address: device,
          removed: removed,
          remainingLinks: left.links,
          remoteUnlinkingFailure: remoteFailure,
          deletedModemRecords: deleted.map { (record: AllLinkRecord) -> LinkRecord in LinkRecord(record) },
          forgotten: nil,
          keptBecause: keptBecause,
          leftoverRecords: nil,
          factoryReset: nil
        )

      }

      let forgotten = ForgottenDevice(address: device, device: await network.forget(device))

      await observer.linking(.forgotten(forgotten))

      var leftovers: LeftoverRecordScan?

      if scan {

        leftovers = try await leftoverRecords(naming: device, observer: observer)

      }

      let lifecycle: DeviceLifecycle? = description?.profile?.lifecycle
      let reset = FactoryResetSteps(
        address: device,
        deviceDescription: description,
        procedure: lifecycle?.reset,
        erases: lifecycle?.resetErases ?? []
      )

      await observer.linking(.factoryReset(reset))

      return DeviceRemovalResult(
        address: device,
        removed: removed,
        remainingLinks: left.links,
        remoteUnlinkingFailure: remoteFailure,
        deletedModemRecords: deleted.map { (record: AllLinkRecord) -> LinkRecord in LinkRecord(record) },
        forgotten: forgotten,
        keptBecause: nil,
        leftoverRecords: leftovers,
        factoryReset: reset
      )

    }

  }

  /// Why a device's links weren't removed through it, for the modem's records to be deleted
  /// instead.
  ///
  /// - Parameter error: Why removing a link through the device failed.
  /// - Returns: The reason.
  static func deletionReason(for error: any Error) -> ModemRecordDeletionReason {

    if let modemError = error as? ModemError, case .deviceTimedOut = modemError {

      return .noAnswer

    }

    if let linkingError = error as? LinkingError {

      switch linkingError {
      case .linkingTimedOut:
        return .noAnswer
      case .remoteLinkingUnsupported:
        return .remoteLinkingUnsupported
      default:
        break
      }

    }

    return .remoteUnlinkingFailed(error)

  }

  /// Why a device is kept rather than forgotten, or `nil` when the modem's database, read
  /// again, has no links with it.
  ///
  /// - Parameters:
  ///   - left: The modem's links with the device, read again.
  ///   - deletionFailure: Why deleting the modem's records failed, if it did.
  /// - Returns: The reason, or `nil` to forget the device.
  static func keptReason(left: ModemLinksLeft, deletionFailure: (any Error)?) -> DeviceKeptReason? {

    if let deletionFailure {

      return .modemRecordsNotDeleted(deletionFailure)

    }

    switch left {
    case let .links(links):
      return links.isEmpty ? nil : .linksRemain(links)
    case let .unreadable(error):
      return .modemLinksUnreadable(error)
    }

  }

  // MARK: - Catalog decisions

  /// The device's group that links back to the modem, and that the modem joins when it links
  /// by the device's address as the responder: group 1 when the catalog says the device
  /// controls it, or else the first group the catalog lists that it controls, or group 1 when
  /// the catalog names none.
  ///
  /// - Parameter description: What the catalog says about the device, if it's known.
  /// - Returns: The group.
  static func controllingGroup(of description: DeviceDescription?) -> AllLinkGroupNumber {

    let groups: [AllLinkGroupNumber] = description?.controllerGroups.map(\.number) ?? []

    if groups.isEmpty || groups.contains(respondingDeviceGroup) {

      return respondingDeviceGroup

    }

    return groups[0]

  }

  /// Whether the catalog says a device controls, as the product or in one of its groups, so
  /// the modem can respond to it. `false` when the catalog doesn't have the device.
  ///
  /// - Parameter description: What the catalog says about the device, if it's known.
  /// - Returns: Whether the device controls.
  static func controls(_ description: DeviceDescription?) -> Bool {

    guard let description else {

      return false

    }

    let productControls: Bool = description.profile?.role?.includesController ?? false

    return productControls || !description.controllerGroups.isEmpty

  }

  /// The steps of a procedure done on the device itself, leaving out those on the other device,
  /// such as the Hub.
  ///
  /// - Parameter procedure: The procedure, or `nil` when the catalog doesn't have it.
  /// - Returns: The steps, in order, or empty.
  static func deviceSteps(of procedure: DeviceLifecycle.Procedure?) -> [DeviceLifecycle.Step] {

    procedure?.steps.filter { (step: DeviceLifecycle.Step) -> Bool in !step.isOnOtherDevice } ?? []

  }

  // MARK: - Helpers

  /// Runs `body` in the network's turn for linking, so it runs alone.
  ///
  /// When `body` throws, the links it may have changed are recorded before the error is
  /// rethrown, so the network's copies of ALL-Link databases aren't stale: those of the device
  /// asked for, and those of the device of a link the modem reported in a `LinkMismatch` or
  /// `LinkingError.unexpectedLink(_:)`, which did take part.
  ///
  /// - Parameters:
  ///   - device: The device asked for, or `nil` for whichever device's SET button is pressed.
  ///   - body: The link or unlink.
  func inTurn<Value: Sendable>(changing device: InsteonAddress?, _ body: () async throws -> Value) async throws -> Value {

    let turns: LinkingTurns = network.linkingTurns

    try await turns.begin()

    do {

      let value: Value = try await body()

      await turns.end()

      return value

    } catch {

      if let reported = Self.reportedLink(in: error) {

        await network.recordLinkChange(of: reported.address, answered: true)

      }

      if let device {

        await network.recordLinkChange(of: device, answered: false)

      }

      await turns.end()

      throw error

    }

  }

  /// The link the modem reported that an error carries, from a `LinkMismatch` or
  /// `LinkingError.unexpectedLink(_:)`, or `nil` for any other error.
  ///
  /// - Parameter error: The error.
  /// - Returns: The link.
  static func reportedLink(in error: any Error) -> AllLinkingCompleted? {

    if let mismatch = error as? LinkMismatch {

      return mismatch.link

    }

    if let linkingError = error as? LinkingError, case let .unexpectedLink(link) = linkingError {

      return link

    }

    return nil

  }

  /// A linker that waits on the network's clock and keeps the network's cache.
  func makeLinker() -> Linker {

    Linker(modem: network.modem, clock: network.clock, cache: network.cache)

  }

  /// An unlinker that waits on the network's clock and keeps the network's cache.
  private func makeUnlinker() -> Unlinker {

    Unlinker(modem: network.modem, clock: network.clock, cache: network.cache)

  }

  /// Turns a light or switched load fully on before it links as a responder, so it records full
  /// on as its on-level for the group, rather than off. A device that doesn't turn on links in
  /// whatever state it's in.
  func turnOnBeforeLinking(
    _ device: InsteonAddress,
    description: DeviceDescription?,
    linker: Linker,
    observer: any LinkingObserver
  ) async throws {

    guard description?.setsOnLevelFromLoadWhenLinked == true else {

      await observer.linking(.notTurningOnBeforeLinking(device))

      return

    }

    await observer.linking(.turningOnBeforeLinking(device))

    do {

      try await linker.prepareResponder(device)
      await network.recordAnswer(of: device, level: 0xFF)

    } catch let error as CancellationError {

      throw error

    } catch {

      await observer.linking(.notTurnedOnBeforeLinking(device, reason: error))

    }

  }

  /// Records a link the modem reported and the identity of the device, tells the observer, and
  /// links the device back when it's to be.
  private func finishLink(_ first: AllLinkingCompleted, twoWay: TwoWayLinking, observer: any LinkingObserver) async throws -> DeviceLinkingResult {

    let device: InsteonAddress = first.address

    await network.recordLinkChange(of: device, answered: true)

    let registered: RegisteredDevice?

    do {

      registered = try await learnIdentity(from: first, observer: observer)

    } catch {

      // Something may have read the device's database again while it was identified, so the
      // link is recorded again before the error goes on.
      await network.recordLinkChange(of: device, answered: true)

      throw error

    }

    await observer.linking(.linked(LinkedDevice(link: first, device: registered, leg: .first)))

    let description: DeviceDescription? = registered?.deviceDescription
    let linksBack: Bool

    switch twoWay {
    case .always:
      linksBack = true
    case .whenDeviceControls:
      linksBack = Self.controls(description)
    case .never:
      linksBack = false
    }

    guard first.mode == .controller, linksBack else {

      return DeviceLinkingResult(links: [first], device: registered, linkBackFailure: nil)

    }

    let group: AllLinkGroupNumber = Self.controllingGroup(of: description)

    await observer.linking(.linkingBack(device, group: group))

    do {

      let back: AllLinkingCompleted = try await makeLinker().linkRemotely(device, modemRole: .responder, modemGroup: group, deviceGroup: group)

      await network.recordLinkChange(of: back.address, answered: true)
      await observer.linking(.linked(LinkedDevice(link: back, device: registered, leg: .linkBack)))

      return DeviceLinkingResult(links: [first, back], device: registered, linkBackFailure: nil)

    } catch let error as CancellationError {

      await network.recordLinkChange(of: device, answered: true)

      throw error

    } catch {

      await network.recordLinkChange(of: device, answered: true)

      return DeviceLinkingResult(links: [first], device: registered, linkBackFailure: error)

    }

  }

  /// The identity a link reported, or else, for a link made, the one the device reports to ID
  /// Request; the registry records either.
  ///
  /// - Returns: The device as the registry knows it, or `nil` if its identity isn't known and it
  ///   didn't report one.
  /// - Throws: `CancellationError` if the task is canceled while the device is asked.
  func learnIdentity(from link: AllLinkingCompleted, observer: any LinkingObserver) async throws -> RegisteredDevice? {

    let device: InsteonAddress = link.address

    if let identity = ReportedIdentity(link) {

      return await network.registry.record(identity, for: device)

    }

    if let known = await network.registry.device(device) {

      return known

    }

    guard link.mode != .delete else {

      return nil

    }

    await observer.linking(.identifying(device))

    do {

      _ = try await network.identify(device)

    } catch let error as CancellationError {

      throw error

    } catch {

      return nil

    }

    return await network.registry.device(device)

  }

  /// Removes every link between the modem and a device without its SET button, in the
  /// caller's turn, as ``DeviceLinkingCoordinator/unlinkAll(_:timeout:observer:)`` describes.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - timeout: How long to wait for the modem to report each link removed.
  ///   - reportsLinksLeft: Whether to tell the observer which links are left, and, when a link
  ///     can't be removed, how to remove them with the device's SET button.
  ///   - observer: What a person is told.
  /// - Returns: The links removed and the links left.
  /// - Throws: ``RemoteUnlinkingError`` when a link can't be removed, and `CancellationError`
  ///   if the task is canceled.
  private func removeAllLinks(
    of device: InsteonAddress,
    timeout: Duration,
    reportsLinksLeft: Bool,
    observer: any LinkingObserver
  ) async throws -> RemovedAllLinks {

    let known: RegisteredDevice? = await network.registry.device(device)
    let description: DeviceDescription? = known?.deviceDescription
    // Battery-powered i2CS devices take Enter Unlinking Mode extended.
    let isBatteryPowered: Bool = description?.profile?.isBatteryPowered ?? false
    let unlinkingMode: UnlinkingModeMessage = isBatteryPowered ? .extendedForI2cs : .standard

    await observer.linking(.readingModemLinks(device, purpose: .findingLinksToRemove))

    // The modem itself is asked which links there are, not an older copy.
    await network.cache.invalidateModem()

    let removed: [ModemLink]

    do {

      removed = try await makeUnlinker().unlinkAllRemotely(device, unlinkingMode: unlinkingMode, timeout: timeout) { (link: ModemLink) async -> Void in

        await observer.linking(.unlinkingRemotely(device, deviceDescription: description, link: link))

      }

    } catch let error as CancellationError {

      // The turn records the change on the way out.
      throw error

    } catch {

      await network.recordLinkChange(of: device, answered: false)

      if reportsLinksLeft {

        _ = try await remainingLinks(of: device, observer: observer)

        let steps: [DeviceLifecycle.Step] = Self.deviceSteps(of: description?.profile?.lifecycle?.unlinking)

        await observer.linking(.fallback(.setButtonUnlinking(device, deviceDescription: description, steps: steps)))

      }

      throw RemoteUnlinkingError(device: device, deviceDescription: description, underlying: error)

    }

    await network.recordLinkChange(of: device, answered: !removed.isEmpty)

    let removedLinks = RemovedLinks(address: device, device: known, links: removed)

    await observer.linking(.unlinkedAll(removedLinks))

    let left: ModemLinksLeft = try await modemLinksLeft(of: device)

    if reportsLinksLeft {

      await report(left, of: device, to: observer)

    }

    return RemovedAllLinks(removed: removedLinks, left: left)

  }

  /// Reads the ALL-Link databases of the other devices the network knows, and reports the
  /// records in use that name a removed device. Nothing is written.
  ///
  /// - Parameters:
  ///   - device: The removed device.
  ///   - observer: What a person is told.
  /// - Returns: The devices that hold records naming the device, and those whose databases
  ///   couldn't be read.
  /// - Throws: `CancellationError` if the task is canceled.
  private func leftoverRecords(naming device: InsteonAddress, observer: any LinkingObserver) async throws -> LeftoverRecordScan {

    let others: [InsteonAddress] = await network.knownDevices().filter { (address: InsteonAddress) -> Bool in address != device }
    var holders: [LeftoverRecords] = []
    var unread: [UnreadDatabase] = []

    for other in others {

      try Task.checkCancellation()

      let registered: RegisteredDevice? = await network.registry.device(other)

      await observer.linking(.scanningDatabase(other, removedDevice: device))

      do {

        let copy: AllLinkDatabaseCopy = try await network.databaseCopy(of: other)
        let naming: [AllLinkRecordResponse] = copy.records.filter { (response: AllLinkRecordResponse) -> Bool in

          response.record.flags.contains(.inUse) && response.record.address == device

        }

        if !naming.isEmpty {

          holders.append(LeftoverRecords(address: other, device: registered, records: naming.map { (response: AllLinkRecordResponse) -> LinkRecord in LinkRecord(response) }))

        }

      } catch let error as CancellationError {

        throw error

      } catch {

        unread.append(UnreadDatabase(address: other, device: registered, reason: error))

      }

    }

    let scan = LeftoverRecordScan(removedDevice: device, holders: holders, unread: unread)

    await observer.linking(.leftoverRecords(scan))

    return scan

  }

  /// The modem's group to unlink in: the one given, or else the group of the modem's records
  /// for the device in the modem's role, or the default group.
  ///
  /// The device's own records say which group its link is in, so a link made in another
  /// group than the default is found.
  private func unlinkGroup(
    _ group: AllLinkGroupNumber?,
    of device: InsteonAddress?,
    role: ModemRole,
    observer: any LinkingObserver
  ) async throws -> AllLinkGroupNumber {

    if let group {

      return group

    }

    guard let device else {

      return Self.defaultModemGroup

    }

    await observer.linking(.readingModemLinks(device, purpose: .findingGroupToUnlink))

    // The modem itself is asked, not an older copy.
    await network.cache.invalidateModem()

    let records: [AllLinkRecord] = try await network.modemLinks(of: device)
    let isController: Bool = role == .controller
    let groups: [UInt8] = Set(records.filter { (record: AllLinkRecord) -> Bool in

      record.flags.contains(.controller) == isController

    }.map(\.group.rawValue)).sorted()

    guard let first = groups.first else {

      await observer.linking(.unlinkGroupChosen(device, group: Self.defaultModemGroup, isFromModemRecords: false))

      return Self.defaultModemGroup

    }

    let chosen = AllLinkGroupNumber(rawValue: first)

    await observer.linking(.unlinkGroupChosen(device, group: chosen, isFromModemRecords: true))

    return chosen

  }

  /// Reads the modem's links with a device again, and tells the observer which are left.
  ///
  /// - Returns: The links left, each role and group once, in the modem's order, or `nil` if
  ///   the modem's database couldn't be read, which is only told.
  /// - Throws: `CancellationError` if the task is canceled.
  private func remainingLinks(of device: InsteonAddress, observer: any LinkingObserver) async throws -> [ModemLink]? {

    let left: ModemLinksLeft = try await modemLinksLeft(of: device)

    await report(left, of: device, to: observer)

    return left.links

  }

  /// Tells the observer which links the modem still has with a device, or that its database
  /// couldn't be read.
  private func report(_ left: ModemLinksLeft, of device: InsteonAddress, to observer: any LinkingObserver) async {

    switch left {
    case let .links(links):
      await observer.linking(.linksRemaining(device, links))
    case let .unreadable(error):
      await observer.linking(.remainingLinksUnknown(device, reason: error))
    }

  }

  /// Reads the modem's links with a device again, without telling the observer.
  ///
  /// - Returns: The links left, each role and group once, in the modem's order, or why the
  ///   modem's database couldn't be read.
  /// - Throws: `CancellationError` if the task is canceled.
  private func modemLinksLeft(of device: InsteonAddress) async throws -> ModemLinksLeft {

    let records: [AllLinkRecord]

    do {

      records = try await network.modemLinks(of: device)

    } catch let error as CancellationError {

      throw error

    } catch {

      return .unreadable(error)

    }

    var links: [ModemLink] = []

    for record in records {

      let link = ModemLink(modemRole: record.flags.contains(.controller) ? .controller : .responder, group: record.group)

      if !links.contains(link) {

        links.append(link)

      }

    }

    return .links(links)

  }

}

/// The modem's links with a device, read again after links were removed.
enum ModemLinksLeft: Sendable {

  /// The links left, each role and group once, in the modem's order. Empty when there are
  /// none.
  case links([ModemLink])

  /// The modem's ALL-Link database couldn't be read.
  case unreadable(any Error)

  /// The links left, or `nil` if the modem's database couldn't be read.
  var links: [ModemLink]? {

    switch self {
    case let .links(links):
      return links
    case .unreadable:
      return nil
    }

  }

}

/// The links removed between the modem and a device, and those left.
struct RemovedAllLinks: Sendable {

  /// The links removed.
  let removed: RemovedLinks

  /// The modem's links with the device, read again.
  let left: ModemLinksLeft

}

extension DeviceLinkingCoordinator {

  /// How long linking or unlinking with a device's SET button waits for it by default: 240
  /// seconds.
  public static let defaultSETButtonTimeout: Duration = Linker.defaultManualLinkingTimeout

  /// How long linking or unlinking without a device's SET button waits for each step by
  /// default: 30 seconds.
  public static let defaultRemoteTimeout: Duration = Linker.defaultRemoteLinkingTimeout

}
