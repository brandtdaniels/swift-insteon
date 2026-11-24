import InsteonProtocol

/// What a front end does with one device, whatever carries the request to it.
///
/// A device on a modem is reached with Insteon messages, and a device on a Hub Pro with the
/// Hub Pro's commands. The front end asks for the operation, and the implementation decides how
/// it is sent, from the Insteon device catalog's description of the device. An operation the
/// device doesn't offer is refused with ``DeviceControlError`` before anything is sent.
///
/// ```swift
/// func dim(_ device: some DeviceOperating) async throws {
///   _ = try await device.turnOn(level: 30)
/// }
/// ```
public protocol DeviceOperating: Sendable {

  /// The device's address.
  var address: InsteonAddress { get }

  /// What the device can do, as the catalog describes it.
  func capabilities() async throws -> DeviceCapabilities

  /// Reads the device's main group.
  func status() async throws -> DeviceStatus

  /// Checks that the device answers.
  func ping() async throws

  /// Turns the main group on, at a level in percent if given.
  func turnOn(level: Int?) async throws -> DeviceTurnOnResult

  /// Turns the main group off.
  func turnOff() async throws

  /// Turns the main group on without ramping, at a level in percent if given.
  func turnOnFast(level: Int?) async throws -> DeviceTurnOnResult

  /// Turns the main group off without ramping.
  func turnOffFast() async throws -> DeviceTurnOffResult

  /// Makes the device beep.
  func beep() async throws -> DeviceBeepResult

}

/// A ``Device`` on a modem, as ``DeviceOperating``.
///
/// Each operation is the device's own, on its main group.
public struct ModemDeviceOperations: DeviceOperating {

  /// The device.
  public let device: Device

  /// Creates the operations of a device.
  ///
  /// - Parameter device: The device.
  public init(_ device: Device) {

    self.device = device

  }

  public var address: InsteonAddress {

    device.address

  }

  public func capabilities() async throws -> DeviceCapabilities {

    try await device.capabilities()

  }

  public func status() async throws -> DeviceStatus {

    try await device.status()

  }

  public func ping() async throws {

    try await device.ping()

  }

  public func turnOn(level: Int?) async throws -> DeviceTurnOnResult {

    try await device.turnOn(level: level)

  }

  public func turnOff() async throws {

    try await device.turnOff()

  }

  public func turnOnFast(level: Int?) async throws -> DeviceTurnOnResult {

    try await device.turnOnFast(level: level)

  }

  public func turnOffFast() async throws -> DeviceTurnOffResult {

    try await device.turnOffFast()

  }

  public func beep() async throws -> DeviceBeepResult {

    try await device.beep()

  }

}
