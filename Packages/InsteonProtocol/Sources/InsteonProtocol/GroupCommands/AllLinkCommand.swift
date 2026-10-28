/// The commands the Developer's Guide defines for ALL-Link broadcasts and cleanups.
///
/// ALL-Link Recall is the one every responder carries out: it returns to the state it saved
/// when it was linked. The others are alias commands, which a responder ignores unless it has a
/// substitute direct command for them, either built in or set with
/// ``AllLinkCommandAlias``. Lighting controls, device categories `0x01` and `0x02`, have the
/// built-in substitutes in ``AllLinkCommand/lightingSubstitute``, so older controllers use the
/// aliases as Light On, Light Off and the rest.
///
/// A toggle button, or a pair of buttons, sends a high-state command and its low-state partner
/// for one group: most often ALL-Link Recall for on and ALL-Link Alias 1 Low for off.
///
/// ```swift
/// if let command = GroupCommand(message), command.allLinkCommand == .alias1Low {
///   print("Group \(command.group) turned off")
/// }
/// ```
public enum AllLinkCommand: UInt8, Hashable, Sendable, CaseIterable {

  /// ALL-Link Recall (cmd1 `0x11`): each responder returns to the state it saved when it was
  /// linked, such as a light going to its on-level at its ramp rate.
  case recall = 0x11

  /// ALL-Link Alias 2 High (cmd1 `0x12`). Lighting controls default to Light On Fast.
  case alias2High = 0x12

  /// ALL-Link Alias 1 Low (cmd1 `0x13`). Lighting controls default to Light Off.
  case alias1Low = 0x13

  /// ALL-Link Alias 2 Low (cmd1 `0x14`). Lighting controls default to Light Off Fast.
  case alias2Low = 0x14

  /// ALL-Link Alias 3 High (cmd1 `0x15`). Lighting controls default to Light Brighten One Step.
  case alias3High = 0x15

  /// ALL-Link Alias 3 Low (cmd1 `0x16`). Lighting controls default to Light Dim One Step.
  case alias3Low = 0x16

  /// ALL-Link Alias 4 High (cmd1 `0x17`). Lighting controls default to Light Start Manual
  /// Change.
  ///
  /// Some legacy controllers, the ControLinc, SwitchLinc and KeypadLinc V2, put a direction in
  /// the broadcast's cmd2, `0x01` to brighten and `0x00` to dim, and send no cleanups after it.
  case alias4High = 0x17

  /// ALL-Link Alias 4 Low (cmd1 `0x18`). Lighting controls default to Light Stop Manual Change.
  ///
  /// Some legacy controllers, the ControLinc, SwitchLinc and KeypadLinc V2, send no cleanups
  /// after it.
  case alias4Low = 0x18

  /// ALL-Link Alias 5 (cmd1 `0x21`). Lighting controls default to Light Instant Change, which
  /// goes to the on-level in their ALL-Link database at the next zero crossing.
  case alias5 = 0x21

  /// The state a toggle or paired button sends a command for.
  public enum ButtonState: Hashable, Sendable {

    /// Toggled on, or the first button of a pair.
    case high

    /// Toggled off, or the second button of a pair.
    case low

  }

  /// The state a toggle or paired button sends the command for, or `nil` for
  /// ``AllLinkCommand/alias5``, which has no partner.
  public var buttonState: ButtonState? {

    switch self {
    case .recall, .alias2High, .alias3High, .alias4High:
      .high
    case .alias1Low, .alias2Low, .alias3Low, .alias4Low:
      .low
    case .alias5:
      nil
    }

  }

  /// The command a toggle or paired button sends for the other state, such as
  /// ``AllLinkCommand/alias1Low`` for ``AllLinkCommand/recall``, or `nil` for
  /// ``AllLinkCommand/alias5``.
  public var partner: AllLinkCommand? {

    switch self {
    case .recall:
      .alias1Low
    case .alias1Low:
      .recall
    case .alias2High:
      .alias2Low
    case .alias2Low:
      .alias2High
    case .alias3High:
      .alias3Low
    case .alias3Low:
      .alias3High
    case .alias4High:
      .alias4Low
    case .alias4Low:
      .alias4High
    case .alias5:
      nil
    }

  }

  /// The direct command a lighting control, device category `0x01` or `0x02`, carries out in
  /// place of the command unless it has been given another, or `nil` for
  /// ``AllLinkCommand/recall``, which never has a substitute.
  ///
  /// The Developer's Guide lists Light Dim One Step's bytes as `0x1500` in its ALL-Link
  /// command table, the same as Light Brighten One Step's; its table of default substitutes
  /// names Light Dim One Step, which is cmd1 `0x16`.
  public var lightingSubstitute: Command? {

    switch self {
    case .recall:
      nil
    case .alias1Low:
      StandardDirectCommand.off.command
    case .alias2High:
      Command(command1: 0x12)
    case .alias2Low:
      StandardDirectCommand.fastOff.command
    case .alias3High:
      StandardDirectCommand.brightenOneStep.command
    case .alias3Low:
      StandardDirectCommand.dimOneStep.command
    case .alias4High:
      Command(command1: 0x17)
    case .alias4Low:
      StandardDirectCommand.stopManualChange.command
    case .alias5:
      Command(command1: 0x21)
    }

  }

}

// MARK: - Group commands

extension GroupCommand {

  /// The ALL-Link command the controller sent, or `nil` if cmd1 is one the Developer's Guide
  /// doesn't define for ALL-Link messages, such as a sensor's or thermostat's own commands.
  public var allLinkCommand: AllLinkCommand? {

    AllLinkCommand(rawValue: command1)

  }

}
