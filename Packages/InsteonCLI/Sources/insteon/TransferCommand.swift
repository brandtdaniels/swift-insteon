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

    let plan: TransferPlan = try TransferPlanner.plan(from: backup, to: target, existingLinks: options.existingLinks)

    if printsJSON {

      Output.line(String(decoding: try plan.json(), as: UTF8.self).trimmingCharacters(in: .newlines))

      return

    }

    for line in TransferPlanText.lines(plan) {

      Output.line(line)

    }

  }

}
