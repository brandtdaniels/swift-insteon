import Foundation
import Testing
import InsteonCore

/// Updating the Insteon device catalog from its published copy.
struct ProductCatalogUpdateTests {

  @Test(.timeLimit(.minutes(1))) func asksNoAddressThatIsntHTTPS() async throws {

    // The address is refused before any request, so nothing is fetched from it.
    let location: URL = try #require(URL(string: "http://example.invalid/catalog/v0"))

    await #expect(throws: ProductCatalogUpdateError.insecureLocation) {

      _ = try await ProductCatalog.update(replacing: nil, from: location)

    }

  }

}
