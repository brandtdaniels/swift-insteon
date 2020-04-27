//
//  Formatter.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

import Foundation

public struct Formatter {

  // MARK: - StandardLengthMessageProtocol

  static func format(_ message: StandardLengthMessageProtocol) -> String {

    return String(
      format: "%@%02X%@",
      message.toAddress.stringValue,
      message.flags.rawValue,
      message.command.stringValue
    )

  }

  // MARK: - ExtendedLengthMessageProtocol

  static func format(_ message: ExtendedLengthMessageProtocol) -> String {

    return String(
      format: "%@%02X%@%@",
      message.toAddress.stringValue,
      message.flags.rawValue,
      message.command.stringValue,
      message.userData.stringValue
    )

  }

  // MARK: - DeviceAddressProtocol

  static func format(_ address: DeviceAddressProtocol) -> String {

    return address.stringValue

  }

  static func prettyFormat(_ address: DeviceAddressProtocol) -> String {

    return address.prettyStringValue

  }

}

// MARK: - DeviceAddressProtocol

extension DeviceAddressProtocol {

    var stringValue: String {

        return String(
          format: "%02X%02X%02X",
          highByte,
          middleByte,
          lowByte
      )

    }

    var prettyStringValue: String {

        return String(
          format: "%02X.%02X.%02X",
          highByte,
          middleByte,
          lowByte
      )

    }

}

// MARK: - CommandProtocol

extension CommandProtocol {

    var stringValue: String {

        return String(
          format: "%02X%02X",
          command1,
          command2
      )
      
    }

}

// MARK: - UserDataProtocol

extension UserDataProtocol {

    var stringValue: String {

        return String(
          format: "%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
          data1,
          data2,
          data3,
          data4,
          data5,
          data6,
          data7,
          data8,
          data9,
          data10,
          data11,
          data12,
          data13,
          data14
      )

    }

}
