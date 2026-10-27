/// Whether a message is standard length, with no user data, or extended length, with 14 bytes
/// of user data.
///
/// INSTEON defines standard and extended commands in separate tables, and the same cmd1 can
/// mean different commands in each: `0x2E` is Light ON at Ramp Rate as a standard command but
/// Extended Set/Get as an extended one. So a command's bytes identify it only together with
/// its message length.
public enum MessageLength: Hashable, Sendable {

  /// A standard-length message: 10 bytes, with no user data.
  case standard

  /// An extended-length message: 24 bytes, including 14 bytes of user data.
  case extended

}
