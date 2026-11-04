import InsteonCore

/// How the relay link's text names the flags the catalog gives for how a relay holds a state.
enum RelayFlagText {

  /// The flags by their labels: `"Pulse flag"`, or `"Pulse and Pulse on both flags"`.
  ///
  /// - Parameter flags: The flags, at least one.
  /// - Returns: The phrase.
  static func named(_ flags: [RelayFlag]) -> String {

    let labels: [String] = flags.map(\.label)

    guard labels.count > 1 else {

      return "\(labels.first ?? "") flag"

    }

    return "\(labels.dropLast().joined(separator: ", ")) and \(labels[labels.count - 1]) flags"

  }

  /// The flags by their labels, with what to say they are: `"Pulse flag is"`, or
  /// `"Pulse and Pulse on both flags are"`.
  ///
  /// - Parameter flags: The flags, at least one.
  /// - Returns: The phrase.
  static func are(_ flags: [RelayFlag]) -> String {

    "\(named(flags)) \(flags.count > 1 ? "are" : "is")"

  }

}
