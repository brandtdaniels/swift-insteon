import Foundation
import InsteonHubPro
import InsteonProtocol

/// What a step of a ``TransferPlan`` does to the thing it's aimed at, named as the Insteon
/// device catalog names effects.
public enum TransferEffect: String, Codable, Hashable, Sendable, CaseIterable {
  /// The step asks for state and changes nothing.
  case readOnly
  /// The step changes a setting.
  case configuration
  /// The step adds or rewrites an ALL-Link record.
  case link
  /// The step removes or overwrites ALL-Link records a person might want, and needs `--force`
  /// to be carried out.
  case destructive
}

/// What one step of a ``TransferPlan`` does.
public enum TransferAction: String, Codable, Hashable, Sendable {
  /// Reads a device's ALL-Link database and checks it still matches the backup.
  case readDatabase
  /// Rewrites a record of a device's ALL-Link database in place so it names the new modem.
  case rewriteRecord
  /// Reads a device's rewritten records back and checks them.
  case readBack
  /// Removes a record from the new modem's ALL-Link database.
  case removeModemRecord
  /// Adds a record to the new modem's ALL-Link database.
  case addModemRecord
}

/// One step of a ``TransferPlan``, with the exact record it would write.
public struct TransferStep: Codable, Hashable, Sendable {

  /// The step's place in the plan, counting from 1.
  public var number: Int

  /// What the step does to its target.
  public var effect: TransferEffect

  /// What the step does.
  public var action: TransferAction

  /// The device or modem the step is aimed at.
  public var target: InsteonAddress

  /// The record the step writes or removes, or `nil` for a read.
  public var record: BackupRecord?

  /// The record a rewrite overwrites, or `nil` for any other step.
  public var replaces: BackupRecord?

  /// The step in one sentence.
  public var summary: String

}

/// Something in the backup or the new modem that the plan doesn't act on, and why.
public struct TransferFinding: Codable, Hashable, Sendable {

  /// What kind of finding it is.
  public enum Kind: String, Codable, Hashable, Sendable {
    /// A second record of a device's repeats a link its first record holds, so only the first is
    /// rewritten.
    case duplicateRecord
    /// A device's record names the old modem, but the old modem holds no matching record, so the
    /// link is already dead and the record is left as it is.
    case noMatchingModemRecord
    /// The old modem holds a record for a device that holds no matching record, so the link is
    /// already dead and the record isn't copied.
    case noMatchingDeviceRecord
    /// The old modem holds a record for an address that isn't a device in the backup, so it
    /// isn't copied.
    case recordForUnknownDevice
    /// The new modem already holds the record, as the plan would add it.
    case alreadyInPlace
    /// The new modem holds a record for the same link with other data bytes, and keeps it.
    case conflictingModemRecord
    /// The old modem holds the same link twice, so it's added once.
    case duplicateModemRecord
  }

  /// What kind of finding it is.
  public var kind: Kind

  /// The record the finding is about.
  public var record: BackupRecord

  /// The finding in one sentence.
  public var summary: String

}

/// Why a device is re-linked by hand rather than rewritten from afar.
public enum ManualTransferReason: String, Codable, Hashable, Sendable {
  /// The backup holds no ALL-Link database for the device.
  case noDatabase
  /// The backup's database for the device is partial.
  case incompleteDatabase
  /// The device runs i1, which has no remote writes to its ALL-Link database.
  case noRemoteWrites
  /// The device runs i2CS and rejects a modem it isn't linked to, so it rejects the writes.
  case rejectsUntilLinked
  /// The backup doesn't say which engine the device runs.
  case engineUnknown
  /// The backup holds no ALL-Link database of the old modem, so the device's records can't be
  /// matched to it.
  case noModemDatabase
}

/// A device re-linked by hand: why, which links the old modem held with it, and the steps.
public struct ManualTransfer: Codable, Hashable, Sendable {

  /// Where the device comes in the order, counting from 1. The devices are done one after
  /// another in this order.
  public var order: Int

  /// The device's address.
  public var address: InsteonAddress

  /// The device's name, or `nil`.
  public var name: String?

  /// What the device is, or `nil`.
  public var type: String?

  /// Why it can't be rewritten from afar.
  public var reason: ManualTransferReason

  /// The links the old modem held with the device, from the old modem's point of view, which
  /// are the links to make again.
  public var linksToRestore: [BackupRecord]

  /// What to do, in order.
  public var steps: [String]

}

/// A device whose records the plan rewrites, with its steps.
public struct DeviceTransfer: Codable, Hashable, Sendable {

  /// The device's address.
  public var address: InsteonAddress

  /// The device's name, or `nil`.
  public var name: String?

  /// What the device is, or `nil`.
  public var type: String?

  /// The engine the device runs.
  public var engine: BackupEngine

  /// The device's steps, in the order they're made.
  public var steps: [TransferStep]

  /// What the plan leaves as it is, and why.
  public var findings: [TransferFinding]

}

/// What the plan does about links the new modem already holds.
public enum ExistingLinksHandling: String, Codable, Hashable, Sendable {
  /// The new modem holds no links.
  case none
  /// The new modem keeps its links, and the plan adds the backup's.
  case merge
  /// The plan removes the new modem's links before it adds the backup's.
  case replaceDatabase
  /// The new modem's ALL-Link database wasn't read, so the plan assumes it holds none.
  case unread
}

