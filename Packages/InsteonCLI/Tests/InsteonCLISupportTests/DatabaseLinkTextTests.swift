import Foundation
import Testing
@testable import InsteonCLISupport
@testable import InsteonCore
import InsteonProtocol

/// Parsing `link --database` and `unlink --database`, asking first, and what they print.
struct DatabaseLinkTextTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  // MARK: - Parsing

  @Test func linksByTheDatabaseWithADevice() throws {

    let plain = try Invocation.parse(["link", "1A.2B.3C", "--database"]).subcommand
    let dry = try Invocation.parse(["link", "--database", "1A.2B.3C", "--dry-run"]).subcommand
    let yes = try Invocation.parse(["link", "1A.2B.3C", "--database", "-y"]).subcommand

    #expect(plain == .link(LinkOptions(device: lamp, database: DatabaseWriteOptions())))
    #expect(dry == .link(LinkOptions(device: lamp, database: DatabaseWriteOptions(isDryRun: true))))
    #expect(yes == .link(LinkOptions(device: lamp, database: DatabaseWriteOptions(assumesYes: true))))

  }

  @Test func linksByTheDatabaseOnlyWithADeviceAndNoOtherWay() {

    #expect(throws: ArgumentError.missingArgument("ADDRESS with --database", subcommand: "link")) {

      try Invocation.parse(["link", "--database"])

    }

    for option in [["--group", "2"], ["--responder"], ["--either"], ["--two-way"], ["--one-way"], ["--timeout", "10"], ["--cancel"]] {

      #expect(throws: ArgumentError.conflictingOptions("--database", option[0])) {

        try Invocation.parse(["link", "1A.2B.3C", "--database"] + option)

      }

    }

  }

  @Test func refusesDryRunAndYesWithoutDatabase() {

    #expect(throws: ArgumentError.missingArgument("--database with --dry-run", subcommand: "link")) {

      try Invocation.parse(["link", "1A.2B.3C", "--dry-run"])

    }

    #expect(throws: ArgumentError.missingArgument("--database with --yes", subcommand: "unlink")) {

      try Invocation.parse(["unlink", "1A.2B.3C", "--yes"])

    }

    #expect(throws: ArgumentError.missingArgument("--database with --orphans", subcommand: "unlink")) {

      try Invocation.parse(["unlink", "1A.2B.3C", "--orphans"])

    }

  }

  @Test func unlinksByTheDatabaseWithOrphans() throws {

    let plain = try Invocation.parse(["unlink", "1A.2B.3C", "--database"]).subcommand
    let orphans = try Invocation.parse(["unlink", "1A.2B.3C", "--database", "--orphans", "--yes"]).subcommand

    #expect(plain == .unlink(UnlinkOptions(device: lamp, database: DatabaseWriteOptions())))
    #expect(orphans == .unlink(UnlinkOptions(device: lamp, database: DatabaseWriteOptions(assumesYes: true, removesOrphans: true))))

    #expect(throws: ArgumentError.missingArgument("ADDRESS with --database", subcommand: "unlink")) {

      try Invocation.parse(["unlink", "--database"])

    }

    for option in [["--group", "2"], ["--responder"], ["--controller"], ["--timeout", "10"]] {

      #expect(throws: ArgumentError.conflictingOptions("--database", option[0])) {

        try Invocation.parse(["unlink", "1A.2B.3C", "--database"] + option)

      }

    }

  }

  // MARK: - Asking first

  @Test func asksBeforeWritingUnlessADryRunOrYes() throws {

    #expect(try DatabaseWriteOptions().asksForConfirmation(readsFromTerminal: true, subcommand: "link"))
    #expect(try !DatabaseWriteOptions(assumesYes: true).asksForConfirmation(readsFromTerminal: false, subcommand: "link"))
    #expect(try !DatabaseWriteOptions(isDryRun: true).asksForConfirmation(readsFromTerminal: false, subcommand: "link"))

    #expect(throws: ArgumentError.confirmationNeeded(subcommand: "unlink")) {

      try DatabaseWriteOptions().asksForConfirmation(readsFromTerminal: false, subcommand: "unlink")

    }

  }

  // MARK: - The plan and the result

  func plan(direction: DatabaseLinkDirection = .link, steps: [DatabaseLinkStep], orphans: [LinkRecord] = []) -> DatabaseLinkPlan {

    DatabaseLinkPlan(
      device: lamp,
      modem: modem,
      direction: direction,
      info: nil,
      engine: .i2cs,
      steps: steps,
      linksInPlace: [],
      orphans: orphans,
      deviceRecords: [],
      modemRecords: [],
      allModemRecords: []
    )

  }

  var linkSteps: [DatabaseLinkStep] {

    [
      DatabaseLinkStep(kind: .markEndOfDatabase, written: AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00)), memoryAddress: 0x0FEF),
      DatabaseLinkStep(
        kind: .addDeviceRecord,
        written: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x00, address: modem, data1: 0xFF, data2: 0x1C, data3: 0x01),
        memoryAddress: 0x0FF7
      ),
      DatabaseLinkStep(kind: .addModemRecord, written: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: lamp), memoryAddress: nil)
    ]

  }

  @Test func showsEachWriteOfThePlan() {

    #expect(DatabaseLinkText.plan(plan(steps: linkSteps)) == [
      "Linking 1A.2B.3C by writing ALL-Link records directly, 3 writes:",
      "  1. Mark the end of the device's database at 0x0FEF, so it keeps an end.",
      "  2. Write the device's responder record for group 0 at 0x0FF7: 11.22.33, data FF 1C 01.",
      "  3. Add the modem's controller record for group 0, naming the device."
    ])
    #expect(DatabaseLinkText.question(plan(steps: linkSteps)) == "Make these 3 writes to the ALL-Link databases of 1A.2B.3C and the modem? [y/N]")

  }

  @Test func listsTheOrphansAnUnlinkLeaves() {

    let orphan = LinkRecord(isController: false, isInUse: true, group: 0x05, address: InsteonAddress(0x55, 0x66, 0x77), data: [0x00, 0x00, 0x00], memoryAddress: 0x0FEF)

    #expect(DatabaseLinkText.plan(plan(direction: .unlink, steps: [], orphans: [orphan])) == [
      "Neither 1A.2B.3C nor the modem holds a record of a link with the other. Nothing to write.",
      "The device's records that name a device the modem has no record of, left as they are. Such a record can be a working link with another device that was never linked to the modem, such as a 3-way switch or a keypad button; pass --orphans to clear them anyway:",
      "  responder record for group 5 at 0x0FEF naming 55.66.77, data 00 00 00."
    ])

  }

  @Test func saysWhichWritesDidntGoAsPlanned() {

    let steps: [DatabaseLinkStep] = linkSteps
    let result = DatabaseLinkResult(
      plan: plan(steps: steps),
      steps: [
        DatabaseLinkResult.StepResult(step: steps[0], outcome: .written),
        DatabaseLinkResult.StepResult(step: steps[1], outcome: .notWritten),
        DatabaseLinkResult.StepResult(step: steps[2], outcome: .notReached)
      ],
      mismatches: [],
      deviceCheck: .checked
    )

    #expect(!result.isComplete)
    #expect(DatabaseLinkText.result(result) == [
      "Made 1 of 3 writes; 1 read back as written.",
      "  1. Written.",
      "  2. Read back differently after it was written twice; the writes after it weren't made.",
      "  3. Not made.",
      "Not every write went as planned; read the databases with 'insteon device 1A.2B.3C links' and 'insteon links'."
    ])

  }

  @Test func printsThePlanAndResultAsJSON() throws {

    let steps: [DatabaseLinkStep] = linkSteps
    let result = DatabaseLinkResult(
      plan: plan(steps: steps),
      steps: steps.map { (step: DatabaseLinkStep) -> DatabaseLinkResult.StepResult in DatabaseLinkResult.StepResult(step: step, outcome: .written) },
      mismatches: [],
      deviceCheck: .checked
    )
    let report: DatabaseLinkText.Report = DatabaseLinkText.report(result)

    #expect(report.direction == "link")
    #expect(report.device == "1A.2B.3C")
    #expect(report.engine == "i2CS")
    #expect(report.dryRun == false)
    #expect(report.complete == true)
    #expect(report.deviceCheck == "checked")
    #expect(report.steps.map { (step: DatabaseLinkText.Step) -> String in step.kind } == ["markEndOfDatabase", "addDeviceRecord", "addModemRecord"])
    #expect(report.steps.map { (step: DatabaseLinkText.Step) -> String? in step.outcome } == ["written", "written", "written"])
    #expect(report.steps[1].record == DatabaseLinkText.Record(
      holder: "device",
      recordAddress: "0x0FF7",
      role: "responder",
      group: 0,
      address: "11.22.33",
      data: "FF 1C 01",
      inUse: true,
      endOfDatabase: false
    ))
    #expect(report.steps[0].record.endOfDatabase)
    #expect(report.steps[2].record.holder == "modem")

    let planOnly: DatabaseLinkText.Report = DatabaseLinkText.report(plan(steps: steps), isDryRun: true)

    #expect(planOnly.dryRun)
    #expect(planOnly.complete == nil)
    #expect(planOnly.mismatches == nil)
    #expect(planOnly.steps.map { (step: DatabaseLinkText.Step) -> String? in step.outcome } == [nil, nil, nil])

    let json: String = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)

    #expect(json.contains("\"recordAddress\":\"0x0FF7\""))

  }

}
