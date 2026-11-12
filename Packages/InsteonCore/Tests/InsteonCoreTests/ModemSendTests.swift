import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// What a raw serial command needs before a modem is sent it, from the modem's command set
/// and the flows' own declarations, with a made-up modem and catalogs.
struct ModemSendTests {

  /// The made-up modem's identity: it reports `0x03/0x77`.
  static let identity: [UInt8] = [0x3A, 0x4B, 0x41, 0x03, 0x77, 0x45]

  /// Command sets the made-up modem's profile names, one effect per number.
  static func json(withCommandSet: Bool = true) -> String {

    #"""
      {
        "devices": [{
          "model": "9801",
          "name": "Example Test Modem",
          "identities": [{ "category": "0x03", "subcategory": "0x77" }],
          "commandSets": [\#(withCommandSet ? #"{ "commandSet": "exampleModem", "category": "0x03", "subcategory": "0x77" }"# : "")],
          "groups": [],
          "capabilities": [],
          "sources": ["A"]
        }],
        "commandSets": [{
          "id": "exampleModem",
          "name": "Example modem",
          "description": "Serial commands that each do something different.",
          "serialCommands": [
            { "name": "readIdentity", "description": "Reads.", "effect": "readOnly", "idempotent": true, "number": "0x60" },
            { "name": "blink", "description": "Blinks.", "effect": "actuation", "idempotent": true, "number": "0x6D" },
            { "name": "tuneAck", "description": "Tunes.", "effect": "configuration", "idempotent": true, "number": "0x68",
              "parameters": [{ "name": "value", "description": "Value.", "byte": 1 }] },
            { "name": "neverSend", "description": "Is never sent.", "effect": "destructive", "idempotent": false, "guard": "never", "number": "0x72" },
            { "name": "wipe", "description": "Wipes.", "effect": "destructive", "idempotent": true, "number": "0x67" }
          ],
          "sources": ["A"]
        }]
      }
      """#

  }

  static func catalog(withCommandSet: Bool = true) throws -> ProductCatalog {

    try ProductCatalog(DeviceCatalog(json: Data(json(withCommandSet: withCommandSet).utf8)))

  }

  /// A modem that answers Get IM Info with the made-up identity and echoes every other command
  /// with an ACK.
  static func connection() -> ScriptedConnection {

    ScriptedConnection { written, _ in

      written.count > 1 && written[1] == 0x60 ? [0x02, 0x60] + identity + [0x06] : written + [0x06]

    }

  }

  /// Sends bytes the way `modem send` does and returns what was written to the modem, or the
  /// refusal.
  static func send(_ bytes: [UInt8], catalog: ProductCatalog?, forcing: Bool = false) async throws -> [[UInt8]] {

    let connection: ScriptedConnection = connection()

    try await Modem.withConnection(connection) { (modem: Modem) async throws -> Void in

      _ = try await ModemSession(modem: modem, hub: nil, catalog: catalog).write(rawCommand: bytes, forcing: forcing, collectingFor: .zero)

    }

    return connection.written

  }

  static let getInfo: [UInt8] = [0x02, 0x60]

  // MARK: - With a command set

  @Test(.timeLimit(.minutes(1))) func sendsWhatTheModemsCommandSetCallsReadOnlyOrActuation() async throws {

    let catalog: ProductCatalog = try Self.catalog()

    #expect(try await Self.send([0x02, 0x6D], catalog: catalog) == [Self.getInfo, [0x02, 0x6D]])

  }

  @Test(.timeLimit(.minutes(1))) func refusesAConfigurationCommandWithoutForceAndSendsItWithForce() async throws {

    let catalog: ProductCatalog = try Self.catalog()
    let tune: [UInt8] = [0x02, 0x68, 0x01]

    await #expect(throws: SendRefusal.needsConsent(.configuration)) {

      _ = try await Self.send(tune, catalog: catalog)

    }

    #expect(try await Self.send(tune, catalog: catalog, forcing: true) == [Self.getInfo, tune])

  }

  @Test(.timeLimit(.minutes(1))) func refusesADestructiveCommandWithoutForceAndSendsItWithForce() async throws {

    let catalog: ProductCatalog = try Self.catalog()

    await #expect(throws: SendRefusal.needsConsent(.destructive)) {

      _ = try await Self.send([0x02, 0x67], catalog: catalog)

    }

    #expect(try await Self.send([0x02, 0x67], catalog: catalog, forcing: true) == [Self.getInfo, [0x02, 0x67]])

  }

  @Test(.timeLimit(.minutes(1))) func refusesACommandTheCommandSetLeavesOutWithoutForce() async throws {

    let catalog: ProductCatalog = try Self.catalog()

    await #expect(throws: SendRefusal.needsConsent(nil)) {

      _ = try await Self.send([0x02, 0x6E], catalog: catalog)

    }

    #expect(try await Self.send([0x02, 0x6E], catalog: catalog, forcing: true) == [Self.getInfo, [0x02, 0x6E]])

  }

  @Test(.timeLimit(.minutes(1))) func neverWritesACommandTheModemsCommandSetNeverSends() async throws {

    let catalog: ProductCatalog = try Self.catalog()

    for forcing in [false, true] {

      await #expect(throws: SendRefusal.neverSentToModem) {

        _ = try await Self.send([0x02, 0x72], catalog: catalog, forcing: forcing)

      }

    }

  }

  // MARK: - The modem's identity

  @Test(.timeLimit(.minutes(1))) func asksTheModemWhoItIsOncePerSession() async throws {

    let catalog: ProductCatalog = try Self.catalog()
    let connection: ScriptedConnection = Self.connection()

    try await Modem.withConnection(connection) { (modem: Modem) async throws -> Void in

      let session = ModemSession(modem: modem, hub: nil, catalog: catalog)

      _ = try await session.write(rawCommand: [0x02, 0x6D], collectingFor: .zero)
      _ = try await session.write(rawCommand: [0x02, 0x69], collectingFor: .zero)

      await #expect(throws: SendRefusal.needsConsent(.configuration)) {

        _ = try await session.write(rawCommand: [0x02, 0x68, 0x01], collectingFor: .zero)

      }

    }

    #expect(connection.written.filter { $0 == Self.getInfo }.count == 1)
    #expect(connection.written == [Self.getInfo, [0x02, 0x6D], [0x02, 0x69]])

  }

  @Test(.timeLimit(.minutes(1))) func doesNotKeepAFailedIdentityReadAndAsksAgain() async throws {

    let catalog: ProductCatalog = try Self.catalog()
    let connection = FailingIdentityConnection(failures: 1)

    try await Modem.withConnection(connection) { (modem: Modem) async throws -> Void in

      let session = ModemSession(modem: modem, hub: nil, catalog: catalog)

      await #expect(throws: FailingIdentityConnection.Failure.self) {

        _ = try await session.write(rawCommand: [0x02, 0x67], forcing: true, collectingFor: .zero)

      }

      _ = try await session.write(rawCommand: [0x02, 0x6D], collectingFor: .zero)

    }

    #expect(await connection.identityAsks == 2)
    #expect(await connection.written == [[0x02, 0x6D]])

  }

  @Test(.timeLimit(.minutes(1))) func readsEveryCommandAgainstTheCatalogTheSessionHolds() async throws {

    // The session is built with one catalog; a call has no way to give another.
    let connection: ScriptedConnection = Self.connection()

    try await Modem.withConnection(connection) { (modem: Modem) async throws -> Void in

      let described = ModemSession(modem: modem, hub: nil, catalog: try Self.catalog())
      let undescribing = ModemSession(modem: modem, hub: nil, catalog: try Self.catalog(withCommandSet: false))

      _ = try await described.write(rawCommand: [0x02, 0x6D], collectingFor: .zero)

      await #expect(throws: SendRefusal.needsConsent(nil)) {

        _ = try await undescribing.write(rawCommand: [0x02, 0x6D], collectingFor: .zero)

      }

    }

  }

  // MARK: - Without one

  @Test(.timeLimit(.minutes(1))) func treatsAModemWithoutACommandSetAsDescribingNothingExceptWhatCoreBuilds() async throws {

    let catalog: ProductCatalog = try Self.catalog(withCommandSet: false)

    #expect(try await Self.send([0x02, 0x69], catalog: catalog) == [Self.getInfo, [0x02, 0x69]])

    await #expect(throws: SendRefusal.needsConsent(nil)) {

      _ = try await Self.send([0x02, 0x6D], catalog: catalog)

    }

    #expect(try await Self.send([0x02, 0x6D], catalog: catalog, forcing: true) == [Self.getInfo, [0x02, 0x6D]])

  }

  @Test(.timeLimit(.minutes(1))) func treatsAnUnknownModemAsOneWithoutACommandSet() async throws {

    // No catalog: nothing describes the modem, and the modem isn't asked who it is.
    await #expect(throws: SendRefusal.needsConsent(nil)) {

      _ = try await Self.send([0x02, 0x6D], catalog: nil)

    }

    #expect(try await Self.send([0x02, 0x60], catalog: nil) == [Self.getInfo])

  }

  @Test(.timeLimit(.minutes(1))) func treatsAModemTheCatalogDoesntKnowAsOneWithoutACommandSet() async throws {

    let catalog: ProductCatalog = try Self.catalog()
    let other = ScriptedConnection { written, _ in

      written.count > 1 && written[1] == 0x60 ? [0x02, 0x60, 0x3A, 0x4B, 0x41, 0x03, 0x55, 0x45, 0x06] : written + [0x06]

    }

    try await Modem.withConnection(other) { (modem: Modem) async throws -> Void in

      let session = ModemSession(modem: modem, hub: nil, catalog: catalog)

      await #expect(throws: SendRefusal.needsConsent(nil)) {

        _ = try await session.write(rawCommand: [0x02, 0x6D], collectingFor: .zero)

      }

      _ = try await session.write(rawCommand: [0x02, 0x69], collectingFor: .zero)

    }

  }

  @Test(.timeLimit(.minutes(1))) func doesNotWriteAForcedCommandWhenTheModemCantSayWhoItIs() async throws {

    let catalog: ProductCatalog = try Self.catalog()
    let broken = FailingIdentityConnection()

    try await Modem.withConnection(broken) { (modem: Modem) async throws -> Void in

      await #expect(throws: FailingIdentityConnection.Failure.self) {

        _ = try await ModemSession(modem: modem, hub: nil, catalog: catalog).write(rawCommand: [0x02, 0x67], forcing: true, collectingFor: .zero)

      }

    }

    #expect(await broken.written.isEmpty)

  }

  // MARK: - What is never consent's to decide

  @Test(.timeLimit(.minutes(1))) func neverWritesTheFloorOrAnUnframedCommandAndNeverAsksTheModemFirst() async throws {

    let catalog: ProductCatalog = try Self.catalog()
    let poke: [UInt8] = [0x02, 0x62, 0x3A, 0x4B, 0x41, 0x0F, 0x29, 0x05]

    await #expect(throws: SendRefusal.protected(.poke)) {

      _ = try await Self.send(poke, catalog: catalog, forcing: true)

    }

    let connection: ScriptedConnection = Self.connection()

    try await Modem.withConnection(connection) { (modem: Modem) async throws -> Void in

      await #expect(throws: SendRefusal.self) {

        _ = try await ModemSession(modem: modem, hub: nil, catalog: catalog).write(rawCommand: [0x02, 0x09], collectingFor: .zero)

      }

    }

    #expect(connection.written.isEmpty)

  }

}

/// A modem connection that fails the write of Get IM Info and keeps every other write.
actor FailingIdentityConnection: ModemConnection {

  struct Failure: Error {}

  private(set) var written: [[UInt8]] = []

  /// How many Get IM Info writes were asked.
  private(set) var identityAsks: Int = 0

  private var failures: Int

  private let continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation

  private let stream: AsyncThrowingStream<[UInt8], any Error>

  /// - Parameter failures: How many Get IM Info writes fail before one is answered. Defaults
  ///   to every one.
  init(failures: Int = .max) {

    self.failures = failures
    (stream, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()

  }

  func write(_ bytes: [UInt8]) async throws {

    if bytes.count > 1, bytes[1] == 0x60 {

      identityAsks += 1

      if failures > 0 {

        failures -= 1

        throw Failure()

      }

      continuation.yield([0x02, 0x60] + ModemSendTests.identity + [0x06])

      return

    }

    written.append(bytes)
    continuation.yield(bytes + [0x06])

  }

  nonisolated func receive() -> AsyncThrowingStream<[UInt8], any Error> {

    stream

  }

}
