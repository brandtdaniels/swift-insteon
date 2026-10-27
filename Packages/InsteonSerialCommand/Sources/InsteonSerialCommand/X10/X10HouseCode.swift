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

/// An X10 command. The raw value is the command's 4-bit X10 encoding.
public enum X10Command: UInt8, CaseIterable, Hashable, Sendable {

  /// Turns off every unit on the house code.
  case allUnitsOff = 0x0
  /// Turns on every light on the house code.
  case allLightsOn = 0x1
  /// Turns the addressed units on.
  case on = 0x2
  /// Turns the addressed units off.
  case off = 0x3
  /// Dims the addressed units.
  case dim = 0x4
  /// Brightens the addressed units.
  case bright = 0x5
  /// Turns off every light on the house code.
  case allLightsOff = 0x6
  /// Introduces an X10 extended code.
  case extendedCode = 0x7
  /// Asks other transmitters on the house code to respond.
  case hailRequest = 0x8
  /// Responds to a hail request.
  case hailAcknowledge = 0x9
  /// The first preset-dim command.
  case presetDim1 = 0xA
  /// The second preset-dim command.
  case presetDim2 = 0xB
  /// Introduces X10 extended data.
  case extendedData = 0xC
  /// Reports that a unit is on.
  case statusOn = 0xD
  /// Reports that a unit is off.
  case statusOff = 0xE
  /// Asks the addressed units for their status.
  case statusRequest = 0xF

}
