import Foundation
import InsteonDeviceCatalog
import InsteonProtocol

/// The state a relay records when it links as a responder, such as an I/O Linc's: what a
/// group On from its controller then sets it to. A group Off sets it to the opposite.
///
/// A relay keeps its state at link time as Data 1 of its responder record: `0xFF` when it was
/// on, and `0x00` when it was off.
/// ``DeviceLinkingCoordinator/linkRelay(_:recording:group:twoWay:setButtonTimeout:observer:)``
/// puts the relay in the state before it links, and
/// ``DeviceLinkingCoordinator/planDatabaseLink(_:relayState:)`` writes the byte directly.
public enum RelayState: String, Hashable, Sendable, CaseIterable {

  /// A group On turns the relay on, and a group Off turns it off.
  case on

  /// A group On turns the relay off, and a group Off turns it on.
  case off

  /// The other state.
  public var opposite: RelayState {

    switch self {
    case .on:
      return .off
    case .off:
      return .on
    }

  }

  /// The responder record's Data 1 that holds the state: `0xFF` for on, `0x00` for off.
  public var data1: UInt8 {

    switch self {
    case .on:
      return 0xFF
    case .off:
      return 0x00
    }

  }

}

/// What linking a relay with a chosen ``RelayState`` switches and puts back, from its flags
/// and status, as
/// ``DeviceLinkingCoordinator/planRelayLink(_:recording:observer:)`` reads them, for a front end
/// to show and ask about before the relay, and whatever it controls, is switched.
public struct RelayLinkPlan: Hashable, Sendable {

  /// The relay.
  public var device: InsteonAddress

  /// The state it's to record.
  public var state: RelayState

  /// Its state before the link, as its status read.
  public var before: RelayState

  /// Whether its momentary flag is on.
  public var isMomentary: Bool

  /// Whether its momentaryOnBothCommands flag is on. On a momentary relay, every On and Off
  /// then only pulses it, and the recorded state is ignored.
  public var pulsesOnBothCommands: Bool

  /// Creates a plan.
  ///
  /// - Parameters:
  ///   - device: The relay.
  ///   - state: The state it's to record.
  ///   - before: Its state before the link.
  ///   - isMomentary: Whether its momentary flag is on.
  ///   - pulsesOnBothCommands: Whether its momentaryOnBothCommands flag is on.
  public init(device: InsteonAddress, state: RelayState, before: RelayState, isMomentary: Bool, pulsesOnBothCommands: Bool) {

    self.device = device
    self.state = state
    self.before = before
    self.isMomentary = isMomentary
    self.pulsesOnBothCommands = pulsesOnBothCommands

  }

  /// Whether the state is ignored: on a momentary relay with momentaryOnBothCommands on, every
  /// On and Off only pulses it. The relay isn't switched and no flag is written.
  public var ignoresState: Bool {

    isMomentary && pulsesOnBothCommands

  }

  /// Whether momentaryOnBothCommands is on though the relay isn't momentary, a mode whose
  /// effect on the relay isn't verified. The relay isn't switched and no flag is written, so
  /// its record holds the state it's in.
  public var leavesUnverifiedMode: Bool {

    !isMomentary && pulsesOnBothCommands

  }

  /// Whether the relay is switched to the state: when it isn't in it, or when it's momentary
  /// and the state is on, since a momentary relay reads on only while it's closed for its
  /// momentary time. Never with momentaryOnBothCommands on.
  public var switchesRelay: Bool {

    !pulsesOnBothCommands && (before != state || (isMomentary && state == .on))

  }

  /// The flag turned off for the link, so the relay holds its state, or `nil` when none is.
  public var clearedFlag: String? {

    switchesRelay && isMomentary ? DeviceLinkingCoordinator.momentaryFlag.rawValue : nil

  }

  /// Whether a momentary relay switched on is switched off right after the link, since it
  /// rests open.
  public var opensAfterLinking: Bool {

    clearedFlag != nil && state == .on

  }

  /// Whether a relay that isn't momentary is switched back to its state before when linking
  /// fails or is canceled. Once linked, it keeps the state it recorded.
  public var switchesBackOnFailure: Bool {

    switchesRelay && !isMomentary

  }

}

