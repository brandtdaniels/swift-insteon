//
//  Keychain.swift
//  
//
//  Created by Brandt Daniels on 6/28/20.
//

import Foundation
import KeychainAccess

public protocol Keychain {

  func getString(key: String) -> String?

  func getData(key: String) -> Data?

  func getDouble(key: String) -> Double?

  func set(_ value: String, key: String)

  func set(_ value: Data, key: String)

  func set(_ value: Double, key: String)

}

public struct InsteonKeychain: Keychain {

  private let keychain = KeychainAccess.Keychain(
    service: "com.brandtdaniels.insteon"
  )

  public init() {}

  public func getString(key: String) -> String? {

    do {
      return try keychain.getString(key)

    } catch let error {

      print(error)

    }

    return nil

  }

  public func getData(key: String) -> Data? {

    do {

      return try keychain.getData(key)

    } catch let error {

      print(error)

    }

    return nil

  }

  public func getDouble(key: String) -> Double? {

    if let data = getData(key: key) {

      return data.withUnsafeBytes { $0.load(as: Double.self) }

    }

    return nil

  }

  public func set(_ value: String, key: String) {

    do {

      try keychain.set(value, key: key)

    } catch let error {

      print(error)

    }

  }

  public func set(_ value: Data, key: String) {

    do {

      try keychain.set(value, key: key)

    } catch let error {

      print(error)

    }

  }

  public func set(_ value: Double, key: String) {

    var double = value

    let data = Data(bytes: &double,
                    count: MemoryLayout.size(ofValue: value))

    set(data, key: key)

  }

}
