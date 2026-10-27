/// An X10 house code, A through P. The raw value is the code's 4-bit X10 encoding.
public enum X10HouseCode: UInt8, CaseIterable, Hashable, Sendable {

  /// House code A.
  case a = 0x6
  /// House code B.
  case b = 0xE
  /// House code C.
  case c = 0x2
  /// House code D.
  case d = 0xA
  /// House code E.
  case e = 0x1
  /// House code F.
  case f = 0x9
  /// House code G.
  case g = 0x5
  /// House code H.
  case h = 0xD
  /// House code I.
  case i = 0x7
  /// House code J.
  case j = 0xF
  /// House code K.
  case k = 0x3
  /// House code L.
  case l = 0xB
  /// House code M.
  case m = 0x0
  /// House code N.
  case n = 0x8
  /// House code O.
  case o = 0x4
  /// House code P.
  case p = 0xC

}
