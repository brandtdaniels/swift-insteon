import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// One device on a ``DeviceNetwork``, controlled as the Insteon device catalog describes it:
/// the way a front end turns it on and off, reads its status and settings, and changes them.
///
/// Get one from the network with ``DeviceNetwork/device(_:beforeIdentifying:)``. Every
/// decision about what the device can do comes from the catalog's group types for it: whether
/// a level means anything to a group, which command turns it on, and how to read its state.
/// A device the catalog doesn't describe is controlled by its category, as a dimmer when it
/// reported dimmable lighting control, `0x01`, and as a relay when it reported switched
/// lighting control, `0x02`. Any other device can only be pinged, and have its status read as
/// the raw byte Light Status Request reports.
///
/// ```swift
/// let lamp = network.device(InsteonAddress(0x1A, 0x2B, 0x3C))
///
/// let result = try await lamp.turnOn(level: 50)
/// if result.ignoredLevel != nil {
///   print("The lamp only turns on and off.")
/// }
///
/// let status = try await lamp.status()
/// print(status.isOn, status.percent ?? 100)
/// ```
///
/// An operation that needs to know what the device is looks it up in the network's
/// ``DeviceNetwork/registry``, and asks the device with ID Request when the registry doesn't
/// know it, through ``DeviceNetwork/identify(_:)``, which records what it reports. Status, and
/// turning a device on or off, record the device's level and when it answered in the network's
/// state, so the network's ``DeviceNetwork/snapshot()`` keeps them.
///
/// A device is a value: it holds only its address and the network, and keeps no state of its
/// own, since everything it learns belongs to the network, where every device and front end
/// sees it. So it's cheap to create for each operation, safe to pass between tasks, and its
/// operations run on the caller's task rather than wait their turn on another actor.
public struct Device: Sendable {

  /// The device's address.
  public let address: InsteonAddress

  /// The network the device is reached through.
  public let network: DeviceNetwork

  /// Called before the device is asked for its identity.
  let beforeIdentifying: @Sendable () -> Void

  /// Creates a device on a network.
  ///
  /// ``DeviceNetwork/device(_:beforeIdentifying:)`` creates one too.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - network: The network the device is reached through.
  ///   - beforeIdentifying: Called before the device is asked for its identity, so an app can
  ///     say why it's waiting. Defaults to doing nothing.
  public init(address: InsteonAddress, network: DeviceNetwork, beforeIdentifying: @escaping @Sendable () -> Void = {}) {

    self.address = address
    self.network = network
    self.beforeIdentifying = beforeIdentifying

  }

  var modem: any LinkingModem {

    network.modem

  }

  // MARK: - What the device is

  /// What the catalog says about the device, from the network's registry, or else from the
  /// identity the device reports to ID Request.
  ///
  /// - Returns: What the catalog says, or `nil` if the registry doesn't know the device and
  ///   it didn't report an identity, such as when it didn't answer or rejected a request.
  /// - Throws: ``DeviceControlError/notLinked`` when the device rejects the modem as an i2CS
  ///   device does before it's linked; `CancellationError` if the task is canceled while the
  ///   device is asked; and the errors of the modem and the connection to it, such as
  ///   `ModemError.connectionClosed`.
  public func info() async throws -> DeviceInfo? {

    let description: DeviceDescription? = try await deviceDescription()

    return description.map { (description: DeviceDescription) -> DeviceInfo in DeviceInfo(description) }

  }

  /// The catalog's description of the device, the way ``info()`` finds it.
  func deviceDescription() async throws -> DeviceDescription? {

    if let known = await network.registry.device(address) {

      return known.deviceDescription

    }

    beforeIdentifying()

    let identification: DeviceIdentification

    do {

      identification = try await network.identify(address)

    } catch let error as ModemError {

      // Only what the device itself did means its identity isn't known; the modem's and the
      // connection's errors are the caller's to handle.
      switch error {
      case .deviceRejected, .deviceTimedOut:
        return nil
      default:
        throw error
      }

    }

    guard identification.acceptsModem else {

      throw DeviceControlError.notLinked

    }

    return await network.registry.device(address)?.deviceDescription

  }

  /// What the device can do, for a front end to decide what to show.
  ///
  /// A group can be turned on and off, or has a status, only when its commands reach it apart
  /// from the device's other groups.
  ///
  /// - Returns: The device's groups, whether it dims and beeps, and its settings with their
  ///   controls.
  /// - Throws: The errors of ``info()``.
  public func capabilities() async throws -> DeviceCapabilities {

    let model: DeviceControlModel = try await controlModel()
    let commands: CommandSet? = model.commandSet

    let groups: [DeviceGroup] = model.groups.map { (group: DeviceControlModel.Group) -> DeviceGroup in

      DeviceGroup(
        number: Int(group.number.rawValue),
        name: group.name,
        typeLabel: group.type.label,
        kind: DeviceGroupKind(rawValue: group.type.kind.rawValue),
        canDim: model.canDim(group),
        canTurnOnAndOff: model.canTurnOnAndOff(group),
        hasStatus: model.canRead(group),
        actionLabels: group.type.actions.map { (action: GroupType.Action) -> String in action.label },
        outputs: (group.type.outputs?.bits ?? []).map { (output: GroupType.Outputs.Output) -> DeviceOutput in

          DeviceOutput(key: output.name.rawValue, label: output.label)

        },
        outputsActiveWhen: group.type.outputs?.activeWhen.map { (condition: DeviceProfile.Group.Condition) -> DeviceFlagCondition in

          DeviceFlagCondition(flag: condition.flag.rawValue, isSet: condition.isSet)

        },
        armModes: group.type.armModes.map(\.rawValue)
      )

    }

    var settings: [DeviceSetting] = []

    if let commands {

      settings = commands.settingItems.map { (item: SettingItem) -> DeviceSetting in SettingPresentation.setting(for: item, in: commands) }

    }

    let source: DeviceCapabilities.Source

    switch model.source {
    case .catalog:
      source = .catalog
    case .categoryFallback:
      source = .categoryFallback
    case .uncontrolled:
      source = .uncontrolled
    }

    return DeviceCapabilities(
      productName: model.description?.displayName,
      isIdentified: model.description != nil,
      source: source,
      groups: groups,
      mainGroupNumber: model.mainGroupNumber.map { (number: AllLinkGroupNumber) -> Int in Int(number.rawValue) },
      canBeep: commands.map { (commands: CommandSet) -> Bool in Self.sendableBeep(in: commands) != nil } ?? false,
      settings: settings
    )

  }

}
