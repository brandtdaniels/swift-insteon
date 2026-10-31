import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonNetworking

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

}
