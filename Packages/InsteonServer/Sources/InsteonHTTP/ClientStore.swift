import Crypto
import Foundation

/// What a client credential may do. Each scope allows everything the scopes below it allow.
public enum ClientScope: String, Codable, CaseIterable, Sendable, Comparable {
  /// Read devices and health, and follow events.
  case read
  /// Everything `read` allows, and send commands to devices.
  case control
  /// Everything `control` allows, and manage clients.
  case admin

  private var rank: Int {
    switch self {
    case .read: 0
    case .control: 1
    case .admin: 2
    }
  }

  public static func < (left: ClientScope, right: ClientScope) -> Bool { left.rank < right.rank }

  /// Whether a credential with this scope may do what `required` guards.
  public func allows(_ required: ClientScope) -> Bool { self >= required }
}

/// A client the service knows: a name and a scope, never its token.
public struct ClientRecord: Codable, Sendable, Equatable {
  /// The identifier in the client's token and in `/api/v1/clients/{id}`.
  public let id: String
  /// A name a person chose, such as `Phone`.
  public let name: String
  /// What the client's credential may do.
  public let scope: ClientScope
  /// When the client was created.
  public let createdAt: Date
}

/// A client and the token that authenticates it, which exists only in this value.
public struct IssuedClient: Sendable, Equatable {
  /// The client.
  public let client: ClientRecord
  /// The token the client sends as `Authorization: Bearer <token>`. The service keeps only a hash.
  public let token: String
}

/// A client as the registry keeps it: the record, and a salted hash of its secret.
public struct StoredClient: Codable, Sendable, Equatable {
  /// The client.
  public let record: ClientRecord
  /// Random bytes mixed into the hash, one set per client.
  public let salt: Data
  /// SHA-256 of the salt followed by the secret.
  public let hash: Data
}

/// Everything the service keeps about its clients.
public struct ClientRegistry: Codable, Sendable, Equatable {
  /// The registry file's format.
  public var version = 1
  /// Names this service to a client that paired with it. Chosen once, never changed.
  public var serviceId: String
  /// The clients that are not revoked.
  public var clients: [StoredClient]

  /// Creates a registry.
  public init(serviceId: String, clients: [StoredClient] = []) {
    self.serviceId = serviceId
    self.clients = clients
  }
}

/// Where the registry lives between runs.
public protocol ClientPersisting: Sendable {
  /// The stored registry, or `nil` when none has been stored.
  func load() async throws -> ClientRegistry?
  /// Replaces the stored registry.
  func save(_ registry: ClientRegistry) async throws
}

/// A registry that lasts as long as the process.
public actor InMemoryClientPersistence: ClientPersisting {
  private var registry: ClientRegistry?

  /// Creates an empty store.
  public init() {}

  public func load() -> ClientRegistry? { registry }
  public func save(_ registry: ClientRegistry) { self.registry = registry }
}

/// Why a client operation was refused.
public enum ClientError: Error, Equatable, Sendable {
  /// The name is empty, longer than 64 characters or has control characters.
  case invalidName
  /// No client has that identifier.
  case unknownClient
  /// The service already has the most clients it keeps.
  case limitReached
  /// The registry couldn't be read or written, so nothing changed.
  case notSaved
}

/// The clients of a service: creating, listing, revoking and recognizing them.
public protocol ClientStoring: Sendable {
  /// Names the service. The same value every time, for the life of the registry.
  func serviceID() async throws -> String
  /// Creates a client and returns its token, which is not recoverable afterward.
  func issue(name: String, scope: ClientScope) async throws -> IssuedClient
  /// Replaces a client's token. The old token stops working.
  func rotate(id: String) async throws -> IssuedClient
  /// Removes a client. Its token stops working.
  func revoke(id: String) async throws
  /// The clients, oldest first.
  func clients() async throws -> [ClientRecord]
  /// The client a token belongs to, or `nil` for a token that is wrong, altered or revoked.
  func authenticate(token: String) async -> ClientRecord?
}

/// Where a store gets its random bytes.
protocol RandomnessSource: Sendable {
  func bytes(_ count: Int) async -> [UInt8]
}

/// The operating system's secure random generator.
struct SystemRandomness: RandomnessSource {
  func bytes(_ count: Int) async -> [UInt8] {
    var generator = SystemRandomNumberGenerator()
    return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
  }
}

