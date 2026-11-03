import InsteonCore

/// What `insteon link ADDRESS --relay-state on|off` shows and asks before it switches the
/// relay, and whatever it controls.
public enum RelayLinkText {

  /// The plan, a line each: what the link records, then each step, numbered.
  ///
  /// - Parameter plan: The plan.
  /// - Returns: The lines.
  public static func plan(_ plan: RelayLinkPlan) -> [String] {

    let device: InsteonAddress = plan.device
    let state: String = plan.state.rawValue
    var steps: [String] = []

    if plan.ignoresState {

      return [
        "\(device)'s momentaryOnBothCommands flag is on, so every On and Off only pulses the relay and the state is ignored.",
        "  1. Link it. The relay isn't switched and no flag is written."
      ]

    }

    if let flag = plan.clearedFlag {

      steps.append("Turn its \(flag) flag off for the link, so the relay holds its state.")

    }

    if plan.switchesRelay {

      steps.append("Turn the relay \(state). Whatever it controls, such as a garage door opener, a lock or a valve, acts on it.")

    }

    if let flag = plan.clearedFlag {

      steps.append(
        plan.opensAfterLinking
          ? "Link it, then turn the relay off again, since a momentary relay rests open, and turn its \(flag) flag back on."
          : "Link it, then turn its \(flag) flag back on."
      )

    } else if plan.switchesBackOnFailure {

      steps.append("Link it. The relay stays \(state), and is turned back \(plan.before.rawValue) if linking fails or is stopped.")

    } else {

      steps.append("Link it. The relay is already \(state), so it isn't switched.")

    }

    let heading: String = "Linking \(device) so a group On turns its relay \(plan.state.rawValue) and a group Off turns it \(plan.state.opposite.rawValue):"

    return [heading] + steps.enumerated().map { (step: (offset: Int, element: String)) -> String in "  \(step.offset + 1). \(step.element)" }

  }

  /// The question asked before the relay is switched, or `nil` when the plan doesn't switch
  /// it.
  ///
  /// - Parameter plan: The plan.
  /// - Returns: The question, ending with `[y/N]`.
  public static func question(_ plan: RelayLinkPlan) -> String? {

    guard plan.switchesRelay else {

      return nil

    }

    return "Switch \(plan.device)'s relay \(plan.state.rawValue) and link it? [y/N]"

  }

  /// What's printed when the person doesn't confirm.
  public static let declined: String = "Nothing was switched or linked."

  /// What's printed after a dry run's plan.
  public static let dryRun: String = "Dry run: nothing was switched or linked."

}
