import Testing
import InsteonCLISupport
import InsteonCore

/// What `insteon device ADDRESS id` prints about a product key, next to what the catalog says.
struct IdentityTextTests {

  let key = ProductKey(0x00, 0x00, 0x1A)

  @Test func explainsAMissingKeyTheCatalogSaysIsntReported() {

    #expect(IdentityText.productKey(reported: nil, answered: false, catalog: .notReported)
      == "not reported; the Insteon device catalog says this product doesn't report one")
    #expect(IdentityText.productKey(reported: nil, answered: true, catalog: .notReported)
      == "none; the Insteon device catalog says this product doesn't report one")

  }

  @Test func showsTheCatalogsKeyNextToWhatTheDeviceReported() {

    #expect(IdentityText.productKey(reported: key, answered: true, catalog: .key(key)) == "0x00001A")
    #expect(IdentityText.productKey(reported: key, answered: true, catalog: .key(ProductKey(0x00, 0x00, 0x20)))
      == "0x00001A; the Insteon device catalog gives 0x000020 for this product")
    #expect(IdentityText.productKey(reported: nil, answered: false, catalog: .key(key))
      == "not reported; the Insteon device catalog gives 0x00001A for this product")

  }

  @Test func saysWhatItAlwaysDidWithoutTheCatalog() {

    #expect(IdentityText.productKey(reported: key, answered: true, catalog: nil) == "0x00001A")
    #expect(IdentityText.productKey(reported: nil, answered: true, catalog: nil) == "none; newer devices don't report one")
    #expect(IdentityText.productKey(reported: nil, answered: false, catalog: nil) == "not reported")

  }

  @Test func printsTheCatalogsKeyForJSON() {

    #expect(IdentityText.catalogProductKey(.key(key)) == "0x00001A")
    #expect(IdentityText.catalogProductKey(.notReported) == "none")
    #expect(IdentityText.catalogProductKey(nil) == nil)

  }

}
