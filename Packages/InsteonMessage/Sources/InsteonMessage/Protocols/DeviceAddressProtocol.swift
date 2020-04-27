//
//  DeviceAddressProtocol.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public protocol DeviceAddressProtocol {

    var highByte: UInt8 { get }

    var middleByte: UInt8 { get }

    var lowByte: UInt8 { get }

}
