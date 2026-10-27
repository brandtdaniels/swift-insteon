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
  /// Introduces an X10 extended code. The data and command bytes that follow it can't be sent
  /// through ``SerialCommand/sendX10(_:)``; this case is mainly for reading received X10.
  case extendedCode = 0x7
  /// Asks other transmitters on the house code to respond.
  case hailRequest = 0x8
  /// Responds to a hail request.
  case hailAcknowledge = 0x9
  /// The first preset-dim command, for levels 0 through 15.
  ///
  /// Preset dim carries the level in the house code's place, so the house code in
  /// ``X10Code/command(_:_:)`` selects the level rather than the house.
  case presetDim1 = 0xA
  /// The second preset-dim command, for levels 16 through 31. Like
  /// ``X10Command/presetDim1``, it carries the level in the house code's place.
  case presetDim2 = 0xB
  /// Introduces X10 extended data. The data bytes that follow it can't be sent through
  /// ``SerialCommand/sendX10(_:)``; this case is mainly for reading received X10.
  case extendedData = 0xC
  /// Reports that a unit is on.
  case statusOn = 0xD
  /// Reports that a unit is off.
  case statusOff = 0xE
  /// Asks the addressed units for their status.
  case statusRequest = 0xF

}
