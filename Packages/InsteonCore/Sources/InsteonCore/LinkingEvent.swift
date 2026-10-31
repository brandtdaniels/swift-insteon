import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// What a front end shows or asks while a ``DeviceLinkingCoordinator`` links or unlinks a
/// device: a command prints and waits for Return, and an app shows a sheet with a button.
///
/// The coordinator calls ``LinkingObserver/linking(_:)`` with each ``LinkingEvent`` in order,
/// and ``LinkingObserver/waitUntilDeviceIsReady(_:)`` when a person has to put the device into
/// its mode before the modem joins. The events carry addresses, catalog descriptions and
/// steps, never sentences, so each front end words them its own way.
///
/// ```swift
/// struct Prompter: LinkingObserver {
///   func linking(_ event: LinkingEvent) async {
///     if case let .pressSETButton(prompt) = event {
///       print("Press the SET button within \(prompt.timeout).")
///     }
///   }
///
///   func waitUntilDeviceIsReady(_ prompt: DeviceFirstPrompt) async throws {
///     print("Put the device into its mode, then press Return.")
///     _ = readLine()
///   }
/// }
/// ```
///
/// An app with a button resumes a continuation from it:
///
/// ```swift
/// func waitUntilDeviceIsReady(_ prompt: DeviceFirstPrompt) async throws {
///   await model.ask(prompt)   // Returns when the person taps Ready.
///   try Task.checkCancellation()
/// }
/// ```
public protocol LinkingObserver: Sendable {

  /// Called with each event, in the order it happens. The coordinator waits for it to return.
  ///
  /// - Parameter event: The event.
  func linking(_ event: LinkingEvent) async

  /// Asks a person to put the device into its mode first, since it's the controller, and
  /// returns once they say it's ready, so the modem joins it.
  ///
  /// The modem isn't in a linking mode yet while this waits, so a person can take as long as
  /// they need.
  ///
  /// - Parameter prompt: What the device is to do, with the catalog's steps for it.
  /// - Throws: `CancellationError` when the task is canceled while it waits, or another error
  ///   to stop the link or unlink before the modem joins.
  func waitUntilDeviceIsReady(_ prompt: DeviceFirstPrompt) async throws

  /// Asks a person to wake a battery-powered device, and returns once they say it's awake, so
  /// the modem can send it the message that keeps it awake before it links, as the catalog's
  /// linking from a Hub says for some devices.
  ///
  /// The modem isn't in a linking mode while this waits.
  ///
  /// - Parameter prompt: The device, with the catalog's steps to wake it.
  /// - Throws: `CancellationError` when the task is canceled while it waits, or another error
  ///   to stop the link before anything is sent.
  func waitUntilDeviceIsAwake(_ prompt: WakePrompt) async throws

}

extension LinkingObserver {

  /// Returns at once, for an observer that doesn't ask a person to wake a device. The message
  /// that keeps the device awake is sent anyway, and a device that's asleep doesn't answer it.
  ///
  /// - Parameter prompt: The device, with the catalog's steps to wake it.
  public func waitUntilDeviceIsAwake(_ prompt: WakePrompt) async throws {}

}

/// A battery-powered device to wake before it links, for a front end to ask a person.
public struct WakePrompt: Hashable, Sendable {

  /// The device.
  public var device: InsteonAddress

  /// What the catalog says about the device, or `nil` if it isn't known.
  public var deviceDescription: DeviceDescription?

  /// The catalog's steps on the device itself to wake it, or empty when the catalog doesn't
  /// have them.
  public var steps: [DeviceLifecycle.Step]

  /// Creates a prompt.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - deviceDescription: What the catalog says about the device.
  ///   - steps: The catalog's steps on the device to wake it.
  public init(device: InsteonAddress, deviceDescription: DeviceDescription?, steps: [DeviceLifecycle.Step]) {

    self.device = device
    self.deviceDescription = deviceDescription
    self.steps = steps

  }

}

/// What a ``DeviceLinkingCoordinator`` did to keep a battery-powered device awake while it
/// links, as the catalog's linking from a Hub says, and to let it sleep again afterward.
public enum KeepAwakeEvent: Sendable {

