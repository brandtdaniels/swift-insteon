import InsteonModem
import InsteonProtocol

/// The ALL-Link groups read from the modem's and devices' databases, and what didn't add up.
public struct AllLinkGroupReading: Hashable, Sendable {

  /// A record whose other half is missing: one end of a link records it, but the other end's
  /// database, which was read, doesn't.
  public struct HalfLink: Hashable, Sendable {

    /// The endpoint whose database has the record.
    public var endpoint: LinkEndpoint

    /// The record.
    public var record: AllLinkRecord

    /// Creates a half link.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint whose database has the record.
    ///   - record: The record.
    public init(endpoint: LinkEndpoint, record: AllLinkRecord) {

      self.endpoint = endpoint
      self.record = record

    }

  }

  /// Every group whose controller and responders both record the link, by controller and
  /// group number. The modem's groups come first, then the devices' in address order.
  public var groups: [AllLinkGroup]

  /// Records whose other half is missing, such as one left behind by a device that was reset
  /// or replaced.
  public var halfLinks: [HalfLink]

  /// Devices whose databases couldn't be read, such as a sleeping battery-powered sensor.
  /// Links to them aren't in ``AllLinkGroupReading/groups``.
  public var unreadable: [InsteonAddress]

  /// Devices other records link to that weren't in the list to read. Links to them aren't in
  /// ``AllLinkGroupReading/groups`` or ``AllLinkGroupReading/halfLinks``.
  public var unlisted: [InsteonAddress]

  /// Creates a reading.
  ///
  /// - Parameters:
  ///   - groups: The groups whose links are complete.
  ///   - halfLinks: The records whose other half is missing.
  ///   - unreadable: The devices whose databases couldn't be read.
  ///   - unlisted: The devices linked to that weren't in the list to read.
  public init(groups: [AllLinkGroup], halfLinks: [HalfLink], unreadable: [InsteonAddress], unlisted: [InsteonAddress]) {

    self.groups = groups
    self.halfLinks = halfLinks
    self.unreadable = unreadable
    self.unlisted = unlisted

  }

}

/// Reads the ALL-Link groups of the modem and a list of devices, the counterpart of ``Linker``.
///
/// A link is two records: the controller's record of the responder, and the responder's record
/// of the controller in the same group, which holds the responder's link data, such as a
/// dimmer's on-level. The reader reads every listed database through an
/// ``AllLinkDatabaseCache`` and pairs the records up. A group is a controller's group number
/// with every responder whose record matches; a record without its match is a half link.
///
/// ```swift
/// let reading = try await AllLinkGroupReader(cache: cache).read(devices: [lamp, keypad])
///
/// for group in reading.groups {
///   print(group.controller, group.number, group.responders.count)
/// }
/// ```
///
/// Only the listed devices and the modem are read. The modem's database is read every time,
/// since it has no delta to say whether something else, such as its SET button, changed it.
/// A device that doesn't answer or rejects the reads is listed in
/// ``AllLinkGroupReading/unreadable`` rather than failing the reading. A responder can have
/// several records for one controller's group, such as one for each of a keypad's buttons, so
/// it can appear in a group more than once, once for each record.
public struct AllLinkGroupReader: Sendable {

  /// The cache the databases are read through.
  public let cache: AllLinkDatabaseCache

  /// Creates a reader.
  ///
  /// - Parameter cache: The cache to read the databases through.
  public init(cache: AllLinkDatabaseCache) {

    self.cache = cache

  }