/// A relay linked with a chosen ``RelayState``: what its responder record holds, what a group
/// On and a group Off do to it, and whether what linking changed went back as it was.
///
/// The link is made whatever these say. ``RelayStateLink/problems`` lists what didn't go as
/// asked, for a front end to report.
public struct RelayStateLink: Sendable {

  /// The relay.
  public var device: InsteonAddress

  /// The state asked for.
  public var state: RelayState

  /// The modem's group in the link.
  public var group: AllLinkGroupNumber

  /// Data 1 of the relay's responder record for the link, read back after it was made, or
  /// `nil` when it couldn't be read.
  public var recordedData1: UInt8?

  /// Why the record doesn't hold the state asked for, such as
  /// ``RelayStateLinkingError/recordedOtherState(_:group:data1:requested:)``, or `nil` when it
  /// does.
  public var recordFailure: RelayStateLinkingError?

  /// The operating flag turned off for the link, such as `momentary`, or `nil` when none was.
  public var clearedFlag: String?

  /// Whether the relay is momentary after the link, as its momentary flag read back. `false`
  /// when the flag turned off for the link wasn't confirmed back on.
  public var isMomentary: Bool

  /// Whether both On and Off close the momentary relay, as its momentaryOnBothCommands flag
  /// says. The relay then only pulses, so the recorded state isn't used while it's momentary.
  public var pulsesOnBothCommands: Bool

  /// What didn't go back as it was after the link, in order: a momentary relay not switched
  /// off, the flag not set back or not confirmed, or another flag that changed. Empty when
  /// everything did.
  public var restoreFailures: [RelayStateLinkingError]

  /// What a group On sets the relay to: the state asked for.
  public var groupOn: RelayState {

    state

  }

  /// What a group Off sets the relay to: the opposite of the state asked for.
  public var groupOff: RelayState {

    state.opposite

  }

  /// Whether the flag turned off for the link read back on afterward, or `nil` when none was
  /// turned off.
  public var isRestored: Bool? {

    guard clearedFlag != nil else {

      return nil

    }

    return !restoreFailures.contains { (failure: RelayStateLinkingError) -> Bool in

      switch failure {
      case .flagNotRestored, .flagRestoreUnconfirmed:
        return true
      default:
        return false
      }

    }

  }

  /// What didn't go as asked: the record's failure, then the restore's. Empty when everything
  /// did.
  public var problems: [RelayStateLinkingError] {

    (recordFailure.map { (failure: RelayStateLinkingError) -> [RelayStateLinkingError] in [failure] } ?? []) + restoreFailures

  }

  /// Creates a relay linked with a state.
  ///
  /// - Parameters:
  ///   - device: The relay.
  ///   - state: The state asked for.
  ///   - group: The modem's group in the link.
  ///   - recordedData1: Data 1 of the responder record read back, or `nil`.
  ///   - recordFailure: Why the record doesn't hold the state, or `nil`. Defaults to `nil`.
  ///   - clearedFlag: The flag turned off for the link, or `nil`. Defaults to `nil`.
  ///   - isMomentary: Whether the relay is momentary after the link.
  ///   - pulsesOnBothCommands: Whether both On and Off close its momentary relay.
  ///   - restoreFailures: What didn't go back as it was. Defaults to none.
  public init(
    device: InsteonAddress,
    state: RelayState,
    group: AllLinkGroupNumber,
    recordedData1: UInt8?,
    recordFailure: RelayStateLinkingError? = nil,
    clearedFlag: String? = nil,
    isMomentary: Bool,
    pulsesOnBothCommands: Bool,
    restoreFailures: [RelayStateLinkingError] = []
  ) {

    self.device = device
    self.state = state
    self.group = group
    self.recordedData1 = recordedData1
    self.recordFailure = recordFailure
    self.clearedFlag = clearedFlag
    self.isMomentary = isMomentary
    self.pulsesOnBothCommands = pulsesOnBothCommands
    self.restoreFailures = restoreFailures

  }

}

/// What a ``DeviceLinkingCoordinator`` did to put a relay in a chosen state before it linked,
/// and to put back what it changed for that.
public enum RelayStateEvent: Sendable {

