import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// One link of the Insteon device catalog's linking from a Hub, as a
/// ``DeviceLinkingCoordinator`` makes it: the modem's role and group, and the device's group.
///
/// The catalog's `lifecycle.fromHub` gives a device's legs in order, one ALL-Linking session
/// each. For each, the modem starts ALL-Linking first, with link code `0x01` as controller or
/// `0x00` as responder, the device joins with Enter Linking Mode for its group or with its SET
/// button, and the coordinator waits for ALL-Linking Completed (`0x53`) before the next leg.
public struct HubLinkingLeg: Hashable, Sendable {

  /// The device.
  public var device: InsteonAddress

  /// The leg's place in the catalog's order, from 0.
  public var index: Int

  /// How many legs the catalog gives the device.
  public var count: Int

  /// The modem's role in the link.
  public var modemRole: ModemRole

  /// The group Start ALL-Linking names, which the modem's record holds.
  public var modemGroup: AllLinkGroupNumber

  /// The device's group, which Enter Linking Mode names in cmd2.
  public var deviceGroup: AllLinkGroupNumber

  /// Whether the catalog says the modem can put the device in linking mode with Enter Linking
  /// Mode, or `nil` if it doesn't say.
  public var remoteEnterLinkingMode: DeviceLifecycle.HubLinking.Answer?

  /// The operating flag state under which this one link puts the modem in every group the
  /// device controls, or `nil` if the leg links ``HubLinkingLeg/deviceGroup`` alone. The
  /// coordinator reports it and doesn't change the flag.
  public var allGroupsWhen: DeviceProfile.Group.Condition?

  /// Creates a leg.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - index: The leg's place in the catalog's order, from 0.
  ///   - count: How many legs the catalog gives the device.
  ///   - modemRole: The modem's role in the link.
  ///   - modemGroup: The group Start ALL-Linking names.
  ///   - deviceGroup: The device's group.
  ///   - remoteEnterLinkingMode: Whether the modem can put the device in linking mode.
  ///     Defaults to `nil`.
  ///   - allGroupsWhen: The operating flag state under which the link covers every group the
  ///     device controls. Defaults to `nil`.
  public init(
    device: InsteonAddress,
    index: Int,
    count: Int,
    modemRole: ModemRole,
    modemGroup: AllLinkGroupNumber,
    deviceGroup: AllLinkGroupNumber,
    remoteEnterLinkingMode: DeviceLifecycle.HubLinking.Answer? = nil,
    allGroupsWhen: DeviceProfile.Group.Condition? = nil
  ) {

    self.device = device
    self.index = index
    self.count = count
    self.modemRole = modemRole
    self.modemGroup = modemGroup
    self.deviceGroup = deviceGroup
    self.remoteEnterLinkingMode = remoteEnterLinkingMode
    self.allGroupsWhen = allGroupsWhen

  }

  /// Whether the leg is the catalog's first.
  public var isFirst: Bool {

    index == 0

  }

  /// Whether the catalog says Enter Linking Mode works for the device, so a failure to link
  /// with it isn't expected.
  public var isRemoteLinkingExpectedToWork: Bool {

    remoteEnterLinkingMode == .yes

  }

  /// The legs the catalog gives a device, in order, or `nil` when it gives none, or names a
  /// modem role this package doesn't know, so the device is linked the way a device without
  /// them is.
  ///
  /// - Parameters:
  ///   - description: What the catalog says about the device, if it's known.
  ///   - device: The device.
  /// - Returns: The legs.
  static func legs(of description: DeviceDescription?, device: InsteonAddress) -> [HubLinkingLeg]? {

    guard let hubLinking = description?.hubLinking, !hubLinking.legs.isEmpty else {

      return nil

    }

    var legs: [HubLinkingLeg] = []

    for (index, leg) in hubLinking.legs.enumerated() {

      let role: ModemRole

      switch leg.modemRole {
      case .controller:
        role = .controller
      case .responder:
        role = .responder
      default:
        return nil
      }

      legs.append(HubLinkingLeg(
        device: device,
        index: index,
        count: hubLinking.legs.count,
        modemRole: role,
        modemGroup: leg.modemGroup,
        deviceGroup: leg.deviceGroup,
        remoteEnterLinkingMode: hubLinking.remoteEnterLinkingMode?.works,
        allGroupsWhen: leg.allGroupsWhen
      ))

    }

    return legs

  }

}

/// How the device joined a ``HubLinkingLeg``'s link.
public enum HubLinkingJoin: Hashable, Sendable {

  /// The modem sent it Enter Linking Mode for the leg's device group.
  case enterLinkingMode

  /// A person pressed its SET button once the modem started ALL-Linking.
  case setButton

  /// A person put it in linking mode with its own controls before the modem started
  /// ALL-Linking, as the catalog says for a device that goes first.
  case deviceFirst

}

/// What became of a ``HubLinkingLeg``.
public enum HubLinkingLegStatus: Sendable {

  /// The modem reported the leg's link, and how the device joined it.
  case linked(AllLinkingCompleted, by: HubLinkingJoin)

  /// The leg failed, for the reason given, and the legs after it weren't run.
  case failed(any Error)

  /// The leg wasn't run, since one before it failed.
  case notRun

}

/// A ``HubLinkingLeg`` and what became of it.
public struct HubLinkingLegOutcome: Sendable {

  /// The leg.
  public var leg: HubLinkingLeg

  /// What became of it.
  public var status: HubLinkingLegStatus

  /// Creates an outcome.
  ///
  /// - Parameters:
  ///   - leg: The leg.
  ///   - status: What became of it.
  public init(leg: HubLinkingLeg, status: HubLinkingLegStatus) {

    self.leg = leg
    self.status = status

  }

  /// The link the modem reported, or `nil` if the leg didn't link.
  public var link: AllLinkingCompleted? {

    if case let .linked(link, _) = status {

      return link

    }

    return nil

  }

  /// Why the leg failed, or `nil` if it didn't.
  public var failure: (any Error)? {

    if case let .failed(error) = status {

      return error

    }

    return nil

  }

}