  /// The device is being sent the message that keeps it awake, at the time the catalog says:
  /// before it goes into linking mode, or right after its first link.
  case sending(InsteonAddress, timing: DeviceLifecycle.HubLinking.KeepAwake.Timing)

  /// The device acknowledged the message that keeps it awake.
  case sent(InsteonAddress)

  /// The message that keeps the device awake wasn't sent or acknowledged, for the reason
  /// given, such as a message the catalog never lets an app send. Linking goes on; the device
  /// may fall asleep before it ends.
  case notSent(InsteonAddress, reason: any Error)

  /// Linking is done, or stopped, and the device is being sent the message that lets it sleep
  /// again.
  case releasing(InsteonAddress)

  /// The device acknowledged the message that lets it sleep again.
  case released(InsteonAddress)

  /// The message that lets the device sleep again wasn't acknowledged, for the reason given.
  case notReleased(InsteonAddress, reason: any Error)

}

/// Something that happened while a ``DeviceLinkingCoordinator`` linked or unlinked a device,
/// for a ``LinkingObserver`` to show.
public enum LinkingEvent: Sendable {

  /// The device is being asked for its identity with ID Request, after a link that didn't
  /// report one.
  case identifying(InsteonAddress)

  /// The device is being turned fully on with Light On before it links as a responder, so it
  /// records full on as its on-level for the group.
  case turningOnBeforeLinking(InsteonAddress)

  /// The device didn't turn on before linking, such as an i2CS device that isn't linked to the
  /// modem yet. It links in the state it's in, so its on-level matches that state.
  case notTurnedOnBeforeLinking(InsteonAddress, reason: any Error)

  /// The device isn't turned on before linking: the catalog doesn't describe it as a light or
  /// a switched load, so it links with whatever on-level it records.
  case notTurningOnBeforeLinking(InsteonAddress)

  /// The device is being linked without its SET button: the modem starts ALL-Linking in the
  /// role, and the device is sent Enter Linking Mode.
  case linkingRemotely(InsteonAddress, modemRole: ModemRole)

  /// The coordinator took another way after the first failed.
  case fallback(LinkingFallback)

  /// The modem is the controller, in its mode, and waits for a person to press the device's
  /// SET button.
  case pressSETButton(SETButtonPrompt)

  /// The device is ready as the controller, and the modem is joining it as the responder,
  /// waiting up to the duration for the device's link.
  case modemJoining(timeout: Duration)

  /// The device is being linked back: it's sent Enter Linking Mode for its group, so the
  /// modem becomes its responder and hears it.
  case linkingBack(InsteonAddress, group: AllLinkGroupNumber)

  /// The modem reported a link.
  case linked(LinkedDevice)

  /// A leg of the catalog's linking from a Hub is starting: the modem starts ALL-Linking in
  /// the leg's role and group.
  case hubLinkingLegStarted(HubLinkingLeg)

  /// The device joined a leg's link: it acknowledged Enter Linking Mode for the leg's device
  /// group, or, going first, a person said it's in linking mode. A device linked with its SET
  /// button once the modem started has no event of its own; ``LinkingEvent/pressSETButton(_:)``
  /// asks for it.
  case hubLinkingLegJoined(HubLinkingLeg, by: HubLinkingJoin)

  /// The modem reported a leg's link with ALL-Linking Completed, and the next leg can start.
  /// ``LinkingEvent/linked(_:)`` reports the same link with the device.
  case hubLinkingLegCompleted(HubLinkingLeg, link: AllLinkingCompleted)

  /// A leg failed, for the reason given, and the legs listed after it aren't run. When the
  /// leg is ``HubLinkingLeg/isRemoteLinkingExpectedToWork``, the catalog says Enter Linking
  /// Mode works for the device, so the failure isn't expected.
  case hubLinkingLegFailed(HubLinkingLeg, reason: any Error, notRun: [HubLinkingLeg])

  /// The device is kept awake while it links, or let sleep again afterward.
  case keepAwake(KeepAwakeEvent)

  /// The catalog says a leg's one link covers every group the device controls while one of
  /// its operating flags is in the state given. The flag isn't read or changed; without it,
  /// each group needs a link of its own.
  case allGroupsWhen(HubLinkingLeg, condition: DeviceProfile.Group.Condition)

