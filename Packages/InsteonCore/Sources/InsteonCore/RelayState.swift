import Foundation
import InsteonDeviceCatalog
import InsteonProtocol

/// The state a relay records when it links as a responder: what a group On from its
/// controller then sets it to. A group Off sets it to the opposite.
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

/// An operating flag the Insteon device catalog names in how a relay holds a state.
public struct RelayFlag: Hashable, Sendable {

  /// The flag's name in the device's command set, which a setting command takes.
  public var name: String

  /// What a person calls the flag: the catalog's label for it, or its name when the catalog
  /// gives none.
  public var label: String

  /// Creates a flag.
  ///
  /// - Parameters:
  ///   - name: The flag's name in the device's command set.
  ///   - label: What a person calls the flag.
  public init(name: String, label: String) {

    self.name = name
    self.label = label

  }

}

/// How a relay holds the state it's switched to, as the Insteon device catalog describes its
/// main group's type, with the flags it names that read on.
///
/// While a flag of ``RelayStateHolding/releasedBy`` is on, the relay doesn't hold a state: it
/// returns to ``RelayStateHolding/restState`` by itself a time after it's switched. While every
/// flag of one of ``RelayStateHolding/pulsesOnEveryCommandWhen`` is on, every group On and Off
/// only pulses it, whatever its responder record holds, so the state a link records is
/// ignored. Otherwise it holds the state it's switched to.
public struct RelayStateHolding: Hashable, Sendable {

  /// The names of the flags that keep the relay from holding a state while any is on.
  public var releasedBy: [String]

  /// The state the relay returns to by itself while a flag of
  /// ``RelayStateHolding/releasedBy`` is on.
  public var restState: RelayState

  /// Sets of flag names, each of which, when all its flags are on, has every On and Off only
  /// pulse the relay.
  public var pulsesOnEveryCommandWhen: [[String]]

  /// The flags the catalog names here that read on, in the catalog's order.
  public var flagsOn: [RelayFlag]

  /// Creates how a relay holds a state.
  ///
  /// - Parameters:
  ///   - releasedBy: The names of the flags that keep the relay from holding a state.
  ///   - restState: The state the relay returns to by itself.
  ///   - pulsesOnEveryCommandWhen: The sets of flag names with which every On and Off only
  ///     pulses the relay. Defaults to none.
  ///   - flagsOn: The flags that read on. Defaults to none.
  public init(releasedBy: [String], restState: RelayState, pulsesOnEveryCommandWhen: [[String]] = [], flagsOn: [RelayFlag] = []) {

    self.releasedBy = releasedBy
    self.restState = restState
    self.pulsesOnEveryCommandWhen = pulsesOnEveryCommandWhen
    self.flagsOn = flagsOn

  }

  /// The flags of ``RelayStateHolding/releasedBy`` that are on, which keep the relay from
  /// holding a state.
  public var releasingFlags: [RelayFlag] {

    flagsOn.filter { (flag: RelayFlag) -> Bool in releasedBy.contains(flag.name) }

  }

  /// The flags of the first set of ``RelayStateHolding/pulsesOnEveryCommandWhen`` whose flags
  /// are all on, with which every On and Off only pulses the relay, or none when no set is.
  public var pulsingFlags: [RelayFlag] {

    for set in pulsesOnEveryCommandWhen where !set.isEmpty {

      let flags: [RelayFlag] = set.compactMap { (name: String) -> RelayFlag? in flagsOn.first { (flag: RelayFlag) -> Bool in flag.name == name } }

      if flags.count == set.count {

        return flags

      }

    }

    return []

  }

  /// Whether the relay holds the state it's switched to: no flag that keeps it from holding
  /// one is on.
  public var holdsState: Bool {

    releasingFlags.isEmpty

  }

  /// Whether every On and Off only pulses the relay, so the state a link records is ignored.
  public var ignoresState: Bool {

    !pulsingFlags.isEmpty

  }

}

