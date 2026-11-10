import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

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
    #expect(IdentityText.productKey(reported: nil, answered: false, catalog: .key(key), isCatalogKeyObserved: true)
      == "not reported; the Insteon device catalog gives 0x00001A for this product")

  }

  @Test func saysWhenTheCatalogsKeyIsKnownFromDocumentsOnly() {

    #expect(IdentityText.productKey(reported: nil, answered: false, catalog: .key(key), isCatalogKeyObserved: false)
      == "not reported; the Insteon device catalog gives 0x00001A for this product from documents only, not from a device seen reporting it")
    // A key the device reported is compared the same way however the catalog knows its own.
    #expect(IdentityText.productKey(reported: key, answered: true, catalog: .key(key), isCatalogKeyObserved: false) == "0x00001A")

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

  // MARK: - No identity

  @Test func saysWhyADeviceAskedWithIDRequestNamedNothing() {

    let device = InsteonAddress(0x1A, 0x2B, 0x3C)

    #expect(IdentityText.unreported(device, acceptsModem: true) == "1A.2B.3C didn't report its identity.")
    #expect(IdentityText.unreported(device, acceptsModem: false) == "1A.2B.3C runs i2CS and has no link to the modem, so it won't say what it is.")
    #expect(
      IdentityText.notLinkedNote(device, acceptsModem: false)
        == "The device runs i2CS and isn't linked to the modem, so it won't say more. Link it first with 'insteon link 1A.2B.3C'."
    )
    #expect(IdentityText.notLinkedNote(device, acceptsModem: true) == nil)

  }

}