  /// The modem's ALL-Link database is being read for the device's links.
  case readingModemLinks(InsteonAddress, purpose: ModemLinksPurpose)

  /// The modem's group to unlink in was chosen for the device: from the modem's records for
  /// it in the modem's role, or the default group when it has none.
  case unlinkGroupChosen(InsteonAddress, group: AllLinkGroupNumber, isFromModemRecords: Bool)

  /// One link between the modem and the device is being removed without its SET button.
  case unlinkingRemotely(InsteonAddress, deviceDescription: DeviceDescription?, link: ModemLink)

  /// The modem reported a removed link.
  case unlinked(UnlinkedLink)

  /// Every link between the modem and the device was removed without its SET button.
  case unlinkedAll(RemovedLinks)

  /// The links the modem still has with the device, from its records, each role and group
  /// once, in the modem's order. Empty when it has none.
  case linksRemaining(InsteonAddress, [ModemLink])

  /// The modem's ALL-Link database couldn't be read to find the device's other links.
  case remainingLinksUnknown(InsteonAddress, reason: any Error)

  /// The caller said the device is gone, and its links with the modem aren't confirmed gone,
  /// for the reason given, so the modem's own records that name it are being deleted
  /// directly. The device's records stay as they are.
  case deletingModemRecords(InsteonAddress, reason: ModemRecordDeletionReason)

  /// The modem's own records that named the device were deleted directly, in the modem's
  /// order.
  case modemRecordsDeleted(InsteonAddress, [AllLinkRecord])

  /// The device wasn't forgotten, since its links with the modem aren't confirmed gone, for
  /// the reason given.
  case kept(InsteonAddress, because: DeviceKeptReason)

  /// The network forgot a removed device: its identity, its state and its records in the
  /// snapshot's copy of the modem's ALL-Link database.
  case forgotten(ForgottenDevice)

  /// A device's ALL-Link database, the first address, is being read for records that still
  /// name the removed device, the second.
  case scanningDatabase(InsteonAddress, removedDevice: InsteonAddress)

  /// The records other devices still hold that name a removed device, and the devices whose
  /// databases couldn't be read. Nothing was changed in them.
  case leftoverRecords(LeftoverRecordScan)

  /// How to restore a removed device's factory settings, from the catalog, for a person to
  /// follow. The coordinator doesn't reset the device.
  case factoryReset(FactoryResetSteps)

}

/// Why a ``DeviceLinkingCoordinator`` reads the modem's ALL-Link database for a device's
/// links.
public enum ModemLinksPurpose: Hashable, Sendable {

  /// To find each link to remove.
  case findingLinksToRemove

  /// To find the group of the link to remove.
  case findingGroupToUnlink

}

/// Another way a ``DeviceLinkingCoordinator`` took after the first failed.
public enum LinkingFallback: Sendable {

  /// The device didn't link without its SET button, so it's linked with its SET button
  /// instead, and only its link is accepted.
  case setButtonLinking(InsteonAddress, reason: any Error)

  /// The device's links couldn't all be removed without its SET button. The links left are
  /// removed with its SET button, in unlinking mode, with the catalog's steps for it, which are
  /// empty when the catalog doesn't have them.
  case setButtonUnlinking(InsteonAddress, deviceDescription: DeviceDescription?, steps: [DeviceLifecycle.Step])

}

/// The modem's role in a link, and how it waits, for a front end to tell a person to press the
/// device's SET button.
public struct SETButtonPrompt: Hashable, Sendable {

  /// Whether a link is being made or removed.
  public var direction: LinkingDirection

  /// The modem's group.
  public var group: AllLinkGroupNumber

  /// How long the modem waits.
  public var timeout: Duration

  /// The device asked for, or `nil` for whichever device's SET button is pressed.
  public var device: InsteonAddress?

  /// What the catalog says about the device, or `nil` if it isn't known.
  public var deviceDescription: DeviceDescription?

  /// The catalog's steps on the device itself to make the link, or empty when the catalog
  /// doesn't have them. A responder leaves a controller's group the way it joins one, so the
  /// linking steps apply when a link is removed too.
  public var steps: [DeviceLifecycle.Step]