/// What linking a relay with a chosen ``RelayState`` switches and puts back, from how it holds
/// a state and its status, as
/// ``DeviceLinkingCoordinator/planRelayLink(_:recording:observer:)`` reads them, for a front end
/// to show and ask about before the relay, and whatever it controls, is switched.
public struct RelayLinkPlan: Hashable, Sendable {

  /// The relay.
  public var device: InsteonAddress

  /// The state it's to record.
  public var state: RelayState

  /// Its state before the link, as its status read.
  public var before: RelayState

  /// How it holds a state, with the flags that read on.
  public var holding: RelayStateHolding

  /// Creates a plan.
  ///
  /// - Parameters:
  ///   - device: The relay.
  ///   - state: The state it's to record.
  ///   - before: Its state before the link.
  ///   - holding: How it holds a state, with the flags that read on.
  public init(device: InsteonAddress, state: RelayState, before: RelayState, holding: RelayStateHolding) {

    self.device = device
    self.state = state
    self.before = before
    self.holding = holding

  }

  /// Whether the state is ignored, since every On and Off only pulses the relay. The relay
  /// isn't switched and no flag is written.
  public var ignoresState: Bool {

    holding.ignoresState

  }

  /// Whether the relay is switched to the state: when it isn't in it, or when it doesn't hold
  /// a state and the state isn't its rest state, since it reads another state only while it's
  /// switched, before it returns. Never when the state is ignored.
  public var switchesRelay: Bool {

    !ignoresState && (before != state || (!holding.holdsState && state != holding.restState))

  }

  /// The flags turned off for the link, so the relay holds its state: those that keep it from
  /// holding one, when it's switched.
  public var clearedFlags: [RelayFlag] {

    switchesRelay ? holding.releasingFlags : []

  }

  /// Whether the relay is switched to its rest state right after the link, while its flags
  /// are still off: when they were turned off and the state isn't its rest state.
  public var returnsToRestAfterLinking: Bool {

    !clearedFlags.isEmpty && state != holding.restState

  }

