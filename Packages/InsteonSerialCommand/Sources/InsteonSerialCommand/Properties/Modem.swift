//
//  Modem.swift
//  
//
//  Created by Brandt Daniels on 5/23/20.
//

/// Flag byte containing Configuration Flags that affect IM operation.
/// These all default to 0.
public struct ModemConfiguration: OptionSet {

  public let rawValue: UInt8

  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// Disable host communications Deadman feature (i.e.
  /// allow host to delay more than 240 milliseconds between
  /// sending bytes to the IM).
  static let disableDeadmanFeature = ModemConfiguration(rawValue: 1 << 4)

  /// Disables automatic LED operation by the IM. The host
  /// must now control the IM’s LED using LED On49 and LED
  /// Off
  static let disableAutoLed = ModemConfiguration(rawValue: 1 << 5)

  /// Puts the IM into Monitor Mode
  static let enableMonitorMode = ModemConfiguration(rawValue: 1 << 6)

  /// Disables automatic linking when the user pushes and
  /// holds the SET Button
  static let disableSetButtonLinking = ModemConfiguration(rawValue: 1 << 7)

}
