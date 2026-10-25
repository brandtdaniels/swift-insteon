//
//  AllLinking.swift
//  
//
//  Created by Brandt Daniels on 5/23/20.
//

/// The type of ALL-Link to establish.
public enum LinkCode: UInt8 {

  /// ALL-Links the IM as a Responder (slave).
  case modemAsResponder = 0x00

  /// ALL-Links the IM as a Controller (master).
  case modemAsController = 0x01

  /// ALL-Links the IM as a Controller when the IM initiates ALLLinking, or as a Responder when another device initiates ALL-Linking.
  case modemAsControllerOrResponder = 0x03

  /// Deletes the ALL-Link.
  case deleteAllLink = 0xFF

}

/// What to do with the ALL-Link Record
public enum ControlCode: UInt8 {

  /// Starting at the top of the ALDB, search for the first ALL-Link
  /// Record matching the <ALL-Link Group> and <ID> in bytes
  /// 5 – 8. The search ignores byte 4, <ALL-Link Record Flags>.
  /// You will receive an ACK at the end of the returned message
  /// if such an ALL-Link Record exists, or else a NAK if it doesn’t.
  /// If the record exists, the IM will return it in an ALL-Link
  /// Record Response message.
  case findFirst = 0x00

  /// Search for the next ALL-Link Record following the one found
  /// using <Control Code> 0x00 above. This allows you to find
  /// both Controller and Responder records for a given <ALL-Link
  /// Group> and <ID>. Be sure to use the same <ALL-Link
  /// Group> and <ID> (bytes 5 – 8) as you used for <Control
  /// Code> 0x00.
  /// You will receive an ACK at the end of the returned message
  /// if another matching ALL-Link Record exists, or else a NAK if
  /// it doesn’t. If the record exists, the IM will return it in an
  /// ALL-Link Record Response message.
  case findNext = 0x01

  /// Modify an existing or else add a new ALL-Link Record for
  /// either a Controller or Responder.
  /// Starting at the top of the ALDB, search for the first ALL-Link
  /// Record matching the <ALL-Link Group> and <ID> in bytes
  /// 5 – 8. The search ignores byte 4, <ALL-Link Record Flags>.
  /// If such an ALL-Link Record exists, overwrite it with the data
  /// in bytes 4 – 11; otherwise, create a new ALL-Link Record
  /// using bytes 4 – 11.
  /// Note that the IM will copy <ALL-Link Record Flags> you
  /// supplied in byte 4 below directly into the <ALL-Link Record
  /// Flags> byte of the ALL-Link Record in an ALDB-L (linear)
  /// database. Use caution, because you can damage an ALDB-L
  /// if you misuse this Command. For instance, if you zero the
  /// <ALL-Link Record Flags> byte in the first ALL-Link Record,
  /// the IM’s ALDB-L database will then appear empty.
  case modifyFirstFoundOrAdd = 0x20

  /// Modify an existing or else add a new Controller (master)
  /// ALL-Link Record.
  /// Starting at the top of the ALDB, search for the first ALL-Link
  /// Controller Record matching the <ALL-Link Group> and
  /// <ID> in bytes 5 – 8. An ALL-Link Controller Record has bit
  /// 6 of its <ALL-Link Record Flags> byte set to 1.
  /// If such a Controller ALL-Link Record exists, overwrite it with
  /// the data in bytes 5 – 11; otherwise, create a new ALL-Link
  /// Record using bytes 5 – 11. In either case, the IM will set bit
  /// 6 of the <ALL-Link Record Flags> byte in the ALL-Link
  /// Record to 1 to indicate that the record is for a Controller.
  case modifyFirstControllerFoundOrAdd = 0x40

  /// Modify an existing or else add a new Responder (slave) ALLLink Record.
  /// Starting at the top of the ALDB, search for the first ALL-Link
  /// Responder Record matching the <ALL-Link Group> and
  /// <ID> in bytes 5 – 8. An ALL-Link Responder Record has bit
  /// 6 of its <ALL-Link Record Flags> byte cleared to 0.
  /// If such a Responder ALL-Link Record exists, overwrite it with
  /// the data in bytes 5 – 11; otherwise, create a new ALL-Link
  /// Record using bytes 5 – 11. In either case, The IM will clear
  /// bit 6 of the <ALL-Link Record Flags> byte in the ALL-Link
  /// Record to 0 to indicate that the record is for a Responder.
  case modifyFirstResponderFoundOrAdd = 0x41

  /// Delete an ALL-Link Record.
  /// Starting at the top of the ALDB, search for the first ALL-Link
  /// Record matching the <ALL-Link Group> and <ID> in bytes
  /// 5 – 8. The search ignores byte 4, <ALL-Link Record Flags>.
  /// You will receive an ACK at the end of the returned message
  /// if such an ALL-Link Record existed and was deleted, or else
  /// a NAK no such record exists.
  case deleteFirstFound = 0x80

}

/// ALL-Link Database control flags for this ALL-Link Record
public struct RecordFlags: OptionSet {

  public let rawValue: UInt8

  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// 1 = Record is in use
  /// 0 = Record is available
  /// Note: This bit is only settable for ALDB-L (linear) databases
  /// using <Control Code> 0x20. It is handled automatically by
  /// ALDB-T (threaded) databases
  static let isUsed = RecordFlags(rawValue: 1 << 7)

  /// 1 = IM is a Controller (master) of the device with <ID>
  /// given in bytes 6 – 8 below,
  /// 0 = IM is a Responder (slave) to the device with <ID>
  /// given in bytes 6 – 8 below
  static let isController = RecordFlags(rawValue: 1 << 6)

  /// 1 = Record has been used before
  /// 0 = ‘High-water Mark’
  /// Note: This bit is only settable for ALDB-L (linear) databases
  /// using <Control Code> 0x20. It is handled automatically by
  /// ALDB-T (threaded) databases.
  static let usedBefore = RecordFlags(rawValue: 1 << 1)


}