  /// Whether a relay that holds a state is switched back to its state before when linking
  /// fails or is canceled. Once linked, it keeps the state it recorded.
  public var switchesBackOnFailure: Bool {

    switchesRelay && holding.holdsState

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

  /// The flags turned off for the link. Empty when none was.
  public var clearedFlags: [RelayFlag]

  /// How the relay holds a state after the link. A flag turned off for the link is on only
  /// when it was confirmed back on.
  public var holding: RelayStateHolding

  /// What didn't go back as it was after the link, in order: the relay not returned to its
  /// rest state, a flag not set back or not confirmed, or another flag that changed. Empty
  /// when everything did.
  public var restoreFailures: [RelayStateLinkingError]

  /// Whether the state was ignored, since every On and Off only pulses the relay.
  public var ignoresState: Bool {

    holding.ignoresState

  }

  /// What a group On sets the relay to: the state asked for, or `nil` when the state was
  /// ignored.
  public var groupOn: RelayState? {

    ignoresState ? nil : state

  }

  /// What a group Off sets the relay to: the opposite of the state asked for, or `nil` when
  /// the state was ignored.
  public var groupOff: RelayState? {

    ignoresState ? nil : state.opposite

  }

  /// Whether the flags turned off for the link read back on afterward, or `nil` when none was
  /// turned off.
  public var isRestored: Bool? {

    guard !clearedFlags.isEmpty else {

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
  ///   - clearedFlags: The flags turned off for the link. Defaults to none.
  ///   - holding: How the relay holds a state after the link.
  ///   - restoreFailures: What didn't go back as it was. Defaults to none.
  public init(
    device: InsteonAddress,
    state: RelayState,
    group: AllLinkGroupNumber,
    recordedData1: UInt8?,
    recordFailure: RelayStateLinkingError? = nil,
    clearedFlags: [RelayFlag] = [],
    holding: RelayStateHolding,
    restoreFailures: [RelayStateLinkingError] = []
  ) {

    self.device = device
    self.state = state
    self.group = group
    self.recordedData1 = recordedData1
    self.recordFailure = recordFailure
    self.clearedFlags = clearedFlags
    self.holding = holding
    self.restoreFailures = restoreFailures

  }

}

/// What a ``DeviceLinkingCoordinator`` did to put a relay in a chosen state before it linked,
/// and to put back what it changed for that.
public enum RelayStateEvent: Sendable {

  /// The relay's flag is on, keeping it from holding a state, and it's being turned off for
  /// the link, so the relay holds its state rather than returning to its rest state.
  case clearingFlag(InsteonAddress, flag: RelayFlag)

  /// The relay is being sent its group type's On or Off for the state.
  case settingRelay(InsteonAddress, RelayState)

  /// The relay's status showed it already in the state, so it wasn't sent a command.
  case relayAlreadySet(InsteonAddress, RelayState)

  /// The relay's flags given are all on, so every On and Off only pulses it and the state is
  /// ignored: it's linked without being switched, and no flag is written.
  case linkedWithoutSwitching(InsteonAddress, flags: [RelayFlag])

  /// The relay's status reads the state given, not the one it was switched to, so it's left
  /// as it is rather than switched again.
  case relayLeft(InsteonAddress, reads: RelayState)

  /// The relay's status, read again, showed it in the state.
  case relayConfirmed(InsteonAddress, RelayState)

  /// The relay is being switched to the state given after the link: its rest state, for a
  /// relay switched out of it with its flags turned off, while they're still off; or its state
  /// before, for a relay that holds a state, when linking failed or was canceled.
  case returningRelay(InsteonAddress, RelayState)

  /// A flag turned off for the link is being turned back on: after the link, or after a
  /// failure or cancellation.
  case restoringFlag(InsteonAddress, flag: RelayFlag)

  /// The flag read back on.
  case flagRestored(InsteonAddress, flag: RelayFlag)

  /// Something didn't go back as it was, for the reason given.
  case restoreFailed(InsteonAddress, RelayStateLinkingError)

  /// The relay linked: what its record holds, what a group On and a group Off do to it, and
  /// what didn't go as asked.
  case recorded(RelayStateLink)

}

/// Why a relay wasn't linked with a chosen ``RelayState``, or what didn't go as asked once it
/// was.
///
/// The refusals come before the relay is switched or a flag is written, and change nothing:
/// ``notIdentified(_:because:)``, ``notLinkedToModem(_:)``, ``notDescribed(_:)``,
/// ``notARelay(_:product:)``, ``stateHoldingNotDescribed(_:product:)``,
/// ``flagNotChangeable(_:flag:)``, ``flagUnreadable(_:flag:)`` and ``planChanged(old:new:)``.
/// After
/// ``flagNotChanged(_:flag:isSet:)``, ``relayNotConfirmed(_:requested:)`` or
/// ``remoteLinkingFailed(_:reason:)``, what was changed is put back first, and what didn't go
/// back, such as ``relayNotReturned(_:state:reason:)`` or
/// ``relayReturnUnconfirmed(_:state:reason:)``, reaches the observer as
/// ``RelayStateEvent/restoreFailed(_:_:)``. Once the link is made, the rest are reported in a
/// ``RelayStateLink``, since the link stays made. ``recordInPlace(_:group:data1:)`` is the
/// database link's refusal, before anything is written.
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

  /// The catalog doesn't say how the relay holds a state, or names a flag or rest state for it
  /// that the device's command set doesn't give, so what a link would record isn't known. The
  /// associated values are the device and its product, as a sentence names it.
  case stateHoldingNotDescribed(InsteonAddress, product: String)

  /// The relay's flag is on, keeping it from holding a state, and the catalog doesn't let
  /// linking change it, or gives no command that turns it off and on, so the relay would
  /// return to its rest state before it links and record that.
  case flagNotChangeable(InsteonAddress, flag: RelayFlag)

  /// The device's reply to Get Operating Flags didn't carry the flag.
  case flagUnreadable(InsteonAddress, flag: RelayFlag)

  /// The flag didn't read back in the state it was written to.
  case flagNotChanged(InsteonAddress, flag: RelayFlag, isSet: Bool)

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

  /// The relay wasn't switched to the state given after the link, for the reason given: its
  /// rest state for a relay switched out of it with its flags turned off, or its state before
  /// for a relay that holds a state when linking failed. It may be left in the state it was
  /// switched to.
  case relayNotReturned(InsteonAddress, state: RelayState, reason: any Error)

  /// The relay, read again inside the link, isn't as the plan approved for it said, so the
  /// link would switch or put back other than it showed. Nothing was changed.
  case planChanged(old: RelayLinkPlan, new: RelayLinkPlan)

  /// The relay's status couldn't be read after linking failed, for the reason given, so it
  /// was switched back to the state given without knowing whether someone had switched it.
  case relayReturnUnconfirmed(InsteonAddress, state: RelayState, reason: any Error)

  /// A flag turned off for the link wasn't turned back on, twice, for the reason given.
  case flagNotRestored(InsteonAddress, flag: RelayFlag, reason: any Error)

  /// A flag turned off for the link was written back on, but couldn't be read back, twice,
  /// for the reason given, so it isn't confirmed.
  case flagRestoreUnconfirmed(InsteonAddress, flag: RelayFlag, reason: any Error)

  /// An operating flags byte a flag turned off for the link is in reads otherwise after the
  /// link than before it, so a flag besides those linking changed did too.
  case otherFlagsChanged(InsteonAddress, before: UInt8, after: UInt8)

  /// The device already has a responder record of the modem in the group with another state
  /// as Data 1, and a database link leaves records in place as they are.
  case recordInPlace(InsteonAddress, group: AllLinkGroupNumber, data1: UInt8)

  /// The device the error is about.
  public var device: InsteonAddress {

    switch self {
    case let .notIdentified(device, _), let .notLinkedToModem(device), let .notDescribed(device), let .notARelay(device, _),
      let .stateHoldingNotDescribed(device, _), let .flagNotChangeable(device, _), let .flagUnreadable(device, _), let .flagNotChanged(device, _, _),
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
    case let .stateHoldingNotDescribed(device, product):
      "The Insteon device catalog doesn't say how \(device)'s relay, \(product), holds a state, so what a link would record isn't known. Nothing was changed."
    case let .flagNotChangeable(device, flag):
      "\(device)'s \(flag.label) flag is on, so its relay doesn't hold a state and returns to its rest state before it links, and the Insteon device catalog doesn't let linking turn the flag off and on. Nothing was changed. Turn the flag off, link, then turn it back on."
    case let .flagUnreadable(device, flag):
      "\(device)'s reply to Get Operating Flags didn't carry its \(flag.label) flag. Nothing was changed."
    case let .flagNotChanged(device, flag, isSet):
      "\(device)'s \(flag.label) flag didn't read back \(isSet ? "on" : "off") after it was written."
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
      "\(device)'s \(flag.label) flag wasn't set back on: \(Self.message(reason))"
    case let .flagRestoreUnconfirmed(device, flag, reason):
      "\(device)'s \(flag.label) flag was written back on, but it couldn't be read back to confirm: \(Self.message(reason))"
    case let .otherFlagsChanged(device, before, after):
      "\(device)'s operating flags read \(Self.hex(after)) after linking, not \(Self.hex(before)) as before, so a flag besides those linking changed did too."
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

    // Each flag that reads on in one plan and not the other, in the order they were read.
    for flag in old.holding.flagsOn + new.holding.flagsOn {

      let isOn: Bool = new.holding.flagsOn.contains(flag)
      let clause: String = "its \(flag.label) flag is \(isOn ? "on" : "off")"

      if isOn != old.holding.flagsOn.contains(flag), !parts.contains(clause) {

        parts.append(clause)

      }

    }

    if parts.isEmpty, old.holding != new.holding {

      parts.append("the catalog says otherwise how its relay holds a state")

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
