import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

/// What `insteon transfer apply` takes, asks and prints.
@Suite(.timeLimit(.minutes(1)))
struct TransferApplyTests {

  // MARK: - Arguments

  @Test func readsTheFileAndItsFlags() throws {

    let subcommand = try Invocation.parse(["transfer", "apply", "home.json", "--merge", "--keep-going", "--yes", "--dry-run"]).subcommand

    #expect(subcommand == .transferApply(TransferApplyOptions(plan: TransferPlanOptions(path: "home.json", existingLinks: .merge), keepsGoing: true, assumesYes: true, isDryRun: true)))

  }

  @Test func takesForceForReplacingTheDatabase() throws {

    let subcommand = try Invocation.parse(["transfer", "apply", "--replace-database", "--force", "home.json"]).subcommand

    #expect(subcommand == .transferApply(TransferApplyOptions(plan: TransferPlanOptions(path: "home.json", existingLinks: .replaceDatabase), isForced: true)))

  }

  @Test func refusesOptionsThatBelongToPlanAlone() {

    #expect(throws: ArgumentError.self) { try Invocation.parse(["transfer", "plan", "home.json", "--keep-going"]) }
    #expect(throws: ArgumentError.missingArgument("FILE", subcommand: "transfer apply")) { try Invocation.parse(["transfer", "apply"]) }
    #expect(throws: ArgumentError.conflictingOptions("--merge", "--replace-database")) { try Invocation.parse(["transfer", "apply", "home.json", "--merge", "--replace-database"]) }

  }

  @Test func helpDescribesApply() {

    let text = HelpText.text(for: "transfer") ?? ""

    #expect(text.contains("transfer apply FILE"))
    #expect(text.contains("--keep-going"))

  }

  @Test func askingNeedsATerminalUnlessYesOrDryRun() throws {

    let plain = TransferApplyOptions(plan: TransferPlanOptions(path: "home.json"))

    #expect(try plain.asksForConfirmation(readsFromTerminal: true))
    #expect(throws: ArgumentError.confirmationNeeded(subcommand: "transfer apply")) { try plain.asksForConfirmation(readsFromTerminal: false) }
    #expect(try !TransferApplyOptions(plan: plain.plan, assumesYes: true).asksForConfirmation(readsFromTerminal: false))
    #expect(try !TransferApplyOptions(plan: plain.plan, isDryRun: true).asksForConfirmation(readsFromTerminal: false))

  }

  // MARK: - The decision

  static let options = TransferApplyOptions(plan: TransferPlanOptions(path: "home.json"))

  @Test func writesAfterOneYesPerClassOfStepItAsksAbout() async throws {

    let plan = try TransferPlanTextTests.plan()
    var questions: [String] = []
    let decision = try await TransferApplyText.decision(plan, options: Self.options, asks: true) { question in questions.append(question); return true }

    #expect(decision == .write)
    #expect(questions.count == 1)
    #expect(questions[0].contains("link"))

  }

  @Test func stopsWhenAnyAnswerIsNo() async throws {

    let decision = try await TransferApplyText.decision(try TransferPlanTextTests.plan(), options: Self.options, asks: true) { _ in false }

    #expect(decision == .declined)

  }

  @Test func asksNothingWithYes() async throws {

    let decision = try await TransferApplyText.decision(try TransferPlanTextTests.plan(), options: Self.options, asks: false) { _ in Issue.record("asked"); return false }

    #expect(decision == .write)

  }

  @Test func showsTheDryRunAndWritesNothing() async throws {

    let dry = TransferApplyOptions(plan: Self.options.plan, isDryRun: true)
    let decision = try await TransferApplyText.decision(try TransferPlanTextTests.plan(), options: dry, asks: false) { _ in true }

    #expect(decision == .dryRun)

  }

  @Test func needsForceToRemoveTheModemsLinksAndAsksForThemSeparately() async throws {

    let existing = [TransferPlanTextTests.record(.controller, group: 4, TransferPlanTextTests.plug)]
    let plan = try TransferPlanTextTests.plan(existing, .replaceDatabase)
    let replace = TransferApplyOptions(plan: TransferPlanOptions(path: "home.json", existingLinks: .replaceDatabase))
    let unforced = try await TransferApplyText.decision(plan, options: replace, asks: false) { _ in true }
    var questions: [String] = []
    let forced = try await TransferApplyText.decision(plan, options: TransferApplyOptions(plan: replace.plan, isForced: true), asks: true) { question in questions.append(question); return true }

    #expect(unforced == .needsForce)
    #expect(forced == .write)
    #expect(questions.count == 2)
    #expect(questions[0].contains("destructive"))

  }

  @Test func hasNothingToWriteWhenThePlanHasOnlyReads() async throws {

    let empty = try TransferPlanner.plan(
      from: HomeBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .modem, modem: BackupModem(address: TransferPlanTextTests.old, allLinkDatabase: []), devices: []),
      to: TransferTarget(address: TransferPlanTextTests.new, records: [])
    )
    let decision = try await TransferApplyText.decision(empty, options: Self.options, asks: true) { _ in Issue.record("asked"); return true }

    #expect(decision == .nothingToWrite)

  }

  // MARK: - The report

  @Test func sayingEachStepAsItIsMade() throws {

    let plan = try TransferPlanTextTests.plan()
    let step = try #require(plan.steps.first { $0.action == .rewriteRecord })

    #expect(TransferApplyText.line(step, .written) == "Step \(step.number): \(step.summary) Written.")

  }

  @Test func summarizesACompleteRunAndAPartialOne() throws {

    let plan = try TransferPlanTextTests.plan()
    let done = TransferReport(newModem: plan.newModem, results: plan.steps.map { TransferStepResult(step: $0, outcome: .written) })
    var failing = done

    failing.results[plan.steps.count - 2].outcome = .unanswered
    failing.results[plan.steps.count - 1].outcome = .notReached

    #expect(TransferApplyText.summary(done, plan: plan).first == "Done: every step of the plan was made.")
    let partial = TransferApplyText.summary(failing, plan: plan)
    #expect(partial.contains { $0.contains("wasn't confirmed") })
    #expect(partial.contains { $0.contains(plan.steps[plan.steps.count - 2].target.description) })

  }

}
