import Foundation

/// The services a device is paired with.
///
/// A service's name and routes go in a file in the host's directory, readable only by its owner. Its
/// credential goes in the host's ``SecretStore``, under the service's identifier, and never in
/// the file. The same code runs on every host; a host gives only a directory and a secret store.
public actor PairingStore {

  /// Why the store couldn't be read or written.
  public enum Failure: Error, Equatable, Sendable {

    /// The file isn't a list of pairings. It is left as it is.
    case unreadable

    /// The file couldn't be written.
    case notSaved

  }

  private let file: URL
  private let secrets: any SecretStore

  /// Creates a store.
  ///
  /// - Parameters:
  ///   - directory: Where the host keeps this app's files.
  ///   - secrets: Where the host keeps credentials.
  public init(directory: URL, secrets: any SecretStore) {
    self.file = directory.appendingPathComponent("pairings.json")
    self.secrets = secrets
  }

  /// Saves a pairing, replacing the one for the same service.
  public func save(_ pairing: ClientPairing) async throws {
    var records = try read()
    try await secrets.save(pairing.credential, account: pairing.serviceID)
    let record = Record(pairing)
    if let index = records.firstIndex(where: { $0.serviceID == record.serviceID }) {
      records[index] = record
    } else {
      records.append(record)
    }
    try write(records)
  }

  /// The saved pairings, in the order they were added.
  ///
  /// A pairing whose credential the secret store no longer holds is left out; it stays saved, and
  /// pairing again replaces it.
  public func load() async throws -> [ClientPairing] {
    var pairings: [ClientPairing] = []
    for record in try read() {
      if let credential = try await secrets.load(account: record.serviceID) {
        pairings.append(record.pairing(credential: credential))
      }
    }
    return pairings
  }

  /// Forgets a pairing and its credential. A pairing that isn't saved is left alone.
  public func remove(serviceID: String) async throws {
    let records = try read()
    guard records.contains(where: { $0.serviceID == serviceID }) else { return }
    try write(records.filter { $0.serviceID != serviceID })
    try await secrets.remove(account: serviceID)
  }

  private func read() throws -> [Record] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    guard let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode(List.self, from: data), list.version == 1 else {
      throw Failure.unreadable
    }
    return list.pairings
  }

  private func write(_ records: [Record]) throws {
    do {
      let directory = file.deletingLastPathComponent()
      if !FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(List(version: 1, pairings: records)).write(to: file, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    } catch {
      throw Failure.notSaved
    }
  }

  private struct List: Codable {
    let version: Int
    let pairings: [Record]
  }

  private struct Record: Codable {
    let serviceID: String
    let name: String
    let scope: String
    let routes: [Route]

    struct Route: Codable {
      let kind: String
      let url: String?
      let ticket: String?
    }

    init(_ pairing: ClientPairing) {
      serviceID = pairing.serviceID
      name = pairing.name
      scope = pairing.scope
      routes = pairing.routes.map { Route(kind: $0.kind, url: $0.url, ticket: $0.ticket) }
    }

    func pairing(credential: String) -> ClientPairing {
      ClientPairing(serviceID: serviceID, name: name, scope: scope, routes: routes.map { .init(kind: $0.kind, url: $0.url, ticket: $0.ticket) }, credential: credential)
    }
  }

}