  /// The relay's flag, such as `momentary`, is on, and it's being turned off for the link, so
  /// the relay holds its state rather than opening again.
  case clearingFlag(InsteonAddress, flag: String)

  /// The relay is being sent its group type's On or Off for the state.
  case settingRelay(InsteonAddress, RelayState)

  /// The relay's status showed it already in the state, so it wasn't sent a command.
  case relayAlreadySet(InsteonAddress, RelayState)

  /// The relay's flag, such as `momentaryOnBothCommands`, is on, so it's linked without being
  /// switched, and no flag is written: on a momentary relay every On and Off only pulses it,
  /// so the state is ignored; on one that isn't momentary, what the flag does isn't verified.
  case stateIgnored(InsteonAddress, flag: String, isMomentary: Bool)

  /// The relay's status reads the state given, not the one it was switched to, so it's left
  /// as it is rather than switched again.
  case relayLeft(InsteonAddress, reads: RelayState)

  /// The relay's status, read again, showed it in the state.
  case relayConfirmed(InsteonAddress, RelayState)

  /// The relay is being switched to the state given after the link: off, for a momentary
  /// relay switched on, while its flag is still off, since it rests open; or its state before,
  /// for a relay that isn't momentary, when linking failed or was canceled.
  case returningRelay(InsteonAddress, RelayState)

  /// The flag turned off for the link is being turned back on: after the link, or after a
  /// failure or cancellation.
  case restoringFlag(InsteonAddress, flag: String)

  /// The flag read back on.
  case flagRestored(InsteonAddress, flag: String)

  /// Something didn't go back as it was, for the reason given.
  case restoreFailed(InsteonAddress, RelayStateLinkingError)

  /// The relay linked: what its record holds, what a group On and a group Off do to it, and
  /// what didn't go as asked.
  case recorded(RelayStateLink)

}

/// Why a relay wasn't linked with a chosen ``RelayState``, or what didn't go as asked once it
/// was.
///
/// The refusals come before the relay is switched or a flag is written:
/// ``notIdentified(_:because:)``, ``notLinkedToModem(_:)``, ``notDescribed(_:)``,
/// ``notARelay(_:product:)``, ``momentaryNotChangeable(_:flag:)`` and
/// ``flagUnreadable(_:flag:)``. After ``flagNotChanged(_:flag:isSet:)``,
/// ``relayNotConfirmed(_:requested:)`` or ``remoteLinkingFailed(_:reason:)``, what was changed
/// is put back first. The rest are reported in a ``RelayStateLink``, since the link stays made.
public enum RelayStateLinkingError: Error, Sendable {

  /// The device didn't report its identity, for the reason given, so whether its main group
  /// is a relay isn't known.
  case notIdentified(InsteonAddress, because: UnidentifiedReason)

  /// The device rejects the modem, as an i2CS device does until it holds a link to it, so it
  /// takes no direct command. It's linked without a relay state first.
  case notLinkedToModem(InsteonAddress)

  /// The device reported an identity the Insteon device catalog doesn't describe, so whether
  /// its main group is a relay isn't known.
  case notDescribed(InsteonAddress)

  /// The device's main group isn't a relay, as the catalog describes it. The associated values
  /// are the device and its product, as a sentence names it.
  case notARelay(InsteonAddress, product: String)

  /// The relay's momentary flag is on, and the catalog doesn't let linking change it, so the
  /// relay would open again before it links and record off.
  case momentaryNotChangeable(InsteonAddress, flag: String)

  /// The device's reply to Get Operating Flags didn't carry the flag.
  case flagUnreadable(InsteonAddress, flag: String)

  /// The flag didn't read back in the state it was written to.
  case flagNotChanged(InsteonAddress, flag: String, isSet: Bool)

  /// The relay's status, read again, didn't show the requested state, so nothing was linked.
  case relayNotConfirmed(InsteonAddress, requested: RelayState)

  /// The device didn't link without its SET button, for the reason given. It isn't linked
  /// with the SET button instead, since that link records whatever state the relay is in by
  /// the time a person presses it.
  case remoteLinkingFailed(InsteonAddress, reason: any Error)

