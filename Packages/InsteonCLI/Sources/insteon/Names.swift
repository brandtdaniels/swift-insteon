import Foundation
import InsteonCLISupport
import InsteonCore

/// Finds products in the Insteon device catalog: the copy that ships with the package, or a
/// newer one `insteon catalog update` downloaded.
struct ProductNames: Sendable {

  /// The catalog, or `nil` if it couldn't be loaded, in which case no names are shown.
  let catalog: ProductCatalog?

  /// Loads the catalog: the copy `insteon catalog update` downloaded, when it's in the format
  /// the command reads and at least as new as the bundled copy, or else the bundled copy. A
  /// copy that can't be read gets a one-line warning on standard error.
  init() {

    catalog = Self.loadCatalog()

  }

  /// The catalog `CatalogStore.load()` chooses, or `nil` after a one-line warning if neither
  /// copy can be read, as when only the executable was copied.
  private static func loadCatalog() -> ProductCatalog? {

    CatalogStore.load()?.catalog

  }

  /// The product a device's identity names, such as "Example Dimmer 9101 (DemoLinc Dimmer)".
  func name(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String? {

    catalog?.productName(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)

  }

}
