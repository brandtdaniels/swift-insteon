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

    /// The file was written by a later version of the app than this one. It is left as it is.
    case unsupportedVersion

    /// The file couldn't be written.
    case notSaved

  }

  private let file: URL
  private let secrets: any SecretStore
  private var busy = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

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
    await begin()
    defer { end() }
    var records = try read()
    let previous = try await secrets.load(account: pairing.serviceID)
    try await secrets.save(pairing.credential, account: pairing.serviceID)
    let record = Record(pairing)
    if let index = records.firstIndex(where: { $0.serviceID == record.serviceID }) {
      records[index] = record
    } else {
      records.append(record)
    }
    do {
      try write(records)
    } catch {
      // Put the credential back as it was, so the saved record still matches it.
      if let previous {
        try? await secrets.save(previous, account: pairing.serviceID)
      } else {
        try? await secrets.remove(account: pairing.serviceID)
      }
      throw error
    }
  }

  /// The saved pairings, in the order they were added.
  ///
  /// A pairing whose credential the secret store doesn't hold is left out; it stays saved, and
  /// pairing again replaces it.
  public func load() async throws -> [ClientPairing] {
    await begin()
    defer { end() }
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
    await begin()
    defer { end() }
    let records = try read()
    guard records.contains(where: { $0.serviceID == serviceID }) else { return }
    // The credential goes first. If that fails the record stays, and removing again finishes the job.
    try await secrets.remove(account: serviceID)
    try write(records.filter { $0.serviceID != serviceID })
  }

  /// Waits for any operation under way to finish. An operation suspends while it waits on the
  /// secret store, and another must not read or write the file in the meantime.
  private func begin() async {
    if busy { await withCheckedContinuation { waiting.append($0) } } else { busy = true }
  }

  private func end() {
    if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
  }

  private func read() throws -> [Record] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    guard let data = try? Data(contentsOf: file), let header = try? JSONDecoder().decode(Header.self, from: data) else {
      throw Failure.unreadable
    }
    guard header.version <= 1 else { throw Failure.unsupportedVersion }
    guard header.version == 1, let list = try? JSONDecoder().decode(List.self, from: data) else { throw Failure.unreadable }
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
      let data = try encoder.encode(List(version: 1, pairings: records))
      // The file is created already restricted to its owner, then moved over the old one, so no
      // moment exists when another user could read the tickets in it.
      let temporary = directory.appendingPathComponent(".pairings-" + UUID().uuidString)
      var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
      #if os(iOS) || os(tvOS) || os(watchOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
      #endif
      guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: attributes) else {
        throw Failure.notSaved
      }
      // rename replaces an existing file in one step on every host; FileManager's replace does not on Linux.
      guard rename(temporary.path, file.path) == 0 else {
        try? FileManager.default.removeItem(at: temporary)
        throw Failure.notSaved
      }
    } catch {
      throw Failure.notSaved
    }
  }

  private struct Header: Decodable {
    let version: Int
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
