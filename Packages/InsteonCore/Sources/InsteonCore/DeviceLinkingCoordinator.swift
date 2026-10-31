import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// Links devices to a network's modem and unlinks them, with the Insteon device catalog
/// deciding what each device needs, and a ``LinkingObserver`` for what a person sees and does.
///
/// Get one from ``DeviceNetwork/linking``. Every coordinator of a network takes turns with the
/// others, so one link or unlink runs at a time, the modem is in one linking mode at a time,
/// and the network's cache of ALL-Link databases has one writer. After each link or unlink, the
/// network's ``DeviceNetwork/registry`` holds the identity the device reported, the copies of
/// the device's and the modem's ALL-Link databases are forgotten, since both changed, and the
/// modem's records are read again when the coordinator needs them, so the network's
/// ``DeviceNetwork/snapshot()`` holds them.
///
/// The catalog decides:
///
/// - whether a device is turned fully on with Light On before it links as a responder, so it
///   records full on as its on-level: only a light or switched load the registry knows;
/// - the steps a person takes on the device when it's linked or unlinked with its SET button;
/// - whether a device is linked back after the modem links as its controller, and in which of
///   its groups: the first group it controls, group 1 when it controls that;
/// - how a device is sent Enter Unlinking Mode when its links are removed without its SET
///   button: extended for a battery-powered i2CS device.
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

    try await inTurn { () async throws -> DeviceLinkingResult in

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
  ///     the device's group the catalog says it controls. Defaults to ``DeviceLinkingCoordinator/defaultModemGroup``.
  ///   - twoWay: Whether to link the device back when the modem is its controller. Defaults to
  ///     ``TwoWayLinking/whenDeviceControls``.
  ///   - setButtonTimeout: How long the modem waits for the SET button when the device is
  ///     linked with it. Defaults to `Linker.defaultManualLinkingTimeout`.
  ///   - observer: What a person is told and asked.
  /// - Returns: The links made and the device.
  /// - Throws: `LinkMismatch` when the modem reports another device's link or a removed link,
  ///   `LinkingError.unexpectedLink(_:)` when it reports another kind of link,
  ///   `LinkingError.linkingTimedOut` if the device isn't linked in time, the observer's
  ///   errors, the modem's errors, and `CancellationError` if the task is canceled. A link back
  ///   that fails doesn't throw; the result says why.
  public func link(
    _ device: InsteonAddress,
    as role: ModemRole,
    group: AllLinkGroupNumber = DeviceLinkingCoordinator.defaultModemGroup,
    twoWay: TwoWayLinking = .whenDeviceControls,
    setButtonTimeout: Duration = Linker.defaultManualLinkingTimeout,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    try await inTurn { () async throws -> DeviceLinkingResult in

      let linker: Linker = makeLinker()
      let description: DeviceDescription? = await network.registry.device(device)?.deviceDescription
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

        await network.recordLinkChange(of: device, answered: false)

        throw error

      } catch let LinkingError.unexpectedLink(link) {

        await network.recordLinkChange(of: link.address, answered: true)

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

    try await inTurn { () async throws -> DeviceUnlinkingResult in

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

    try await inTurn { () async throws -> DeviceUnlinkingAllResult in

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

        await network.recordLinkChange(of: device, answered: false)

        throw error

      } catch {

        await network.recordLinkChange(of: device, answered: false)

        _ = try await remainingLinks(of: device, observer: observer)

        let steps: [DeviceLifecycle.Step] = Self.deviceSteps(of: description?.profile?.lifecycle?.unlinking)

        await observer.linking(.fallback(.setButtonUnlinking(device, deviceDescription: description, steps: steps)))

        throw RemoteUnlinkingError(device: device, deviceDescription: description, underlying: error)

      }

      await network.recordLinkChange(of: device, answered: !removed.isEmpty)

      let report = RemovedLinks(address: device, device: known, links: removed)

      await observer.linking(.unlinkedAll(report))

      let remaining: [ModemLink]? = try await remainingLinks(of: device, observer: observer)

      return DeviceUnlinkingAllResult(removed: report, remainingLinks: remaining)

    }

  }

  // MARK: - Catalog decisions

  /// The device's group that links back to the modem: group 1 when the catalog says the device
  /// controls it, or else the first group it controls, or group 1 when the catalog names none.
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
  private func inTurn<Value: Sendable>(_ body: () async throws -> Value) async throws -> Value {

    let turns: LinkingTurns = network.linkingTurns

    try await turns.begin()

    do {

      let value: Value = try await body()

      await turns.end()

      return value

    } catch {

      await turns.end()

      throw error

    }

  }

  /// A linker that waits on the network's clock and keeps the network's cache.
  private func makeLinker() -> Linker {

    Linker(modem: network.modem, clock: network.clock, cache: network.cache)

  }

  /// An unlinker that waits on the network's clock and keeps the network's cache.
  private func makeUnlinker() -> Unlinker {

    Unlinker(modem: network.modem, clock: network.clock, cache: network.cache)

  }

  /// Turns a light or switched load fully on before it links as a responder, so it records full
  /// on as its on-level for the group, rather than off. A device that doesn't turn on links in
  /// whatever state it's in.
  private func turnOnBeforeLinking(
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

    let registered: RegisteredDevice? = try await learnIdentity(from: first, observer: observer)

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
  private func learnIdentity(from link: AllLinkingCompleted, observer: any LinkingObserver) async throws -> RegisteredDevice? {

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

    let records: [AllLinkRecord]

    do {

      records = try await network.modemLinks(of: device)

    } catch let error as CancellationError {

      throw error

    } catch {

      await observer.linking(.remainingLinksUnknown(device, reason: error))

      return nil

    }

    var links: [ModemLink] = []

    for record in records {

      let link = ModemLink(modemRole: record.flags.contains(.controller) ? .controller : .responder, group: record.group)

      if !links.contains(link) {

        links.append(link)

      }

    }

    await observer.linking(.linksRemaining(device, links))

    return links

  }

}
