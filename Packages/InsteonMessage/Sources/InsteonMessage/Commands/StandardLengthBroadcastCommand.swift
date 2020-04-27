//
//  StandardLengthBroadcastCommand.swift
//  
//
//  Created by Brandt Daniels on 4/26/20.
//

public enum StandardLengthBroadcastCommand {

    case setButtonPressedResponder

    case setButtonPressedController

    case testPowerlinePhase

    case heartbeat(batteryLevel: UInt8)

    case deviceStatusChanged

    public var command: Command {

        switch self {

        case .setButtonPressedResponder:
            return Command(command1: 0x01)

        case .setButtonPressedController:
            return Command(command1: 0x02)

        case .testPowerlinePhase:
            return Command(command1: 0x03)

        case .heartbeat(batteryLevel: let batteryLevel):
            return Command(command1: 0x04, command2: batteryLevel)

        case .deviceStatusChanged:
            return Command(command1: 0x27)

        }

    }

}