  /// Reads the groups of the modem and the listed devices.
  ///
  /// - Parameter devices: The devices whose databases to read.
  /// - Returns: The groups, the half links, and the devices that couldn't be read or weren't
  ///   listed.
  /// - Throws: The modem's errors, other than a listed device not answering or rejecting the
  ///   reads, or `CancellationError` if the task is canceled.
  public func read(devices: [InsteonAddress]) async throws -> AllLinkGroupReading {

    let modemAddress = try await cache.modem.modemInfo().address
    await cache.invalidateModem()

    var databases: [InsteonAddress: (endpoint: LinkEndpoint, records: [AllLinkRecord])] = [
      modemAddress: (.modem, try await cache.modemRecords().filter { $0.flags.contains(.inUse) })
    ]
    var unreadable: [InsteonAddress] = []

    for device in Set(devices).subtracting([modemAddress]).sorted(by: Self.addressOrder) {

      try Task.checkCancellation()

      do {

        let records = try await cache.records(of: device)
          .filter { !$0.isEndOfDatabase && $0.record.flags.contains(.inUse) }
          .map(\.record)

        databases[device] = (.device(device), records)

      } catch let error as ModemError {

        // Only the device's own failures make it unreadable; the modem's end the reading.
        switch error {
        case .deviceTimedOut(device), .deviceRejected(device, _):
          unreadable.append(device)
        default:
          throw error
        }

      }

    }

    return Self.pair(databases, modem: modemAddress, unreadable: unreadable)

  }

  /// Pairs each controller record with the responder's record of it.
  private static func pair(
    _ databases: [InsteonAddress: (endpoint: LinkEndpoint, records: [AllLinkRecord])],
    modem: InsteonAddress,
    unreadable: [InsteonAddress]
  ) -> AllLinkGroupReading {

    let skipped = Set(unreadable)
    var groups: [AllLinkGroup] = []
    var halfLinks: [AllLinkGroupReading.HalfLink] = []
    var unlisted: Set<InsteonAddress> = []

    // The modem first, then the devices in address order.
    let owners = [modem] + databases.keys.filter { $0 != modem }.sorted(by: addressOrder)

    // Each database's records by what they link, so a record's match is found directly.
    let indexes = databases.mapValues { database in

      Dictionary(grouping: database.records) { MatchKey(address: $0.address, group: $0.group, isController: $0.flags.contains(.controller)) }

    }

    for owner in owners {

      guard let (endpoint, records) = databases[owner] else {

        continue

      }

      var responders: [AllLinkGroupNumber: [AllLinkGroup.Responder]] = [:]

      for record in records {

        let other = record.address
        let isController = record.flags.contains(.controller)

        guard let otherDatabase = databases[other], let otherIndex = indexes[other] else {

          if !skipped.contains(other) {

            unlisted.insert(other)

          }

          continue

        }

        // The other end's matching records: the opposite role, the same group, and this end.
        let matches = otherIndex[MatchKey(address: owner, group: record.group, isController: !isController)] ?? []

        guard !matches.isEmpty else {

          halfLinks.append(.init(endpoint: endpoint, record: record))

          continue

        }

        // Each pair is collected once, from its controller's side, with every record the
        // responder keeps for it.
        if isController {

          responders[record.group, default: []] += matches.map { match in

            AllLinkGroup.Responder(otherDatabase.endpoint, data1: match.data1, data2: match.data2, data3: match.data3)

          }

        }

      }

      for number in responders.keys.sorted(by: { $0.rawValue < $1.rawValue }) {

        // A controller with two records of the same responder in a group would list its
        // records twice.
        var seen: Set<AllLinkGroup.Responder> = []
        let members = responders[number, default: []].filter { seen.insert($0).inserted }

        groups.append(AllLinkGroup(controller: endpoint, number: number, responders: members))

      }

    }

    return AllLinkGroupReading(
      groups: groups,
      halfLinks: halfLinks,
      unreadable: unreadable,
      unlisted: unlisted.sorted(by: addressOrder)
    )

  }

  /// What a record links: the other end, the group, and the record's role.
  private struct MatchKey: Hashable {

    let address: InsteonAddress

    let group: AllLinkGroupNumber

    let isController: Bool

  }

  /// Orders addresses by their bytes.
  private static func addressOrder(_ lhs: InsteonAddress, _ rhs: InsteonAddress) -> Bool {

    lhs.bytes.lexicographicallyPrecedes(rhs.bytes)

  }

}