  /// Creates a prompt.
  ///
  /// - Parameters:
  ///   - direction: Whether a link is being made or removed.
  ///   - group: The modem's group.
  ///   - timeout: How long the modem waits.
  ///   - device: The device asked for, or `nil` for any device.
  ///   - deviceDescription: What the catalog says about the device.
  ///   - steps: The catalog's steps on the device.
  public init(
    direction: LinkingDirection,
    group: AllLinkGroupNumber,
    timeout: Duration,
    device: InsteonAddress?,
    deviceDescription: DeviceDescription?,
    steps: [DeviceLifecycle.Step]
  ) {

    self.direction = direction
    self.group = group
    self.timeout = timeout
    self.device = device
    self.deviceDescription = deviceDescription
    self.steps = steps

  }

}

/// What a device is to do before the modem joins it as the responder, for a front end to ask a
/// person.
public struct DeviceFirstPrompt: Hashable, Sendable {

  /// Whether the device is to enter linking mode or unlinking mode.
  public var direction: LinkingDirection

  /// The device asked for, or `nil` for any device.
  public var device: InsteonAddress?

  /// What the catalog says about the device, or `nil` if it isn't known.
  public var deviceDescription: DeviceDescription?

  /// The catalog's steps on the device itself for its mode, or empty when the catalog doesn't
  /// have them.
  public var steps: [DeviceLifecycle.Step]

  /// Creates a prompt.
  ///
  /// - Parameters:
  ///   - direction: Whether the device is to link or unlink.
  ///   - device: The device asked for, or `nil` for any device.
  ///   - deviceDescription: What the catalog says about the device.
  ///   - steps: The catalog's steps on the device.
  public init(direction: LinkingDirection, device: InsteonAddress?, deviceDescription: DeviceDescription?, steps: [DeviceLifecycle.Step]) {

    self.direction = direction
    self.device = device
    self.deviceDescription = deviceDescription
    self.steps = steps

  }

}

/// Which of a link's legs the modem reported.
public enum LinkLeg: Hashable, Sendable {

  /// The link asked for.
  case first

  /// The link back that follows, in which the device controls and the modem responds.
  case linkBack

  /// A leg after the first of the catalog's linking from a Hub, by its place in the catalog's
  /// order, from 0. The first leg is ``LinkLeg/first``.
  case hubLinking(Int)

}

/// A link the modem reported, with the device as the registry knows it.
public struct LinkedDevice: Hashable, Sendable {

  /// The link.
  public var link: AllLinkingCompleted

  /// The device, with the identity it reported and its description, or `nil` if its identity
  /// isn't known.
  public var device: RegisteredDevice?

  /// Which leg the link is.
  public var leg: LinkLeg

  /// Creates a reported link.
  ///
  /// - Parameters:
  ///   - link: The link.
  ///   - device: The device as the registry knows it.
  ///   - leg: Which leg the link is.
  public init(link: AllLinkingCompleted, device: RegisteredDevice?, leg: LinkLeg) {

    self.link = link
    self.device = device
    self.leg = leg

  }

}

/// A removed link the modem reported, with the device as the registry knew it.
public struct UnlinkedLink: Hashable, Sendable {

  /// The removed link. A removed link carries no identity.
  public var link: AllLinkingCompleted

  /// The device as the registry knew it, or `nil` if its identity isn't known.
  public var device: RegisteredDevice?

  /// Creates a removed link.
  ///
  /// - Parameters:
  ///   - link: The removed link.
  ///   - device: The device as the registry knew it.
  public init(link: AllLinkingCompleted, device: RegisteredDevice?) {

    self.link = link
    self.device = device

  }

}

/// The links removed between the modem and a device without its SET button.
public struct RemovedLinks: Hashable, Sendable {

  /// The device.
  public var address: InsteonAddress

  /// The device as the registry knows it, or `nil` if its identity isn't known.
  public var device: RegisteredDevice?

  /// The links removed, in order, or empty if the modem had none with the device.
  public var links: [ModemLink]

  /// Creates removed links.
  ///
  /// - Parameters:
  ///   - address: The device.
  ///   - device: The device as the registry knows it.
  ///   - links: The links removed.
  public init(address: InsteonAddress, device: RegisteredDevice?, links: [ModemLink]) {

    self.address = address
    self.device = device
    self.links = links

  }

}

