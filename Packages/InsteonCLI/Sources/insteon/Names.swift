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

  /// The product a device's identity names, such as "Dimmer Switch 2477D (SwitchLinc Dimmer)".
  func name(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String? {

    catalog?.productName(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)

  }

}

/// A command that couldn't do what was asked, with a message that says why and what to do.
struct CommandFailure: Error, CustomStringConvertible {

  /// The message for the person who typed the command.
  let description: String

}

/// Names for the values the command prints.
enum Names {

  /// A category with its name, such as "0x01 (Dimmable Lighting Control)".
  static func category(_ category: DeviceCategory) -> String {

    category.name.map { "\(category) (\($0))" } ?? "\(category)"

  }

  /// An engine as Insteon's documents name it, or "unknown".
  static func engine(_ engine: InsteonEngine?) -> String {

    engine?.name ?? "unknown"

  }

  /// The modem's role in a link it reported, or "unknown".
  static func mode(_ mode: AllLinkMode?) -> String {

    mode?.name ?? "unknown"

  }

  /// An error as a one-line message, without credentials: the command's own errors, and the
  /// libraries' as InsteonCore describes them, with where to set the Hub's user name and
  /// password when the Hub rejects them.
  static func message(for error: any Error) -> String {

    switch error {
    case let error as ArgumentError:
      return error.description
    case let error as ConfigurationError:
      return error.description
    case let error as DotEnvError:
      return error.description
    case let error as EnvironmentFileError:
      return error.description
    case is CancellationError:
      return "Interrupted."
    case let error as CommandFailure:
      return error.description
    default:
      break
    }

    if InsteonErrorDescription.isRejectedHubCredentials(error), let message = InsteonErrorDescription.message(for: error) {

      return message + " Check INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD."

    }

    return InsteonErrorDescription.message(for: error) ?? error.localizedDescription

  }

}
