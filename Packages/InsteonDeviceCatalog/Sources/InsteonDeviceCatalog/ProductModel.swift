/// A product's model number, as printed on the product, such as `2477D` or `2982-222`.
///
/// The model number names a product, while its category and subcategory identify it on the
/// network. One model can report several subcategories, such as one for each region it was
/// sold in.
///
/// ```swift
/// let model: ProductModel = "2477D"
/// print(model)   // "2477D"
/// ```
public struct ProductModel: RawRepresentable, Hashable, Sendable {

  /// The model number.
  public var rawValue: String

  /// Creates a model number.
  ///
  /// - Parameter rawValue: The model number.
  public init(rawValue: String) {

    self.rawValue = rawValue

  }

}

extension ProductModel: ExpressibleByStringLiteral {

  /// Creates a model number from a string literal, such as `"2477D"`.
  ///
  /// - Parameter value: The model number.
  public init(stringLiteral value: String) {

    self.init(rawValue: value)

  }

}

extension ProductModel: CustomStringConvertible {

  /// The model number.
  public var description: String {

    rawValue

  }

}

extension ProductModel: Decodable {

  /// Decodes a model number from a string.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the value isn't a string.
  public init(from decoder: any Decoder) throws {

    self.init(rawValue: try decoder.singleValueContainer().decode(String.self))

  }

}
