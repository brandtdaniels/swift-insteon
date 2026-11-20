import Testing
import InsteonCLISupport
import InsteonCore

/// `insteon backup` and `insteon transfer plan` on the command line.
struct BackupArgumentTests {

  // MARK: - backup

  @Test func readsBackupWithItsFile() throws {

    #expect(try Invocation.parse(["backup", "home.json"]).subcommand == .backup(BackupOptions(path: "home.json")))

  }

  @Test func readsForceAndTheOptionsBeforeOrAfterTheSubcommand() throws {

    let invocation = try Invocation.parse(["--hub", "192.168.1.20", "--json", "backup", "--force", "home.json"])

    #expect(invocation.subcommand == .backup(BackupOptions(path: "home.json", overwrites: true)))
    #expect(invocation.hub == "192.168.1.20")
    #expect(invocation.printsJSON)

  }

  @Test func readsCheckAsAFileCheckThatNeedsNoModem() throws {

    #expect(try Invocation.parse(["backup", "--check", "home.json"]).subcommand == .backupCheck(path: "home.json"))
    #expect(try Invocation.parse(["backup", "home.json", "--check"]).subcommand == .backupCheck(path: "home.json"))

  }

  @Test func needsAFile() {

    #expect(throws: ArgumentError.missingArgument("FILE", subcommand: "backup")) { try Invocation.parse(["backup"]) }
    #expect(throws: ArgumentError.missingArgument("FILE", subcommand: "backup")) { try Invocation.parse(["backup", "--check"]) }

  }

  @Test func refusesCheckWithForceAndAnExtraFile() {

    #expect(throws: ArgumentError.conflictingOptions("--check", "--force")) { try Invocation.parse(["backup", "--check", "--force", "home.json"]) }
    #expect(throws: ArgumentError.unexpectedArgument("other.json", subcommand: "backup")) { try Invocation.parse(["backup", "home.json", "other.json"]) }
    #expect(throws: ArgumentError.unknownOption("--merge", subcommand: "backup")) { try Invocation.parse(["backup", "--merge", "home.json"]) }

  }

  // MARK: - transfer plan

  @Test func readsTransferPlanWithItsFile() throws {

    #expect(try Invocation.parse(["transfer", "plan", "home.json"]).subcommand == .transferPlan(TransferPlanOptions(path: "home.json")))

  }

  @Test func readsMergeAndReplaceDatabase() throws {

    #expect(try Invocation.parse(["transfer", "plan", "home.json", "--merge"]).subcommand == .transferPlan(TransferPlanOptions(path: "home.json", existingLinks: .merge)))
    #expect(try Invocation.parse(["transfer", "plan", "--replace-database", "home.json"]).subcommand == .transferPlan(TransferPlanOptions(path: "home.json", existingLinks: .replaceDatabase)))

  }

  @Test func refusesBothChoicesAtOnce() {

    #expect(throws: ArgumentError.conflictingOptions("--merge", "--replace-database")) { try Invocation.parse(["transfer", "plan", "home.json", "--merge", "--replace-database"]) }

  }

  @Test func needsPlanAndAFile() {

    #expect(throws: ArgumentError.missingArgument("plan", subcommand: "transfer")) { try Invocation.parse(["transfer"]) }
    #expect(throws: ArgumentError.unexpectedArgument("apply", subcommand: "transfer")) { try Invocation.parse(["transfer", "apply", "home.json"]) }
    #expect(throws: ArgumentError.missingArgument("FILE", subcommand: "transfer plan")) { try Invocation.parse(["transfer", "plan"]) }

  }

  // MARK: - Help and Hub Pros

  @Test func hasHelpForBothCommands() throws {

    #expect(try Invocation.parse(["help", "backup"]).subcommand == .help(topic: "backup"))
    #expect(try Invocation.parse(["transfer", "--help"]).subcommand == .help(topic: "transfer"))
    #expect(HelpText.text(for: "backup")?.contains("--check FILE") == true)
    #expect(HelpText.text(for: "transfer")?.contains("--replace-database") == true)
    #expect(HelpText.overview.contains("backup FILE"))
    #expect(HelpText.overview.contains("transfer plan FILE"))

  }

  @Test func runsBothCommandsOnAHubPro() {

    #expect(HubProText.runsOnAHubPro(.backup(BackupOptions(path: "home.json"))))
    #expect(HubProText.runsOnAHubPro(.backupCheck(path: "home.json")))
    #expect(HubProText.runsOnAHubPro(.transferPlan(TransferPlanOptions(path: "home.json"))))

  }

  // MARK: - Exit statuses

  @Test func anIncompleteResultHasItsOwnStatus() {

    #expect(ExitStatus.status(for: IncompleteResult(description: "Example.")) == ExitStatus.incomplete)
    #expect(ExitStatus.incomplete == 2)
    #expect(Names.message(for: IncompleteResult(description: "Example.")) == "Example.")

  }

}