/// Whether a ``DeviceLinkingCoordinator`` links a device back after the modem links as its
/// controller, so the modem becomes the responder of the device's group and hears it.
public enum TwoWayLinking: Hashable, Sendable {

  /// Always link back.
  case always

  /// Link back when the Insteon device catalog says the device controls: as the product, or
  /// in one of its groups. A device the catalog doesn't have isn't linked back.
  case whenDeviceControls

  /// Never link back.
  case never

}

/// What a ``DeviceLinkingCoordinator`` linked.
public struct DeviceLinkingResult: Sendable {

  /// The links the modem reported, in order: the link asked for, then the link back if there
  /// was one, or each leg's link of the catalog's linking from a Hub.
  public var links: [AllLinkingCompleted]

  /// The device, as the registry knows it after the link, or `nil` if its identity isn't
  /// known.
  public var device: RegisteredDevice?

  /// Why the link back failed, or `nil` if it worked or wasn't tried. The link asked for stays
  /// made; the device can be linked back with its SET button, the modem as the responder.
  public var linkBackFailure: (any Error)?

  /// Each leg of the catalog's linking from a Hub and what became of it, in the catalog's
  /// order, or empty when the device was linked without them.
  public var legs: [HubLinkingLegOutcome]

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - links: The links the modem reported.
  ///   - device: The device as the registry knows it.
  ///   - linkBackFailure: Why the link back failed.
  ///   - legs: Each leg of the catalog's linking from a Hub and what became of it. Defaults to
  ///     none.
  public init(links: [AllLinkingCompleted], device: RegisteredDevice?, linkBackFailure: (any Error)?, legs: [HubLinkingLegOutcome] = []) {

    self.links = links
    self.device = device
    self.linkBackFailure = linkBackFailure
    self.legs = legs

  }

  /// The leg that failed, so the legs after it weren't run, or `nil` if none did.
  public var failedLeg: HubLinkingLegOutcome? {

    legs.first { (outcome: HubLinkingLegOutcome) -> Bool in outcome.failure != nil }

  }

}

/// What a ``DeviceLinkingCoordinator`` unlinked with a device's SET button.
public struct DeviceUnlinkingResult: Sendable {

  /// The removed link the modem reported.
  public var link: UnlinkedLink

  /// The links the modem still has with the device, or `nil` if its database couldn't be read.
  public var remainingLinks: [ModemLink]?

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - link: The removed link.
  ///   - remainingLinks: The links left.
  public init(link: UnlinkedLink, remainingLinks: [ModemLink]?) {

    self.link = link
    self.remainingLinks = remainingLinks

  }

}

/// What a ``DeviceLinkingCoordinator`` unlinked without a device's SET button.
public struct DeviceUnlinkingAllResult: Sendable {

  /// The links removed.
  public var removed: RemovedLinks

  /// The links the modem still has with the device, or `nil` if its database couldn't be read.
  public var remainingLinks: [ModemLink]?

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - removed: The links removed.
  ///   - remainingLinks: The links left.
  public init(removed: RemovedLinks, remainingLinks: [ModemLink]?) {

    self.removed = removed
    self.remainingLinks = remainingLinks

  }

}

/// A device's links couldn't all be removed without its SET button.
///
/// The links removed before the failure stay removed. The coordinator has already said which
/// are left, with ``LinkingEvent/linksRemaining(_:_:)``, and how to remove them with the SET
/// button, with ``LinkingFallback/setButtonUnlinking(_:deviceDescription:steps:)``.
public struct RemoteUnlinkingError: Error {

  /// The device.
  public var device: InsteonAddress

  /// What the catalog says about the device, or `nil` if it isn't known.
  public var deviceDescription: DeviceDescription?

  /// Why removing a link failed, such as `LinkingError.linkingTimedOut`.
  public var underlying: any Error

  /// Creates an error.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - deviceDescription: What the catalog says about the device.
  ///   - underlying: Why removing a link failed.
  public init(device: InsteonAddress, deviceDescription: DeviceDescription?, underlying: any Error) {

    self.device = device
    self.deviceDescription = deviceDescription
    self.underlying = underlying

  }

}
