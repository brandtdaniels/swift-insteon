import Foundation
import RepoCheckSupport

/// Reads the fields of the Insteon device catalog's manifest that the update script needs.
public enum CatalogManifest {
  /// A field of the manifest.
  public enum Field: String, CaseIterable {
    case sha256
    case version
  }

  /// The text of a field of the manifest at the URL.
  ///
  /// - Throws: `CheckFailure` if the file isn't a JSON object or lacks the field.
  public static func value(of field: Field, at url: URL) throws -> String {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw CheckFailure("\(url.path): can't be read")
    }

    try StrictJSON.validate(Array(data), named: url.path)

    guard let manifest = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? [String: Any] else {
      throw CheckFailure("\(url.path): isn't a JSON object")
    }

    guard let value = manifest[field.rawValue] else {
      throw CheckFailure("\(url.path): has no \(field.rawValue)")
    }

    return (value as? String) ?? "\(value)"
  }
}
