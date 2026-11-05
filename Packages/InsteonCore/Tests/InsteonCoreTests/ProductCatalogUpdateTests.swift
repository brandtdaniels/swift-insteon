import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonNetworking
import InsteonProtocol

/// Updating the Insteon device catalog from its published copy.
struct ProductCatalogUpdateTests {

  /// An error neither the updater nor the network throws.
  struct Unrelated: Error, Equatable {}

  @Test(.timeLimit(.minutes(1))) func asksNoAddressThatIsntHTTPS() async throws {

    // The address is refused before any request, so nothing is fetched from it.
    let location: URL = try #require(URL(string: "http://example.invalid/catalog/v0"))

    await #expect(throws: ProductCatalogUpdateError.insecureLocation) {

      _ = try await ProductCatalog.update(replacing: nil, currentVersion: nil, from: location)

    }

  }

  @Test func throwsItsOwnErrorForEachOfTheUpdatersAndTheRedirects() {

    let version = DeviceCatalogVersion(major: 1, minor: 2, patch: 3)
    let weakening = GuardWeakening(commandSet: "exampleGuarded", kind: .flag, name: "lockout")
    let notACatalog = DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Not a catalog."))
    let cases: [(any Error, ProductCatalogUpdateError)] = [
      (DeviceCatalogUpdateError.incompatibleVersion(version), .incompatibleVersion(version)),
      (DeviceCatalogUpdateError.olderThanCurrent(version), .olderThanCurrent(version)),
      (DeviceCatalogUpdateError.unexpectedStatus(404), .unexpectedStatus(404)),
      (DeviceCatalogUpdateError.malformedManifest, .malformedManifest),
      (DeviceCatalogUpdateError.checksumMismatch, .checksumMismatch),
      (HTTPClientError.insecureRedirect, .insecureRedirect),
      (HTTPClientError.redirectRefused, .redirectRefused),
      (notACatalog, .unreadableCatalog),
      (DeviceCatalogUpdateError.weakensGuards([weakening]), .weakensGuards([weakening])),
    ]

    for (error, expected) in cases {

      #expect((ProductCatalog.updateError(for: error) as? ProductCatalogUpdateError) == expected, "\(error)")

    }

  }

  @Test func passesOtherErrorsThroughAsTheyAre() {

    #expect(ProductCatalog.updateError(for: CancellationError()) is CancellationError)
    #expect((ProductCatalog.updateError(for: HTTPClientError.responseTooLarge(limit: 16)) as? HTTPClientError) == .responseTooLarge(limit: 16))
    #expect((ProductCatalog.updateError(for: HTTPClientError.nonHTTPResponse) as? HTTPClientError) == .nonHTTPResponse)
    #expect((ProductCatalog.updateError(for: Unrelated()) as? Unrelated) == Unrelated())

  }

  // MARK: - A saved or supplied catalog

  /// A made-up command set whose lockout flag is guarded as `lockout` says.
  static func catalog(lockout: FlagGuard?) -> DeviceCatalog {

    DeviceCatalog(
      profiles: [],
      commandSets: [
        CommandSet(
          id: "exampleGuarded",
          name: "Example guarded",
          summary: "A lockout.",
          operatingFlags: [OperatingFlag(name: "lockout", summary: "Locks out linking.", query: .operatingFlags, bit: 0x01, on: 0x00, off: 0x01, writeGuard: lockout)]
        )
      ]
    )

  }

  @Test func refusesASavedCatalogThatWeakensTheBaselinesGuards() throws {

    let baseline: DeviceCatalog = Self.catalog(lockout: .neverSet)

    #expect(throws: ProductCatalogError.weakensGuards([GuardWeakening(commandSet: "exampleGuarded", kind: .flag, name: "lockout")])) {

      try ProductCatalog.checked(Self.catalog(lockout: nil), against: baseline)

    }

    // Equal and stricter guards are kept.
    #expect(try ProductCatalog.checked(Self.catalog(lockout: .neverSet), against: baseline) == Self.catalog(lockout: .neverSet))
    #expect(try ProductCatalog.checked(Self.catalog(lockout: .keep), against: baseline) == Self.catalog(lockout: .keep))

  }

  @Test func readsTheBundledCopyAsGuardedAsItself() throws {

    let json: Data = try DeviceCatalog.bundledJSON()

    #expect(throws: Never.self) {

      _ = try ProductCatalog(json: json)
      _ = try ProductCatalog.load(contentsOf: ProductCatalog.bundledCatalogURL())

    }

  }

}
