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
    let cleared: [RelayFlag] = plan.clearedFlags
    var steps: [String] = []

    if plan.ignoresState {

      return [
        "\(device)'s \(RelayFlagText.are(plan.holding.pulsingFlags)) on, so every On and Off only pulses its relay and the state is ignored.",
        "  1. Link it. The relay isn't switched and no flag is written."
      ]

    }

    if !cleared.isEmpty {

      steps.append("Turn its \(RelayFlagText.named(cleared)) off for the link, so the relay holds its state.")

    }

    if plan.switchesRelay {

      steps.append("Turn the relay \(state). Whatever it controls, such as a garage door opener, a lock or a valve, acts on it.")

    }

    if !cleared.isEmpty {

      let rest: String = plan.holding.restState.rawValue

      steps.append(
        plan.returnsToRestAfterLinking
          ? "Link it, then turn the relay \(rest) again, since it returns to \(rest) by itself with \(cleared.count > 1 ? "those flags" : "that flag") on, "
            + "and turn its \(RelayFlagText.named(cleared)) back on."
          : "Link it, then turn its \(RelayFlagText.named(cleared)) back on."
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

    if !plan.clearedFlags.isEmpty {

      return "Turn off \(plan.device)'s \(RelayFlagText.named(plan.clearedFlags)), switch its relay \(plan.state.rawValue) and link it? [y/N]"

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

    /// The state the relay returns to by itself while a flag that keeps it from holding a
    /// state is on, `"on"` or `"off"`.
    public var restState: String

    /// The names of the flags the catalog gives for how the relay holds a state that read on.
    public var flagsOn: [String]

    /// The names of the flags that read on and keep the relay from holding a state.
    public var releasingFlags: [String]

    /// The names of the flags with which every On and Off only pulses the relay, when all of
    /// them read on; empty otherwise.
    public var pulsingFlags: [String]

    /// Whether the relay is switched.
    public var switchesRelay: Bool

    /// The names of the flags turned off for the link.
    public var clearedFlags: [String]

    /// Whether the relay is switched to its rest state right after the link.
    public var returnsToRestAfterLinking: Bool

    /// Whether a relay that holds a state is switched back when linking fails.
    public var switchesBackOnFailure: Bool

    /// Whether the state is ignored, since every On and Off only pulses the relay.
    public var ignoresState: Bool

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
      restState: plan.holding.restState.rawValue,
      flagsOn: plan.holding.flagsOn.map(\.name),
      releasingFlags: plan.holding.releasingFlags.map(\.name),
      pulsingFlags: plan.holding.pulsingFlags.map(\.name),
      switchesRelay: plan.switchesRelay,
      clearedFlags: plan.clearedFlags.map(\.name),
      returnsToRestAfterLinking: plan.returnsToRestAfterLinking,
      switchesBackOnFailure: plan.switchesBackOnFailure,
      ignoresState: plan.ignoresState,
      dryRun: isDryRun
    )

  }

  /// What's printed when the person doesn't confirm.
  public static let declined: String = "Nothing was switched or linked."

  /// What's printed after a dry run's plan.
  public static let dryRun: String = "Dry run: nothing was switched or linked."

}