  /// The relay's responder record for the link holds another state as Data 1. The link is
  /// made.
  case recordedOtherState(InsteonAddress, group: AllLinkGroupNumber, data1: UInt8, requested: RelayState)

  /// The relay's database holds no responder record of the modem for the link's group. The
  /// link was reported.
  case recordNotFound(InsteonAddress, group: AllLinkGroupNumber)

  /// The relay's database couldn't be read to check its record, for the reason given. The
  /// link was reported.
  case recordNotRead(InsteonAddress, reason: any Error)

  /// The relay wasn't switched to the state given after the link, for the reason given: off
  /// for a momentary relay switched on, or its state before for a relay that isn't momentary
  /// when linking failed. It may be left in the state it was switched to.
  case relayNotReturned(InsteonAddress, state: RelayState, reason: any Error)

  /// The relay, read again inside the link, isn't as the plan approved for it said, so the
  /// link would switch or put back other than it showed. Nothing was changed.
  case planChanged(old: RelayLinkPlan, new: RelayLinkPlan)

  /// The relay's status couldn't be read after linking failed, for the reason given, so it
  /// was switched back to the state given without knowing whether someone had switched it.
  case relayReturnUnconfirmed(InsteonAddress, state: RelayState, reason: any Error)

  /// The flag turned off for the link wasn't turned back on, twice, for the reason given.
  case flagNotRestored(InsteonAddress, flag: String, reason: any Error)

  /// The flag turned off for the link was written back on, but couldn't be read back, twice,
  /// for the reason given, so it isn't confirmed.
  case flagRestoreUnconfirmed(InsteonAddress, flag: String, reason: any Error)

  /// The operating flags byte the flag is in reads otherwise after the link than before it,
  /// so a flag besides the one linking changed did too.
  case otherFlagsChanged(InsteonAddress, before: UInt8, after: UInt8)

  /// The device already has a responder record of the modem in the group with another state
  /// as Data 1, and a database link leaves records in place as they are.
  case recordInPlace(InsteonAddress, group: AllLinkGroupNumber, data1: UInt8)

  /// The device the error is about.
  public var device: InsteonAddress {

    switch self {
    case let .notIdentified(device, _), let .notLinkedToModem(device), let .notDescribed(device), let .notARelay(device, _),
      let .momentaryNotChangeable(device, _), let .flagUnreadable(device, _), let .flagNotChanged(device, _, _),
      let .relayNotConfirmed(device, _), let .remoteLinkingFailed(device, _), let .recordedOtherState(device, _, _, _),
      let .recordNotFound(device, _), let .recordNotRead(device, _), let .relayNotReturned(device, _, _), let .relayReturnUnconfirmed(device, _, _),
      let .flagNotRestored(device, _, _), let .flagRestoreUnconfirmed(device, _, _), let .otherFlagsChanged(device, _, _),
      let .recordInPlace(device, _, _):
      return device
    case let .planChanged(old, _):
      return old.device
    }

  }

}

extension RelayStateLinkingError: CustomStringConvertible, LocalizedError {

