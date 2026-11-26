import Foundation
import InsteonService

/// A home that answers from a list and records each command it is asked to send.
///
/// A home built over the in-memory modem replaces it when the library offers one.
final class ScriptedHome: DeviceQuerying, DeviceCommanding, @unchecked Sendable {
  private let listed: [ServiceDevice]
  private let refusal: (any Error)?
  private let listFailure: (any Error)?
  private let lock = NSLock()
  private var sent: [ServiceCommand] = []

  init(devices: [ServiceDevice], refusal: (any Error)? = nil, listFailure: (any Error)? = nil) {
    listed = devices
    self.refusal = refusal
    self.listFailure = listFailure
  }

  var commands: [ServiceCommand] { lock.withLock { sent } }

  func devices() async throws -> [ServiceDevice] {
    if let listFailure { throw listFailure }
    return listed
  }

  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    if let refusal { throw refusal }
    lock.withLock { sent.append(command) }
    return CommandReceipt(address: command.address, outcome: .acknowledged, status: nil)
  }
}
