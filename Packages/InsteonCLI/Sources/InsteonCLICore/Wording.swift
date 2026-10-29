/// Words the command prints that depend on a number.
public enum Wording {

  /// A count with a noun, singular for one and plural otherwise, such as `"1 record"` or
  /// `"2 records"`.
  ///
  /// - Parameters:
  ///   - count: The number of things.
  ///   - singular: The noun for one, such as `"record"`.
  ///   - plural: The noun for any other number. Defaults to `singular` with an `s`.
  /// - Returns: The count and the noun.
  public static func count(_ count: Int, _ singular: String, plural: String? = nil) -> String {

    "\(count) \(count == 1 ? singular : plural ?? singular + "s")"

  }

}