  /// A one-line explanation of the error.
  public var description: String {

    switch self {
    case let .notIdentified(device, reason):
      "\(device) didn't report its identity\(Self.why(reason)), so whether its main group is a relay isn't known. Nothing was changed."
    case let .notLinkedToModem(device):
      "\(device) rejects the modem's direct commands until it holds a link to the modem, as an i2CS device does. Nothing was changed. Link it without a relay state first, then link it again with one."
    case let .notDescribed(device):
      "The Insteon device catalog doesn't describe the identity \(device) reported, so whether its main group is a relay isn't known. Nothing was changed."
    case let .notARelay(device, product):
      "\(device), \(product), isn't a relay by the Insteon device catalog, so it records no relay state. Nothing was changed."
    case let .momentaryNotChangeable(device, flag):
      "\(device)'s \(flag) flag is on, so its relay opens again before it links, and the Insteon device catalog doesn't let linking change the flag. Nothing was changed. Turn \(flag) off, link, then turn it back on."
    case let .flagUnreadable(device, flag):
      "\(device)'s reply to Get Operating Flags didn't carry its \(flag) flag. Nothing was changed."
    case let .flagNotChanged(device, flag, isSet):
      "\(device)'s \(flag) flag didn't read back \(isSet ? "on" : "off") after it was written."
    case let .relayNotConfirmed(device, requested):
      "\(device)'s relay didn't read back \(requested.rawValue), so it would record the wrong state. Nothing was linked."
    case let .remoteLinkingFailed(device, reason):
      "\(device) didn't link without its SET button: \(Self.message(reason)) It isn't linked with its SET button instead, since that records whatever state the relay is in by then. No link was reported."
    case let .recordedOtherState(device, group, data1, requested):
      "\(device)'s responder record for group \(group.rawValue) holds Data 1 \(Self.hex(data1)), not \(Self.hex(requested.data1)) for \(requested.rawValue), so a group On doesn't set the relay \(requested.rawValue). The link stays made; link it again with the relay state."
    case let .recordNotFound(device, group):
      "\(device)'s ALL-Link database holds no responder record of the modem for group \(group.rawValue), so the state it recorded isn't known."
    case let .recordNotRead(device, reason):
      "\(device)'s ALL-Link database couldn't be read to check the state it recorded: \(Self.message(reason))"
    case let .relayNotReturned(device, state, reason):
      "\(device)'s relay wasn't switched \(state.rawValue): \(Self.message(reason)) It may be left \(state.opposite.rawValue)."
    case let .planChanged(old, new):
      "\(old.device) changed since the plan was shown: \(Self.difference(old, new)). Nothing was changed; plan the link again."
    case let .relayReturnUnconfirmed(device, state, reason):
      "\(device)'s status couldn't be read after linking stopped: \(Self.message(reason)) Its relay was switched \(state.rawValue), as it was before, without knowing whether someone had switched it since."
    case let .flagNotRestored(device, flag, reason):
      "\(device)'s \(flag) flag wasn't set back on: \(Self.message(reason))"
    case let .flagRestoreUnconfirmed(device, flag, reason):
      "\(device)'s \(flag) flag was written back on, but it couldn't be read back to confirm: \(Self.message(reason))"
    case let .otherFlagsChanged(device, before, after):
      "\(device)'s operating flags read \(Self.hex(after)) after linking, not \(Self.hex(before)) as before, so a flag besides the one linking changed did too."
    case let .recordInPlace(device, group, data1):
      "\(device) already has a responder record of the modem for group \(group.rawValue) with Data 1 \(Self.hex(data1)), another state, and a database link leaves records in place as they are. Nothing was written; unlink it first."
    }

  }

  /// The same text as the error's `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

  /// A byte as `0x` and two uppercase hexadecimal digits.
  private static func hex(_ byte: UInt8) -> String {

    String(format: "0x%02X", byte)

  }

  /// An underlying error's sentence, ending with a period.
  private static func message(_ error: any Error) -> String {

    InsteonErrorDescription.message(for: error) ?? error.localizedDescription

  }

  /// How a relay's plan read again differs from the one approved, as a clause.
  private static func difference(_ old: RelayLinkPlan, _ new: RelayLinkPlan) -> String {

    var parts: [String] = []

    if old.before != new.before {

      parts.append("its relay reads \(new.before.rawValue), not \(old.before.rawValue)")

    }

    if old.isMomentary != new.isMomentary {

      parts.append("its momentary flag is \(new.isMomentary ? "on" : "off")")

    }

    if old.pulsesOnBothCommands != new.pulsesOnBothCommands {

      parts.append("its momentaryOnBothCommands flag is \(new.pulsesOnBothCommands ? "on" : "off")")

    }

    return parts.isEmpty ? "the plan is for another relay or state" : parts.joined(separator: ", and ")

  }

  /// Why a device didn't report its identity, as a clause.
  private static func why(_ reason: UnidentifiedReason) -> String {

    switch reason {
    case .notLinked:
      return ", since it rejects the modem until it's linked"
    case .noIdentity:
      return " in time"
    case let .failed(error):
      return " (\(message(error)))"
    }

  }

}
