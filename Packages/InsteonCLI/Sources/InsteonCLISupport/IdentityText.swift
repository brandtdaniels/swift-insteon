import InsteonCore

/// What `insteon device ADDRESS id` and `insteon links --identify` print about a device's
/// identity: why a device named nothing, and its product key, what the device reported to
/// Product Data Request, next to what the Insteon device catalog says it reports, so a key
/// that's missing is explained.
public enum IdentityText {

  /// The product key row's text.
  ///
  /// - Parameters:
  ///   - reported: The key the device reported, or `nil` if it reported none or only zeros.
  ///   - answered: Whether the device answered Product Data Request at all.
  ///   - catalog: What the catalog says the product reports, or `nil` if it doesn't say or
  ///     doesn't have the device.
  ///   - isCatalogKeyObserved: Whether a device was seen reporting the catalog's key, rather
  ///     than the key being known from documents only. Defaults to `false`.
  /// - Returns: The text, such as `"0x00001A"`, or
  ///   `"not reported; the Insteon device catalog says this product doesn't report one"`.
  public static func productKey(reported: ProductKey?, answered: Bool, catalog: ExpectedProductKey?, isCatalogKeyObserved: Bool = false) -> String {

    if let reported {

      switch catalog {
      case let .key(expected)? where expected != reported:
        return "\(reported); the Insteon device catalog gives \(expected) for this product"
      case .notReported?:
        return "\(reported); the Insteon device catalog says this product doesn't report one"
      default:
        return "\(reported)"
      }

    }

    // A device that answered Product Data Request without a key is a newer one; a device that
    // didn't answer said nothing about its key.
    let missing: String = answered ? "none" : "not reported"

    switch catalog {
    case .notReported?:
      return "\(missing); the Insteon device catalog says this product doesn't report one"
    case let .key(expected)? where !answered && !isCatalogKeyObserved:
      // A key known from documents only may be one the device never sends.
      return "\(missing); the Insteon device catalog gives \(expected) for this product from documents only, not from a device seen reporting it"
    case let .key(expected)?:
      return "\(missing); the Insteon device catalog gives \(expected) for this product"
    case nil:
      return answered ? "none; newer devices don't report one" : "not reported"
    }

  }

  /// What `--json` prints for the catalog's product key: the key, such as `"0x00001A"`,
  /// `"none"` for a product the catalog says reports none, or `nil` when the catalog doesn't
  /// say.
  ///
  /// - Parameter entry: What the catalog says the product reports.
  /// - Returns: The value.
  public static func catalogProductKey(_ entry: ExpectedProductKey?) -> String? {

    switch entry {
    case let .key(key)?:
      return "\(key)"
    case .notReported?:
      return "none"
    case nil:
      return nil
    }

  }

  /// What `insteon links --identify` says about a device that answered ID Request without an
  /// identity: an i2CS device that isn't linked to the modem won't say what it is.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - acceptsModem: Whether the device takes commands from the modem.
  /// - Returns: The note.
  public static func unreported(_ device: InsteonAddress, acceptsModem: Bool) -> String {

    acceptsModem
      ? "\(device) didn't report its identity."
      : "\(device) runs i2CS and has no link to the modem, so it won't say what it is."

  }

  /// What `insteon device ADDRESS id` adds about a device that doesn't take commands from the
  /// modem, or `nil` for one that does.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - acceptsModem: Whether the device takes commands from the modem.
  /// - Returns: The note, or `nil`.
  public static func notLinkedNote(_ device: InsteonAddress, acceptsModem: Bool) -> String? {

    acceptsModem ? nil : "The device runs i2CS and isn't linked to the modem, so it won't say more. Link it first with 'insteon link \(device)'."

  }

}
