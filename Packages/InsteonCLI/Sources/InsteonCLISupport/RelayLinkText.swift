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
        "\(device)'s relay is momentary with its momentaryOnBothCommands flag on, so every On and Off only pulses it and the state is ignored.",
        "  1. Link it. The relay isn't switched and no flag is written."
      ]

    }

    if plan.leavesUnverifiedMode {

      return [
        "\(device)'s momentaryOnBothCommands flag is on though its relay isn't momentary, a mode whose effect isn't verified, so the relay isn't switched.",
        "  1. Link it. No flag is written; its record holds \(plan.before.rawValue), the state the relay is in, "
          + "so a group On turns the relay \(plan.before.rawValue) and a group Off turns it \(plan.before.opposite.rawValue)."
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

  /// What `insteon link --relay-state` does once it has shown the plan.
  public enum Decision: Hashable, Sendable {

    /// Only show the plan, as `--dry-run` asks.
    case dryRun

    /// Stop: the person didn't agree to switching the relay.
    case declined

    /// Link as the plan says.
    case link

  }

  /// Decides what to do with a plan once it's shown: a dry run stops there, a plan that
  /// switches the relay is asked about when `asks` is `true`, and anything else links.
  ///
  /// - Parameters:
  ///   - plan: The plan.
  ///   - isDryRun: Whether `--dry-run` was given.
  ///   - asks: Whether to ask before switching, as ``DatabaseWriteOptions/asksForConfirmation(readsFromTerminal:subcommand:)`` says.
  ///   - confirm: Asks a person a question, and returns whether they agreed.
  /// - Returns: What to do.
  public static func decision(_ plan: RelayLinkPlan, isDryRun: Bool, asks: Bool, confirm: (String) async throws -> Bool) async throws -> Decision {

    if isDryRun {

      return .dryRun

    }

    if asks, let question = question(plan) {

      return try await confirm(question) ? .link : .declined

    }

    return .link

  }

  /// A plan as `--json` prints it for a dry run.
  public struct Report: Encodable, Hashable, Sendable {

    /// The relay's address.
    public var device: String

    /// The state asked for, `"on"` or `"off"`.
    public var state: String

    /// The relay's state before the link, as its status read.
    public var before: String

    /// Whether its momentary flag is on.
    public var isMomentary: Bool

    /// Whether its momentaryOnBothCommands flag is on.
    public var pulsesOnBothCommands: Bool

    /// Whether the relay is switched.
    public var switchesRelay: Bool

    /// The flag turned off for the link, or `nil`.
    public var clearedFlag: String?

    /// Whether a momentary relay switched on is switched off after the link.
    public var opensAfterLinking: Bool

    /// Whether a relay that isn't momentary is switched back when linking fails.
    public var switchesBackOnFailure: Bool

    /// Whether the state is ignored, on a momentary relay with momentaryOnBothCommands on.
    public var ignoresState: Bool

    /// Whether momentaryOnBothCommands is on though the relay isn't momentary.
    public var leavesUnverifiedMode: Bool

    /// Whether the plan was only shown.
    public var dryRun: Bool

  }

  /// A plan as `--json` prints it.
  ///
  /// - Parameters:
  ///   - plan: The plan.
  ///   - isDryRun: Whether it was only shown.
  /// - Returns: The report.
  public static func report(_ plan: RelayLinkPlan, isDryRun: Bool) -> Report {

    Report(
      device: "\(plan.device)",
      state: plan.state.rawValue,
      before: plan.before.rawValue,
      isMomentary: plan.isMomentary,
      pulsesOnBothCommands: plan.pulsesOnBothCommands,
      switchesRelay: plan.switchesRelay,
      clearedFlag: plan.clearedFlag,
      opensAfterLinking: plan.opensAfterLinking,
      switchesBackOnFailure: plan.switchesBackOnFailure,
      ignoresState: plan.ignoresState,
      leavesUnverifiedMode: plan.leavesUnverifiedMode,
      dryRun: isDryRun
    )

  }

  /// What's printed when the person doesn't confirm.
  public static let declined: String = "Nothing was switched or linked."

  /// What's printed after a dry run's plan.
  public static let dryRun: String = "Dry run: nothing was switched or linked."

}