/// What a person chose to do about links the new modem already holds.
public enum ExistingLinksChoice: String, Hashable, Sendable {
  /// Plans nothing, and throws ``TransferPlanError/existingLinks(count:)``, when the new modem
  /// holds links.
  case refuse
  /// Keeps the new modem's links and adds the backup's.
  case merge
  /// Removes the new modem's links, then adds the backup's.
  case replaceDatabase
}

/// The new modem a plan is made for.
public struct TransferTarget: Hashable, Sendable {

  /// The new modem's address.
  public var address: InsteonAddress

  /// The new modem's ALL-Link database, or `nil` if it couldn't be read.
  public var records: [BackupRecord]?

  /// Creates a target.
  ///
  /// - Parameters:
  ///   - address: The new modem's address.
  ///   - records: The new modem's ALL-Link database, or `nil` if it couldn't be read.
  public init(address: InsteonAddress, records: [BackupRecord]?) {

    self.address = address
    self.records = records

  }

}

/// Why no plan can be made.
public enum TransferPlanError: Error, Hashable, Sendable {
  /// The new modem is the one the backup was taken from, so there is nothing to transfer.
  case sameModem
  /// The new modem is a device in the backup.
  case targetIsInBackup
  /// The new modem holds links, and neither merging nor replacing its database was chosen.
  case existingLinks(count: Int)
}

extension TransferPlanError: CustomStringConvertible, LocalizedError {

  /// A one-line explanation.
  public var description: String {

    switch self {
    case .sameModem:
      "The modem is the one the backup was taken from, so there is nothing to transfer."
    case .targetIsInBackup:
      "The modem's address is a device in the backup, so it can't be the modem the devices are moved to."
    case let .existingLinks(count):
      "The modem already holds \(count) \(count == 1 ? "link" : "links"). Choose --merge to keep them and add the backup's, or --replace-database to remove them first. The plan writes nothing either way."
    }

  }

  /// The same text as `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

}

/// What moving a backup's devices to a new modem takes: every step, grouped per device, each
/// marked with its effect and the exact record it writes. A plan writes nothing.
///
/// The same backup and the same new modem make the same plan, byte for byte.
///
/// ```swift
/// let plan = try TransferPlanner.plan(from: backup, to: TransferTarget(address: newModem, records: records))
/// for step in plan.modemSteps + plan.devices.flatMap(\.steps) {
///   print(step.number, step.effect, step.summary)
/// }
/// ```
public struct TransferPlan: Codable, Hashable, Sendable {

  /// The checksum of the backup the plan was made from.
  public var backupChecksum: String

  /// The modem the backup was taken from, or `nil` if the backup doesn't say.
  public var oldModem: InsteonAddress?

  /// The new modem.
  public var newModem: InsteonAddress

  /// What the plan does about links the new modem already holds.
  public var existingLinks: ExistingLinksHandling

  /// How many links the new modem holds, or `nil` if its database wasn't read.
  public var existingLinkCount: Int?

  /// What a person has to know before going on, each as a sentence.
  public var warnings: [String]

  /// The steps aimed at the new modem, in the order they're made.
  public var modemSteps: [TransferStep]

  /// What the plan leaves as it is among the old modem's records and the new modem's, and why.
  public var modemFindings: [TransferFinding]

  /// The devices rewritten from afar, in address order.
  public var devices: [DeviceTransfer]

  /// The devices that hold no link to the old modem, which need nothing, in address order.
  public var unchangedDevices: [InsteonAddress]

  /// The devices re-linked by hand, in the order to do them.
  public var manual: [ManualTransfer]

  /// Every step of the plan in the order it's made: the new modem's, then each device's.
  public var steps: [TransferStep] {

    modemSteps + devices.flatMap(\.steps)

  }

  /// How many steps of each effect the plan has.
  public var stepCounts: [TransferEffect: Int] {

    var counts: [TransferEffect: Int] = [:]

    for step in steps {

      counts[step.effect, default: 0] += 1

    }

    return counts

  }

  /// Writes the plan as JSON with sorted keys, the same bytes for the same plan.
  ///
  /// - Returns: The JSON, indented, with a final newline.
  /// - Throws: An error from the encoder, which doesn't happen for a plan this package made.
  public func json() throws -> Data {

    let encoder: JSONEncoder = JSONEncoder()

    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    return try encoder.encode(self) + Data("\n".utf8)

  }

}

extension TransferTarget {

  /// Reads the new modem's address and ALL-Link database from a connected modem. It asks Get IM
  /// Info and reads the modem's records, and sends nothing that changes the modem.
  ///
  /// - Parameter network: The network of the modem the devices move to.
  /// - Returns: The target.
  /// - Throws: The modem's errors.
  public static func read(from network: DeviceNetwork) async throws -> TransferTarget {

    let info: ModemInfo = try await network.modemInfo()
    let entries: [ModemDatabaseEntry] = try await network.modemDatabase()

    return TransferTarget(address: info.address, records: entries.map { BackupRecord($0.record) })

  }

  /// Reads a Hub Pro's modem address from its device list. A Hub Pro doesn't give out its modem's
  /// ALL-Link database, so the target has no records.
  ///
  /// - Parameter network: The Hub Pro's network.
  /// - Returns: The target, or `nil` if the Hub Pro's list names no modem.
  /// - Throws: What reading the Hub Pro's list throws.
  public static func read(hubPro network: HubProNetwork) async throws -> TransferTarget? {

    try await network.open()

    return await network.listing().first(where: \.isModem).map { (listed: HubProListedDevice) -> TransferTarget in

      TransferTarget(address: listed.address, records: nil)

    }

  }

}
