import InsteonProtocol

/// One entry of the Hub Pro's device list.
public struct HubProListedDevice: Hashable, Sendable {

  /// The device's Insteon address.
  public var address: InsteonAddress

  /// The name the Hub Pro keeps for the device.
  public var name: String

  /// The kind of device, as the Hub Pro names it.
  public var deviceType: String

  /// Whether the entry is the Hub Pro's own modem, which is listed with its devices.
  public var isModem: Bool

  /// Creates an entry.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - name: The Hub Pro's name for it.
  ///   - deviceType: The kind of device.
  ///   - isModem: Whether it is the Hub Pro's own modem.
  public init(address: InsteonAddress, name: String, deviceType: String, isModem: Bool) {

    self.address = address
    self.name = name
    self.deviceType = deviceType
    self.isModem = isModem

  }

}

/// What the Hub Pro reports about one device: its identity and the commands it lists for it.
public struct HubProDescription: Hashable, Sendable {

  /// A command the Hub Pro lists for a device, with the names of its parameters.
  public struct Command: Hashable, Sendable {

    /// The command's key.
    public var name: String

    /// The names of the parameters the command takes.
    public var parameters: [String]

    /// Creates a command.
    ///
    /// - Parameters:
    ///   - name: The key.
    ///   - parameters: The parameters' names.
    public init(name: String, parameters: [String] = []) {

      self.name = name
      self.parameters = parameters

    }

  }

  /// The device's Insteon address.
  public var address: InsteonAddress

  /// The name the Hub Pro keeps for the device.
  public var name: String

  /// The kind of device, as the Hub Pro names it.
  public var deviceType: String

  /// The category the device reported, or `nil`.
  public var category: UInt8?

  /// The subcategory the device reported, or `nil`.
  public var subcategory: UInt8?

  /// The firmware version the device reported, or `nil`.
  public var firmwareVersion: UInt8?

  /// The product's SKU, such as a model number, or `nil`.
  public var sku: String?

  /// The commands the Hub Pro lists for the device, in its order.
  public var commands: [Command]

  /// Creates a description.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - name: The Hub Pro's name for it.
  ///   - deviceType: The kind of device.
  ///   - category: The category it reported.
  ///   - subcategory: The subcategory it reported.
  ///   - firmwareVersion: The firmware version it reported.
  ///   - sku: The product's SKU.
  ///   - commands: The commands the Hub Pro lists for it.
  public init(
    address: InsteonAddress,
    name: String,
    deviceType: String,
    category: UInt8?,
    subcategory: UInt8?,
    firmwareVersion: UInt8?,
    sku: String?,
    commands: [Command]
  ) {

    self.address = address
    self.name = name
    self.deviceType = deviceType
    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion
    self.sku = sku
    self.commands = commands

  }

  /// The keys of the commands the Hub Pro lists for the device.
  public var commandNames: [String] {

    commands.map(\.name)

  }

  /// The parameters a listed command takes.
  ///
  /// - Parameter name: The command's key.
  /// - Returns: The parameters' names, or none for a command that isn't listed.
  public func parameters(of name: String) -> [String] {

    commands.first { $0.name == name }?.parameters ?? []

  }

  /// Whether the Hub Pro lists a command for the device.
  ///
  /// - Parameter command: The command.
  /// - Returns: `true` when the command's key is listed.
  public func offers(_ command: HubProCommand) -> Bool {

    commandNames.contains(command.key)

  }

  /// Whether a listed command takes a level.
  ///
  /// - Parameter command: The command.
  /// - Returns: `true` when the Hub Pro lists the command with the level parameter.
  public func takesLevel(_ command: HubProCommand) -> Bool {

    parameters(of: command.key).contains(HubProCommand.levelParameter)

  }

}

/// What the Hub Pro answered to a command it ran.
public struct HubProCommandResult: Hashable, Sendable {

  /// The level the device reported, from 0 through 255, when the answer carries one.
  public var onLevel: UInt8?

  /// The link delta the device reported, when the answer carries one.
  public var linkDelta: UInt8?

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - onLevel: The level the device reported.
  ///   - linkDelta: The link delta the device reported.
  public init(onLevel: UInt8?, linkDelta: UInt8?) {

    self.onLevel = onLevel
    self.linkDelta = linkDelta

  }

}

/// Why a command wasn't confirmed by the Hub Pro.
public enum HubProControlError: Error, Hashable, Sendable {

  /// The Hub Pro doesn't know the device.
  case unknownDevice(InsteonAddress)

  /// The Hub Pro says the device doesn't support the command.
  case notSupported(command: String, device: InsteonAddress)

  /// The Hub Pro answered without the result `successful`, so whether the command took effect
  /// is unknown.
  case notConfirmed

}
