import InsteonCore

/// What `insteon transfer apply` asks and says as it carries out a plan.
public enum TransferApplyText {

  /// What to do with a plan once it's shown.
  public enum Decision: Hashable, Sendable {

    /// Stop: the plan has no step that writes.
    case nothingToWrite

    /// Only show the plan, as `--dry-run` asks.
    case dryRun

    /// Stop: removing the modem's own links needs `--force`.
    case needsForce

    /// Stop: the person didn't agree to a kind of step.
    case declined

    /// Carry the plan out.
    case write

  }

  /// Decides what to do with a plan once it's shown.
  ///
  /// A plan with no writing step stops there, dry run or not, and a dry run stops there. Removing
  /// the modem's own links needs `--force`. When `asks` is `true`, the person is asked once for
  /// each kind of step the plan has, destructive first, and any answer but yes stops.
  ///
  /// - Parameters:
  ///   - plan: The plan.
  ///   - options: What was given on the command line.
  ///   - asks: Whether to ask before writing.
  ///   - confirm: Asks a person a question, and returns whether they agreed.
  /// - Returns: What to do.
  public static func decision(_ plan: TransferPlan, options: TransferApplyOptions, asks: Bool, confirm: (String) async throws -> Bool) async throws -> Decision {

    let counts: [TransferEffect: Int] = plan.stepCounts
    let destructive: Int = counts[.destructive] ?? 0
    let links: Int = counts[.link] ?? 0
    let configuration: Int = counts[.configuration] ?? 0

    guard destructive + links + configuration > 0 else {

      return .nothingToWrite

    }

    if options.isDryRun {

      return .dryRun

    }

    guard destructive == 0 || options.isForced else {

      return .needsForce

    }

    if asks {

      for (name, count, what) in [
        ("destructive", destructive, "remove \(destructive) of the modem's own links"),
        ("configuration", configuration, "change \(configuration) settings"),
        ("link", links, "write \(links) ALL-Link \(links == 1 ? "record" : "records")")
      ] where count > 0 {

        guard try await confirm("Carry out the \(name) steps, which \(what)? [y/N]") else {

          return .declined

        }

      }

    }

    return .write

  }

  /// The line said when a step has been made.
  ///
  /// - Parameters:
  ///   - step: The step.
  ///   - outcome: What became of it.
  /// - Returns: The line.
  public static func line(_ step: TransferStep, _ outcome: TransferOutcome) -> String {

    "Step \(step.number): \(step.summary) \(text(outcome))"

  }

  private static func text(_ outcome: TransferOutcome) -> String {

    switch outcome {
    case .written: "Written."
    case .writtenOnRetry: "Written on the second try."
    case .alreadyDone: "Already done."
    case .notWritten: "It didn't read back as written."
    case .unanswered: "It didn't answer, so it isn't known whether it was written. It isn't sent again."
    case .changedSincePlanned: "The record is neither the backup's nor the plan's, so it was left alone."
    case .notReached: "Not reached."
    }

  }

  /// What a run did, in lines: that it finished, or which devices it stopped at and what to do.
  ///
  /// - Parameters:
  ///   - report: The report.
  ///   - plan: The plan it carried out.
  /// - Returns: The lines.
  public static func summary(_ report: TransferReport, plan: TransferPlan) -> [String] {

    if report.isComplete {

      var lines: [String] = ["Done: every step of the plan was made."]

      if !plan.manual.isEmpty {

        lines.append("\(plan.manual.count) \(plan.manual.count == 1 ? "device is" : "devices are") left to link by hand, as the plan lists.")

      }

      return lines

    }

    var lines: [String] = []
    let modemFailed: Bool = report.results.contains { $0.step.target == report.newModem && !$0.outcome.isDone && $0.outcome != .notReached }

    if modemFailed {

      lines.append("The new modem's records weren't all made, so no device was touched after that.")

    }

    for device in report.failedDevices {

      let failed: [TransferStepResult] = report.results.filter { $0.step.target == device && !$0.outcome.isDone && $0.outcome != .notReached }

      lines.append("\(device) stopped: " + failed.map { text($0.outcome) }.joined(separator: " "))

    }

    let notReached: Int = report.results.filter { $0.outcome == .notReached }.count

    if notReached > 0 {

      lines.append("\(notReached) \(notReached == 1 ? "step was" : "steps were") not reached. Fix what stopped it and run the command again: it reads each record first and writes only what is left.")

    }

    return lines

  }

}
