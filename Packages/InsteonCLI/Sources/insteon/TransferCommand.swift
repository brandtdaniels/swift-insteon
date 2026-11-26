import Foundation
import InsteonCLISupport
import InsteonCore

/// `insteon transfer plan`: plans how a backup's devices move to the connected modem. It reads
/// the modem's address and ALL-Link database, sends nothing else, and writes nothing.
enum TransferCommand {

  /// Reads the backup, checking its checksum, before any modem is connected.
  static func load(_ options: TransferPlanOptions) throws -> HomeBackup {

    try HomeBackup(parsing: BackupFile.read(options.path))

  }

  /// Plans for the modem a session is connected to.
  static func plan(_ backup: HomeBackup, options: TransferPlanOptions, modem: ModemSession, hub: HubLocation?, names: ProductNames, printsJSON: Bool) async throws {

    Output.note("Reading the new modem's address and ALL-Link database. Nothing is written.")

    // A network of its own, so the identity cache, which holds the old modem's devices, is
    // neither read nor changed.
    let network: DeviceNetwork = modem.network(catalog: names.catalog, snapshot: NetworkSnapshot(), hub: hub)
    let target: TransferTarget = try await TransferTarget.read(from: network)

    try print(backup, target: target, options: options, printsJSON: printsJSON)

  }

  /// Plans for a Hub Pro, whose modem address comes from its device list.
  static func plan(_ backup: HomeBackup, options: TransferPlanOptions, hubPro network: HubProNetwork, printsJSON: Bool) async throws {

    Output.note("Reading the Hub Pro's device list for its modem's address. Nothing is written.")

    guard let target = try await TransferTarget.read(hubPro: network) else {

      throw CommandFailure(description: "The Hub Pro's list names no modem, so there is no address to plan for.")

    }

    try print(backup, target: target, options: options, printsJSON: printsJSON)

  }

  /// Carries a plan out on the modem a session is connected to: reads the modem, shows the plan,
  /// asks, and writes, reading before each write.
  static func apply(_ backup: HomeBackup, options: TransferApplyOptions, modem: ModemSession, hub: HubLocation?, names: ProductNames, printsJSON: Bool) async throws {

    let asks: Bool = try options.asksForConfirmation(readsFromTerminal: Terminal.readsFromTerminal)

    Output.note("Reading the new modem's address and ALL-Link database. Nothing is written yet.")

    let network: DeviceNetwork = modem.network(catalog: names.catalog, snapshot: NetworkSnapshot(), hub: hub)
    let target: TransferTarget = try await TransferTarget.read(from: network)
    let plan: TransferPlan = try TransferPlanner.plan(from: backup, to: target, existingLinks: options.plan.existingLinks)

    try print(plan, printsJSON: printsJSON)

    switch try await TransferApplyText.decision(plan, options: options, asks: asks, confirm: Terminal.confirm) {
    case .nothingToWrite:
      Output.note("The plan has nothing to write.")
    case .dryRun:
      Output.note("Dry run: nothing was written.")

      if (plan.stepCounts[.destructive] ?? 0) > 0, !options.isForced {

        Output.note("A real run would stop: removing the modem's own links takes --force.")

      }
    case .needsForce:
      throw CommandFailure(description: "Removing the modem's own links takes --force. Nothing was written.")
    case .declined:
      Output.note("Nothing was written.")
    case .write:
      let report: TransferReport = await TransferExecutor(writer: ModemTransferWriter(network: network, plan: plan), keepGoing: options.keepsGoing).run(plan) { step, outcome in
        Output.note(TransferApplyText.line(step, outcome))
      }

      // With --json, standard output holds the plan's JSON alone.
      for line in TransferApplyText.summary(report, plan: plan) {

        if printsJSON {

          Output.note(line)

        } else {

          Output.line(line)

        }

      }

      if !report.isComplete {

        throw IncompleteResult(description: "The transfer didn't finish: what was written stays, and running the command again writes only what is left.")

      }
    }

  }

  /// Asks each device of the backup to answer through the connected modem.
  static func verify(_ backup: HomeBackup, modem: ModemSession, hub: HubLocation?, names: ProductNames, printsJSON: Bool) async throws {

    Output.note("Asking each device of the backup to answer through this modem. A ping changes nothing.")

    let network: DeviceNetwork = modem.network(catalog: names.catalog, snapshot: NetworkSnapshot(), hub: hub)

    // Reaching the modem first, so a connection that fails is the command's failure, which is
    // what lets it fall back to a Hub Pro, and not every device's.
    _ = try await network.modemInfo()

    try report(await TransferVerifier.verify(backup, describing: Names.message(for:)) { address in try await network.device(address).ping() }, printsJSON: printsJSON)

  }

  /// The same, through a Hub Pro.
  static func verify(_ backup: HomeBackup, hubPro network: HubProNetwork, printsJSON: Bool) async throws {

    Output.note("Asking each device of the backup to answer through this Hub Pro. A ping changes nothing.")

    try await network.open()
    try report(await TransferVerifier.verify(backup, describing: Names.message(for:)) { address in try await network.device(address).ping() }, printsJSON: printsJSON)

  }

  /// What `--json` prints for `transfer verify`.
  private struct VerifyJSON: Encodable {

    struct Device: Encodable {
      let address: String
      let name: String?
      let answered: Bool
      let problem: String?
    }

    let complete: Bool
    let devices: [Device]

  }

  private static func report(_ verification: TransferVerification, printsJSON: Bool) throws {

    if printsJSON {

      try Output.json(VerifyJSON(complete: verification.isComplete, devices: verification.checks.map { VerifyJSON.Device(address: $0.address.description, name: $0.name, answered: $0.answered, problem: $0.problem) }))

      if !verification.isComplete {

        throw IncompleteResult(description: "Some devices didn't answer through this modem.")

      }

      return

    }

    if !verification.checks.isEmpty {

      Output.table(TransferVerifyText.rows(verification))

    }

    Output.line(TransferVerifyText.summary(verification))

    if !verification.isComplete {

      throw IncompleteResult(description: "Some devices didn't answer through this modem.")

    }

  }

  private static func print(_ backup: HomeBackup, target: TransferTarget, options: TransferPlanOptions, printsJSON: Bool) throws {

    try print(TransferPlanner.plan(from: backup, to: target, existingLinks: options.existingLinks), printsJSON: printsJSON)

  }

  private static func print(_ plan: TransferPlan, printsJSON: Bool) throws {

    if printsJSON {

      Output.line(String(decoding: try plan.json(), as: UTF8.self).trimmingCharacters(in: .newlines))

      return

    }

    for line in TransferPlanText.lines(plan) {

      Output.line(line)

    }

  }

}
