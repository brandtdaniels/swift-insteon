import InsteonDeviceCatalog
import InsteonProtocol

/// What `insteon link` and `insteon unlink` tell the person to do, and in which order.
///
/// The controller of a link goes first. When the modem is the controller, it enters linking
/// or unlinking mode, then the person presses the device's SET button. When the modem is the
/// responder, the device is the controller, so the person puts it into its mode first, then
/// the modem joins, as Insteon's own steps say.
public enum LinkingInstructions {

  /// Whether a link is being made or removed.
  public enum Mode: Hashable, Sendable {

    /// A link is being made.
    case linking

    /// A link is being removed.
    case unlinking

  }

  /// The steps of one of a device's procedures that are done on the device itself, each with
  /// what the device does in answer, such as
  /// `"Press and hold the SET button until the module beeps. [LED blinks green]"`.
  ///
  /// - Parameter procedure: The procedure, such as the profile's lifecycle `linking`.
  /// - Returns: The steps, in order.
  public static func steps(of procedure: DeviceLifecycle.Procedure) -> [String] {

    procedure.steps.filter { !$0.isOnOtherDevice }.map { step in

      step.expectation.map { "\(step.text) [\($0)]" } ?? step.text

    }

  }

  /// A device's address, then its product's name and model in parentheses when the catalog
  /// has its profile, such as `"1A.2B.3C (Dimmer Switch 2477D)"`, to name it in a sentence.
  ///
  /// The product's alias is left out, so the parentheses don't nest.
  ///
  /// - Parameters:
  ///   - device: The device's address.
  ///   - profile: The catalog's profile for the device, or `nil` if it isn't known.
  /// - Returns: The label.
  public static func deviceLabel(_ device: InsteonAddress, profile: DeviceProfile?) -> String {

    guard let profile else {

      return "\(device)"

    }

    return "\(device) (\(profile.name) \(profile.model))"

  }

  /// What to tell the person before the modem joins a device as its responder: put the
  /// device into its mode first, then press Return.
  ///
  /// - Parameters:
  ///   - mode: Whether the device is to link or unlink.
  ///   - device: The device, as ``deviceLabel(_:profile:)`` writes it, such as
  ///     `"1A.2B.3C (Dimmer Switch 2477D)"`, or `nil` for any device.
  ///   - steps: The device's own steps for the mode, from ``steps(of:)``, or empty if the
  ///     catalog doesn't have them.
  ///   - waitsForReturn: Whether the command waits for Return before starting the modem,
  ///     which it does when it reads from a terminal.
  /// - Returns: The lines, in order.
  public static func deviceFirst(_ mode: Mode, device: String?, steps: [String], waitsForReturn: Bool) -> [String] {

    let target = device ?? "the device"
    var lines: [String]

    switch (mode, steps.isEmpty) {
    case (.linking, true):
      lines = ["First put \(target) into linking mode: press and hold its SET button until it beeps or its light blinks."]
    case (.unlinking, true):
      lines = [
        "First put \(target) into unlinking mode. On most devices, press and hold the SET button until it beeps, "
          + "then press and hold it again until it beeps again; the device's manual has its steps."
      ]
    case (.linking, false), (.unlinking, false):
      lines = ["First put \(target) into \(mode == .linking ? "linking" : "unlinking") mode:"]
      lines += steps.enumerated().map { "  \($0.offset + 1). \($0.element)" }
    }

    lines.append(
      waitsForReturn
        ? "Then press Return, and the modem joins as its responder."
        : "The modem joins as its responder now."
    )

    return lines

  }

  /// What to tell the person once the modem, as the controller, is in its mode: press the
  /// device's SET button.
  ///
  /// - Parameters:
  ///   - mode: Whether the modem is linking or unlinking.
  ///   - group: The modem's group.
  ///   - seconds: How long the command waits.
  ///   - device: The device, or `nil` for any device.
  ///   - steps: The device's own steps to link, from ``steps(of:)``, or empty if the catalog
  ///     doesn't have them. A responder unlinks with its linking steps too.
  /// - Returns: The lines, in order.
  public static func modemFirst(_ mode: Mode, group: AllLinkGroupNumber, seconds: Int64, device: String?, steps: [String]) -> [String] {

    let target = device ?? "the device"
    let modemMode = mode == .linking ? "linking" : "unlinking"
    var lines = ["The modem is in \(modemMode) mode for group \(group)."]

    if steps.isEmpty {

      lines.append("Now press and hold the SET button of \(target) until it beeps or its light blinks.")

    } else {

      lines.append("Now, on \(target):")
      lines += steps.enumerated().map { "  \($0.offset + 1). \($0.element)" }

    }

    lines.append("Waiting up to \(seconds) seconds; Control-C stops.")

    return lines

  }

}

/// Explains a link the modem reported that isn't the one asked for.
public enum LinkOutcome {

  /// Why a link the modem reported isn't the one asked for, or `nil` if it is.
  ///
  /// - Parameters:
  ///   - link: The modem's report.
  ///   - mode: Whether a link was being made or removed.
  ///   - device: The device asked for, or `nil` for any device.
  /// - Returns: A message that says what happened and what to do, or `nil` if the link is the
  ///   one asked for.
  public static func mismatch(_ link: AllLinkingCompleted, mode: LinkingInstructions.Mode, device: InsteonAddress?) -> String? {

    if let device, link.address != device {

      let change = link.mode == .delete ? "removed its link" : "linked"

      return "The modem reported \(link.address), not \(device): another device's SET button was pressed, "
        + "and the modem \(change) with it in group \(link.group). Run the command again for \(device)."

    }

    switch (mode, link.mode == .delete) {
    case (.unlinking, false):
      return "\(link.address) linked again in group \(link.group) instead of unlinking: it was in linking mode, not unlinking mode. "
        + "Put it into unlinking mode (on most devices, hold its SET button until it beeps, then hold it again until it beeps again) "
        + "and run the command again."
    case (.linking, true):
      return "\(link.address) removed its link in group \(link.group) instead of linking: it was in unlinking mode, not linking mode. "
        + "Run the command again, and hold its SET button only until it first beeps."
    default:
      return nil
    }

  }

}
