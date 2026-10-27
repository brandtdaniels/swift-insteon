/// The generation of INSTEON engine a device runs, which sets the commands every such device
/// supports and how strictly it checks extended messages.
///
/// A device reports its engine in the acknowledgement of
/// ``StandardDirectCommand/getEngineVersion``: cmd2 is the engine's raw value. Engines are
/// ordered, so a device with a later engine supports everything an earlier one does.
///
/// ```swift
/// if let engine = InsteonEngine(rawValue: acknowledgement.command.command2),
///    let minimum = StandardDirectCommand.exitLinkingMode.minimumEngine,
///    engine >= minimum {
///   // Every device with this engine supports the command.
/// }
/// ```
public enum InsteonEngine: UInt8, Hashable, Sendable, CaseIterable {

  /// The first engine. Its devices support the base commands that every device does.
  case i1 = 0x00

  /// The second engine, which adds commands such as reading and writing operating flags and the
  /// extended Set/Get, ALL-Link database and trigger commands.
  case i2 = 0x01

  /// The second engine with checksums. Its devices reject an extended message whose user data
  /// doesn't carry a valid ``ChecksumIntegrity`` checksum, and they report more reasons in a
  /// NAK; see ``NAKReason``.
  case i2cs = 0x02

}

extension InsteonEngine: Comparable {

  /// Returns whether one engine is earlier than another.
  ///
  /// - Parameters:
  ///   - lhs: An engine.
  ///   - rhs: Another engine.
  /// - Returns: `true` if `lhs` is earlier than `rhs`.
  public static func < (lhs: InsteonEngine, rhs: InsteonEngine) -> Bool {

    lhs.rawValue < rhs.rawValue

  }

}
