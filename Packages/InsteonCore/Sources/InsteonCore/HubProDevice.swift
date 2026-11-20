import Foundation
import InsteonDeviceCatalog
import InsteonHubPro
import InsteonModem
import InsteonProtocol

/// One device on a ``HubProNetwork``.
///
/// What the device can do comes from the Insteon device catalog's description of it, and which of
/// those operations the Hub Pro runs for it from the commands the Hub Pro lists for it. An
/// operation either one rules out is refused with ``DeviceControlError/unsupported(_:product:)``
/// before anything is sent.
///
/// A command that changes the device is sent once. If the Hub Pro doesn't confirm it, the device
/// may have changed, so the error is `ModemError.deviceTimedOut`, as for a device that doesn't
/// answer a modem, and the command is not sent again.
public struct HubProDevice: DeviceOperating {

  /// The device's address.
  public let address: InsteonAddress

  let network: HubProNetwork

  init(address: InsteonAddress, network: HubProNetwork) {

    self.address = address
    self.network = network

  }

  // MARK: - What the device is

  /// What the device can do, as the catalog describes it, and the Hub Pro lists for it.
  ///
  /// The device's settings are left out, since the Hub Pro reads and writes none.
  public func capabilities() async throws -> DeviceCapabilities {

    let model = await controlModel()
    var capabilities = Device.capabilities(of: model)

    capabilities.settings = []
    capabilities.canBeep = await network.description(of: address)?.offers(.beep) ?? false

    return capabilities

  }

  // MARK: - Read

  /// Reads the device's main group with a status request.
  ///
  /// - Throws: ``DeviceControlError`` if the unit doesn't list the request for the device or
  ///   doesn't list the device, and `ModemError.deviceTimedOut` if it doesn't confirm.
  public func status() async throws -> DeviceStatus {

    let model = await controlModel()
    let result = try await run(.statusRequest, as: .status, model: model)

    guard let value = result.onLevel else {

      throw ModemError.deviceTimedOut(address)

    }

    await network.recordAnswer(of: address, level: value)

    let delta = result.linkDelta ?? 0

    guard let group = model.mainGroup else {

      return DeviceStatus(group: nil, value: value, allLinkDatabaseDelta: delta, reading: .raw, isOn: value != 0)

    }

    let number = Int(group.number.rawValue)

    guard let state = group.type.state else {

      return DeviceStatus(group: number, value: value, allLinkDatabaseDelta: delta, reading: .raw, isOn: value != 0)

    }

    let reply = model.standardCommand(named: state.command)?.reply
    let reading = Device.reading(of: value, group: group, in: model, reply: reply)

    return DeviceStatus(group: number, value: value, allLinkDatabaseDelta: delta, reading: reading.reading, isOn: reading.isOn)

  }

  /// Checks that the device answers, if the unit lists a ping for it.
  public func ping() async throws {

    let model = await controlModel()

    _ = try await run(.ping, as: .status, model: model)

    await network.recordAnswer(of: address, level: nil)

  }

  // MARK: - Actuate

  /// Turns the main group on.
  ///
  /// - Parameter level: The level in percent, or `nil` for fully on. A level is sent only to a
  ///   device that dims, and the result says when it wasn't used.
  public func turnOn(level: Int?) async throws -> DeviceTurnOnResult {

    try await turnOn(level: level, fast: false)

  }

  /// Turns the main group off.
  public func turnOff() async throws {

    let model = await controlModel()
    let group = try switchable(model, for: .turnOff)

    _ = try await run(.off, as: .turnOff, model: model)

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(group) ? 0 : nil)

  }

  /// Turns the main group on without ramping, if the unit lists FastOn for the device.
  public func turnOnFast(level: Int?) async throws -> DeviceTurnOnResult {

    try await turnOn(level: level, fast: true)

  }

  /// Turns the main group off without ramping, if the unit lists FastOff for the device.
  public func turnOffFast() async throws -> DeviceTurnOffResult {

    let model = await controlModel()
    let group = try switchable(model, for: .turnOffFast)

    _ = try await run(.fastOff, as: .turnOffFast, model: model)

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(group) ? 0 : nil)

    return DeviceTurnOffResult(group: Int(group.number.rawValue), isCommandDescribed: true)

  }

  /// Makes the device beep, if the unit lists Beep for it.
  public func beep() async throws -> DeviceBeepResult {

    let model = await controlModel()

    _ = try await run(.beep, as: .beep, model: model)

    await network.recordAnswer(of: address, level: nil)

    return DeviceBeepResult(isListed: true)

  }

  // MARK: - Helpers

  private func turnOn(level: Int?, fast: Bool) async throws -> DeviceTurnOnResult {

    let operation: DeviceOperation = fast ? .turnOnFast : .turnOn
    let model = await controlModel()
    let group = try switchable(model, for: operation)
    let dims = model.canDim(group)
    var value: UInt8 = 0xFF

    if dims, let level {

      value = LightLevel.level(percent: level)

    }

    // The level goes only to a command the unit lists with a level.
    let description = await network.description(of: address)
    let template: HubProCommand = fast ? .fastOn(level: nil) : .on(level: nil)
    let command: HubProCommand = description?.takesLevel(template) == true ? (fast ? .fastOn(level: value) : .on(level: value)) : template

    _ = try await run(command, as: operation, model: model)

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(group) ? value : nil)

    return DeviceTurnOnResult(
      group: Int(group.number.rawValue),
      level: dims && level != nil ? LightLevel.percent(level: value) : nil,
      ignoredLevel: dims ? nil : level
    )

  }

  /// The model of what the device can do, from the catalog's description of its identity.
  private func controlModel() async -> DeviceControlModel {

    DeviceControlModel.make(await network.registry.device(address)?.deviceDescription)

  }

  /// The main group, when the device turns on and off.
  private func switchable(_ model: DeviceControlModel, for operation: DeviceOperation) throws -> DeviceControlModel.Group {

    guard model.description != nil else {

      throw DeviceControlError.notIdentified(operation)

    }

    guard let group = model.mainGroup, model.canTurnOnAndOff(group) else {

      throw DeviceControlError.unsupported(operation, product: model.product)

    }

    return group

  }

  /// Sends a command the unit lists for the device, once.
  private func run(_ command: HubProCommand, as operation: DeviceOperation, model: DeviceControlModel) async throws -> HubProCommandResult {

    guard let description = await network.description(of: address) else {

      throw DeviceControlError.notLinked

    }

    guard description.offers(command) else {

      throw DeviceControlError.unsupported(operation, product: model.product)

    }

    do {

      return try await network.perform(command, on: address)

    } catch is CancellationError {

      throw CancellationError()

    } catch HubProControlError.unknownDevice {

      throw DeviceControlError.notLinked

    } catch HubProControlError.notSupported {

      throw DeviceControlError.unsupported(operation, product: model.product)

    } catch {

      // The command may have reached the device, so nothing says whether it took effect.
      throw ModemError.deviceTimedOut(address)

    }

  }

}
