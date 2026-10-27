/// An X10 unit code, 1 through 16. The raw value is the code's 4-bit X10 encoding.
public enum X10UnitCode: UInt8, CaseIterable, Hashable, Sendable {

  /// Unit 1.
  case one = 0x6
  /// Unit 2.
  case two = 0xE
  /// Unit 3.
  case three = 0x2
  /// Unit 4.
  case four = 0xA
  /// Unit 5.
  case five = 0x1
  /// Unit 6.
  case six = 0x9
  /// Unit 7.
  case seven = 0x5
  /// Unit 8.
  case eight = 0xD
  /// Unit 9.
  case nine = 0x7
  /// Unit 10.
  case ten = 0xF
  /// Unit 11.
  case eleven = 0x3
  /// Unit 12.
  case twelve = 0xB
  /// Unit 13.
  case thirteen = 0x0
  /// Unit 14.
  case fourteen = 0x8
  /// Unit 15.
  case fifteen = 0x4
  /// Unit 16.
  case sixteen = 0xC

}
