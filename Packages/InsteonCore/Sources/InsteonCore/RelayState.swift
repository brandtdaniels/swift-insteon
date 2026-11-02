import Foundation
import InsteonProtocol

/// The state a relay records when it links as a responder, such as an I/O Linc's: what a
/// group On from its controller then sets it to. A group Off sets it to the opposite.
///
/// A relay keeps its state at link time as Data 1 of its responder record: `0xFF` when it was
/// on, and `0x00` when it was off. ``DeviceLinkingCoordinator`` puts the relay in the state
/// before it links, and ``DeviceLinkingCoordinator/planDatabaseLink(_:relayState:)`` writes
/// the byte directly.
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

/// What a relay linked with a chosen ``RelayState`` does when its controller's group command
/// arrives, and whether the operating flag linking changed went back as it was.
public struct RelayStateLink: Sendable {

  /// The relay.
  public var device: InsteonAddress

  /// The state the relay recorded.
  public var state: RelayState

  /// Whether the relay is momentary, as its momentary operating flag is after the link. A
  /// momentary relay closes only for its momentary time, so the state it holds lasts only that
  /// long.
  public var isMomentary: Bool

  /// Whether both On and Off close the momentary relay, as its momentaryOnBothCommands flag
  /// says. The relay then only pulses, so the recorded state isn't used while it's momentary.
  public var pulsesOnBothCommands: Bool

  /// Why the operating flag linking cleared wasn't set back as it was, as
  /// ``RelayStateLinkingError/flagNotRestored(_:flag:reason:)``, or `nil` when it was, or none
  /// was cleared. The link stays made.
  public var restoreFailure: (any Error)?

  /// What a group On sets the relay to: the recorded state.
  public var groupOn: RelayState {

    state

  }

  /// What a group Off sets the relay to: the opposite of the recorded state.
  public var groupOff: RelayState {

    state.opposite

  }

  /// Creates what a relay linked with a state does.
  ///
  /// - Parameters:
  ///   - device: The relay.
  ///   - state: The state it recorded.
  ///   - isMomentary: Whether it's momentary after the link.
  ///   - pulsesOnBothCommands: Whether both On and Off close its momentary relay.
  ///   - restoreFailure: Why the flag linking cleared wasn't set back, or `nil`. Defaults to
  ///     `nil`.
  public init(device: InsteonAddress, state: RelayState, isMomentary: Bool, pulsesOnBothCommands: Bool, restoreFailure: (any Error)? = nil) {

    self.device = device
    self.state = state
    self.isMomentary = isMomentary
    self.pulsesOnBothCommands = pulsesOnBothCommands
    self.restoreFailure = restoreFailure

  }

}

/// What a ``DeviceLinkingCoordinator`` did to put a relay in a chosen state before it linked,
/// and to set back the operating flag it changed for that.
public enum RelayStateEvent: Sendable {

  /// The relay's flag, such as `momentary`, is on, and it's being turned off for the link, so
  /// the relay holds its state rather than opening again.
  case clearingFlag(InsteonAddress, flag: String)

  /// The relay is being sent Light On or Light Off for the state.
  case settingRelay(InsteonAddress, RelayState)

  /// The relay's status showed it already in the state, so it wasn't sent a command.
  case relayAlreadySet(InsteonAddress, RelayState)

  /// The relay's status, read again, showed it in the state.
  case relayConfirmed(InsteonAddress, RelayState)

  /// The flag cleared for the link is being set back as it was: after the link, or after a
  /// failure or cancellation.
  case restoringFlag(InsteonAddress, flag: String)

  /// The flag read back as it was before the link.
  case flagRestored(InsteonAddress, flag: String)

  /// The flag wasn't set back as it was, for the reason given, so the relay keeps it off until
  /// it's changed by hand.
  case flagNotRestored(InsteonAddress, flag: String, reason: any Error)

  /// The relay linked with the state: what a group On and a group Off do to it.
  case recorded(RelayStateLink)

}

/// Why a relay wasn't linked with a chosen ``RelayState``.
///
/// Every refusal comes before the relay is sent a command or its flags are written, apart from
/// ``RelayStateLinkingError/relayNotConfirmed(_:requested:)`` and
/// ``RelayStateLinkingError/flagNotChanged(_:flag:isSet:)``, after which the flag is set back
/// as it was. ``RelayStateLinkingError/flagNotRestored(_:flag:reason:)`` is reported, not
/// thrown.
public enum RelayStateLinkingError: Error, Sendable {

  /// The modem isn't the controller, so the device doesn't respond in the link and records no
  /// state.
  case modemNotController(InsteonAddress)

  /// The device didn't report an identity the Insteon device catalog describes, so whether its
  /// main group is a relay isn't known.
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

  /// The flag cleared for the link wasn't set back as it was, for the reason given.
  case flagNotRestored(InsteonAddress, flag: String, reason: any Error)

  /// The device already has a responder record of the modem in the group with another state
  /// as Data 1, and a database link leaves records in place as they are.
  case recordInPlace(InsteonAddress, group: AllLinkGroupNumber, data1: UInt8)

}

extension RelayStateLinkingError: CustomStringConvertible, LocalizedError {

  /// A one-line explanation of the error.
  public var description: String {

    switch self {
    case let .modemNotController(device):
      "\(device) records a relay state only as a responder, so the modem must be the controller. Nothing was changed."
    case let .notDescribed(device):
      "\(device) didn't report an identity the Insteon device catalog describes, so whether its main group is a relay isn't known. Nothing was changed."
    case let .notARelay(device, product):
      "\(device), \(product), isn't a relay by the Insteon device catalog, so it records no relay state. Nothing was changed."
    case let .momentaryNotChangeable(device, flag):
      "\(device)'s \(flag) flag is on, so its relay opens again before it links, and the Insteon device catalog doesn't let linking change the flag. Nothing was changed. Turn \(flag) off, link, then turn it on again."
    case let .flagUnreadable(device, flag):
      "\(device)'s reply to Get Operating Flags didn't carry its \(flag) flag. Nothing was linked."
    case let .flagNotChanged(device, flag, isSet):
      "\(device)'s \(flag) flag didn't read back \(isSet ? "on" : "off") after it was written. Nothing was linked."
    case let .relayNotConfirmed(device, requested):
      "\(device)'s relay didn't read back \(requested.rawValue), so it would record the wrong state. Nothing was linked."
    case let .flagNotRestored(device, flag, reason):
      "\(device)'s \(flag) flag wasn't set back as it was: \(InsteonErrorDescription.message(for: reason) ?? reason.localizedDescription) Set it by hand."
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

}
