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
    case .needsForce:
      throw CommandFailure(description: "Removing the modem's own links takes --force. Nothing was written.")
    case .declined:
      Output.note("Nothing was written.")
    case .write:
      let report: TransferReport = await TransferExecutor(writer: ModemTransferWriter(network: network, plan: plan), keepGoing: options.keepsGoing).run(plan) { step, outcome in
        Output.note(TransferApplyText.line(step, outcome))
      }

      for line in TransferApplyText.summary(report, plan: plan) {

        Output.line(line)

      }

      if !report.isComplete {

        throw IncompleteResult(description: "The transfer didn't finish: what was written stays, and running the command again writes only what is left.")

      }
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
