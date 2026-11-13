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

    let loaded = CatalogStore.load()

    catalog = loaded?.catalog

    switch loaded?.source {
    case .bundled?:
      catalogVersion = CatalogStore.bundledVersion().map { "\($0)" } ?? "unknown"
    case .cached?:
      catalogVersion = CatalogStore.cachedVersion().map { "\($0)" } ?? "unknown"
    case nil:
      catalogVersion = "unknown"
    }

  }

  /// The version of the catalog in use, or `"unknown"` if none could be loaded.
  let catalogVersion: String

  /// The product a device's identity names, such as "Example Dimmer 9101 (DemoLinc Dimmer)".
  func name(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String? {

    catalog?.productName(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)

  }

}