/// Keeps clients in a ``ClientPersisting``, holding only a salted hash of each token.
///
/// A token is `<id>.<secret>`: the id finds the client and the secret is 32 random bytes. The
/// store reads the registry again before each change and when a token names an id it doesn't
/// hold, so a client created by another process is recognized and a change never discards one.
public actor ClientStore: ClientStoring {
  /// The most clients the store keeps.
  public static let maximumClients = 64

  private static let secretBytes = 32
  private static let saltBytes = 16
  private static let idBytes = 8
  private static let serviceIDBytes = 16

  private let persistence: any ClientPersisting
  private let now: @Sendable () -> Date
  private let randomness: any RandomnessSource
  private var cached: ClientRegistry?
  private var isStored = false
  private var busy = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  /// Creates a store.
  /// - Parameters:
  ///   - persistence: Where the registry lives.
  ///   - now: The time a client is created.
  public init(persistence: any ClientPersisting, now: @escaping @Sendable () -> Date = { Date() }) {
    self.init(persistence: persistence, now: now, randomness: SystemRandomness())
  }

  init(persistence: any ClientPersisting, now: @escaping @Sendable () -> Date, randomness: any RandomnessSource) {
    self.persistence = persistence
    self.now = now
    self.randomness = randomness
  }

  public func serviceID() async throws -> String {
    try await exclusively {
      let registry = try await freshRegistry()
      if !isStored { try await store(registry) }
      return registry.serviceId
    }
  }

  public func clients() async throws -> [ClientRecord] {
    try await exclusively { try await freshRegistry().clients.map(\.record) }
  }

  public func issue(name: String, scope: ClientScope) async throws -> IssuedClient {
    guard let name = Self.validated(name) else { throw ClientError.invalidName }
    return try await exclusively {
      var registry = try await freshRegistry()
      guard registry.clients.count < Self.maximumClients else { throw ClientError.limitReached }
      let id = Self.hex(await randomness.bytes(Self.idBytes))
      // Whole seconds, which is all the registry file keeps, so a client reads back equal to the one issued.
      let record = ClientRecord(id: id, name: name, scope: scope, createdAt: Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down)))
      let (stored, token) = await credential(for: record)
      registry.clients.append(stored)
      try await store(registry)
      return IssuedClient(client: record, token: token)
    }
  }

  public func rotate(id: String) async throws -> IssuedClient {
    try await exclusively {
      var registry = try await freshRegistry()
      guard let index = registry.clients.firstIndex(where: { $0.record.id == id }) else { throw ClientError.unknownClient }
      let record = registry.clients[index].record
      let (stored, token) = await credential(for: record)
      registry.clients[index] = stored
      try await store(registry)
      return IssuedClient(client: record, token: token)
    }
  }

  public func revoke(id: String) async throws {
    try await exclusively {
      var registry = try await freshRegistry()
      guard registry.clients.contains(where: { $0.record.id == id }) else { throw ClientError.unknownClient }
      registry.clients.removeAll { $0.record.id == id }
      try await store(registry)
    }
  }

  public func authenticate(token: String) async -> ClientRecord? {
    guard let parsed = Self.parse(token) else { return nil }
    if let match = matching(parsed) { return match }
    // An id this store doesn't hold may belong to a client another process created.
    guard cached?.clients.contains(where: { $0.record.id == parsed.id }) != true else { return nil }
    let reloaded = try? await exclusively { try await freshRegistry() }
    guard reloaded != nil else { return nil }
    return matching(parsed)
  }

  // MARK: Credentials

  private func credential(for record: ClientRecord) async -> (stored: StoredClient, token: String) {
    let secret = Self.base64URL(await randomness.bytes(Self.secretBytes))
    let salt = Data(await randomness.bytes(Self.saltBytes))
    let stored = StoredClient(record: record, salt: salt, hash: Self.hash(salt: salt, secret: secret))
    return (stored, record.id + "." + secret)
  }

  private func matching(_ parsed: (id: String, secret: String)) -> ClientRecord? {
    guard let stored = cached?.clients.first(where: { $0.record.id == parsed.id }) else { return nil }
    let presented = Self.hash(salt: stored.salt, secret: parsed.secret)
    return SecureDigest.matches(Array(presented), Array(stored.hash)) ? stored.record : nil
  }

  private static func hash(salt: Data, secret: String) -> Data {
    Data(SHA256.hash(data: salt + Data(secret.utf8)))
  }

  private static func parse(_ token: String) -> (id: String, secret: String)? {
    guard token.utf8.count <= 128 else { return nil }
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].utf8.count == idBytes * 2, parts[0].allSatisfy({ $0.isHexDigit && !$0.isUppercase }), parts[1].utf8.count == 43, parts[1].allSatisfy(isBase64URL) else { return nil }
    return (String(parts[0]), String(parts[1]))
  }

  private static func isBase64URL(_ character: Character) -> Bool {
    character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
  }

  private static func validated(_ name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...64).contains(trimmed.count), !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
    return trimmed
  }

  private static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

  private static func base64URL(_ bytes: [UInt8]) -> String {
    Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  // MARK: Registry

  /// The stored registry, or a new one when nothing is stored, and the cache afterward.
  private func freshRegistry() async throws -> ClientRegistry {
    let loaded: ClientRegistry?
    do { loaded = try await persistence.load() } catch { throw ClientError.notSaved }
    if let loaded {
      cached = loaded
      isStored = true
      return loaded
    }
    if let cached { return cached }
    let created = ClientRegistry(serviceId: Self.hex(await randomness.bytes(Self.serviceIDBytes)))
    cached = created
    return created
  }

  private func store(_ registry: ClientRegistry) async throws {
    do { try await persistence.save(registry) } catch { throw ClientError.notSaved }
    cached = registry
    isStored = true
  }

  /// Runs `work` alone, so two changes never read the same registry and lose one of them.
  private func exclusively<Result>(_ work: () async throws -> Result) async rethrows -> Result {
    if busy { await withCheckedContinuation { waiting.append($0) } } else { busy = true }
    // The next waiter inherits the turn, so a new caller can't slip in between.
    defer { if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() } }
    return try await work()
  }
}
