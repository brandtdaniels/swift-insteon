import Foundation
import InsteonCore
import InsteonService

/// A network that answers from a list, keeps each device's level as commands change it, and records
/// each command it is asked to send. A test can hold commands to run something while one is in flight.
///
/// A network built over the in-memory modem replaces it where the test is about the network.
actor ScriptedNetwork: DeviceQuerying, DeviceCommanding {

  /// What a command's receipt says.
  enum Reply: Sendable {
    /// An acknowledgment with no status, as the service answers a switching command.
    case acknowledged
    /// An acknowledgment that carries the status the device reported.
    case acknowledgedWithStatus(DeviceStatus)
    /// A read, which a switching command doesn't answer with.
    case read
  }

  private var listed: [ServiceDevice]
  private var refusal: (any Error)?
  private var listFailure: (any Error)?
  private var reply: Reply = .acknowledged
  private var levelAfterCommand: UInt8?
  private var sent: [ServiceCommand] = []
  private var isHolding = false
  private var held: [CheckedContinuation<Void, Never>] = []
  private var announced = 0
  private var observed = 0
  private var watcher: CheckedContinuation<Void, Never>?

  init(devices: [ServiceDevice], refusal: (any Error)? = nil, listFailure: (any Error)? = nil) {
    listed = devices
    self.refusal = refusal
    self.listFailure = listFailure
  }

  var commands: [ServiceCommand] { sent }

  func setDevices(_ devices: [ServiceDevice]) { listed = devices }
  func setListFailure(_ error: (any Error)?) { listFailure = error }
  func setReply(_ reply: Reply) { self.reply = reply }

  /// Makes a command leave the device at this level, as a dimmer that ramps or limits it might.
  func leaveDevicesAt(_ level: UInt8) { levelAfterCommand = level }

  /// Makes each command wait, after it is recorded, until ``release()``.
  func holdCommands() { isHolding = true }

  /// Returns once a command is waiting.
  func waitForHeldCommand() async {
    if announced == observed { await withCheckedContinuation { watcher = $0 } }
    observed += 1
  }

  /// Lets every waiting command finish, and stops holding.
  func release() {
    isHolding = false
    let waiting = held
    held = []
    for continuation in waiting { continuation.resume() }
  }

  func devices() async throws -> [ServiceDevice] {
    if let listFailure { throw listFailure }
    return listed
  }

  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    if let refusal { throw refusal }
    sent.append(command)
    if isHolding {
      announced += 1
      watcher?.resume()
      watcher = nil
      await withCheckedContinuation { held.append($0) }
    }
    if let index = listed.firstIndex(where: { $0.address == command.address }) {
      let device = listed[index]
      let level: UInt8 = levelAfterCommand ?? (command.action == .on ? 0xFF : 0x00)
      listed[index] = ServiceDevice(
        address: device.address, productName: device.productName, canTurnOnAndOff: device.canTurnOnAndOff, canDim: device.canDim,
        value: level, lastAnsweredAt: nil)
    }
    switch reply {
    case .acknowledged: return CommandReceipt(address: command.address, outcome: .acknowledged, status: nil)
    case let .acknowledgedWithStatus(status): return CommandReceipt(address: command.address, outcome: .acknowledged, status: status)
    case .read: return CommandReceipt(address: command.address, outcome: .read, status: nil)
    }
  }
}
