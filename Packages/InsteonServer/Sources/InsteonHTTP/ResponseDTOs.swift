import Foundation
import InsteonCore
import InsteonService

/// Versioning and coding are transport policy, separate from the service's domain values.
struct DeviceListDTO: Encodable {
  let version = 1
  let devices: [DeviceDTO]
  init(_ devices: [ServiceDevice]) { self.devices = devices.map(DeviceDTO.init) }
}

struct DeviceDTO: Encodable {
  let address: String
  let productName: String?
  let canTurnOnAndOff: Bool
  let canDim: Bool
  let value: UInt8?
  let lastAnsweredAt: Date?
  init(_ device: ServiceDevice) {
    address = device.address.description; productName = device.productName
    canTurnOnAndOff = device.canTurnOnAndOff; canDim = device.canDim
    value = device.value; lastAnsweredAt = device.lastAnsweredAt
  }
}

struct StatusDTO: Encodable {
  let group: Int?
  let kind: String
  let value: UInt8
  let isOn: Bool
  let percent: Int?
  let label: String?
  init(_ status: DeviceStatus) {
    group = status.group; value = status.value; isOn = status.isOn
    switch status.reading {
    case let .percent(number): kind = "percent"; percent = number; label = nil
    case .onOff: kind = "onOff"; percent = nil; label = nil
    case let .named(name): kind = "named"; percent = nil; label = name
    case .raw: kind = "raw"; percent = nil; label = nil
    }
  }
}

struct ReceiptDTO: Encodable {
  let version = 1
  let address: String
  let outcome: String
  let status: StatusDTO?
  let persistence: String
  init(_ receipt: CommandReceipt) {
    address = receipt.address.description
    outcome = receipt.outcome == .acknowledged ? "acknowledged" : "read"
    status = receipt.status.map(StatusDTO.init)
    switch receipt.persistence {
    case .notConfigured: persistence = "notConfigured"
    case .notAttempted: persistence = "notAttempted"
    case .saved: persistence = "saved"
    case .failed: persistence = "failed"
    }
  }
}

struct EventDTO: Encodable {
  let version = 1
  let kind: String
  let address: String
  let group: Int?
  let name: String?
  let productName: String?
  init(_ event: ServiceEvent) {
    switch event {
    case let .identified(address, productName):
      kind = "identified"; self.address = address.description; group = nil; name = nil; self.productName = productName
    case let .setButtonPressed(address):
      kind = "setButtonPressed"; self.address = address.description; group = nil; name = nil; productName = nil
    case let .groupCommand(address, group, name):
      kind = "groupCommand"; self.address = address.description; self.group = group; self.name = name; productName = nil
    case let .heartbeat(address, group):
      kind = "heartbeat"; self.address = address.description; self.group = group; name = nil; productName = nil
    case let .statusChanged(address):
      kind = "statusChanged"; self.address = address.description; group = nil; name = nil; productName = nil
    }
  }
}
