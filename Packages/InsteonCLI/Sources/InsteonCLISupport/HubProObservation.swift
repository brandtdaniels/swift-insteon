import Foundation
import InsteonCore

/// A command a Hub Pro lists for a device, with the names of its parameters.
public struct HubProObservedCommand: Hashable, Sendable {

  /// The command's key.
  public var name: String

  /// The names of the parameters it takes.
  public var parameters: [String]

  /// Creates a command.
  ///
  /// - Parameters:
  ///   - name: The key.
  ///   - parameters: The parameters' names.
  public init(name: String, parameters: [String]) {

    self.name = name
    self.parameters = parameters

  }

}

/// What a Hub Pro reports about one of its devices, without the device's address, name or place.
public struct HubProObservedDevice: Hashable, Sendable {

  /// The kind of device, as the Hub Pro names it.
  public var deviceType: String

  /// The category, such as `"0x01"`, or `nil` if the Hub Pro reports none.
  public var category: String?

  /// The subcategory, or `nil`.
  public var subcategory: String?

  /// The firmware version, or `nil`.
  public var firmware: String?

  /// The product's SKU, or `nil`.
  public var sku: String?

  /// The product the Insteon device catalog names for the device, or `nil` if it names none.
  public var model: String?

  /// The commands the Hub Pro lists for the device, in its order.
  public var commands: [HubProObservedCommand]

  /// Creates what the Hub Pro reports about a device.
  public init(deviceType: String, category: String?, subcategory: String?, firmware: String?, sku: String?, model: String?, commands: [HubProObservedCommand]) {

    self.deviceType = deviceType
    self.category = category
    self.subcategory = subcategory
    self.firmware = firmware
    self.sku = sku
    self.model = model
    self.commands = commands

  }

}

/// What reading a Hub Pro found out about it and its devices.
///
/// It has no place for an address, a name or a place, so none can end up in the file.
public struct HubProFindings: Hashable, Sendable {

  /// The version of the Hub Pro's configuration, or `nil` if it reports none.
  public var configVersion: String?

  /// The version of the Hub Pro's server, or `nil`.
  public var serverVersion: String?

  /// The kinds of device its list names, its own modem's included, each once, in order.
  public var deviceTypes: [String]

  /// Each device it lists besides its own modem, in the order of category, subcategory and
  /// firmware, not the order the Hub Pro lists them in.
  public var devices: [HubProObservedDevice]

  /// Creates findings.
  public init(configVersion: String?, serverVersion: String?, deviceTypes: [String], devices: [HubProObservedDevice]) {

    self.configVersion = configVersion
    self.serverVersion = serverVersion
    self.deviceTypes = deviceTypes
    self.devices = devices

  }

}

/// Reads a Hub Pro, with requests that only read.
public enum HubProObservationRun {

  /// Reads the Hub Pro's settings and device list, and describes each device it lists.
  ///
  /// Every request is a `GET` that changes nothing: no command is sent, and nothing is added,
  /// removed or updated. Requests go one at a time.
  ///
  /// - Parameters:
  ///   - network: The Hub Pro's network, not yet opened.
  ///   - productName: The product the catalog names for an identity, or `nil`.
  /// - Returns: What it found.
  /// - Throws: The errors of opening a Hub Pro's network, such as `HubProError`.
  public static func observe(
    _ network: HubProNetwork,
    productName: (DeviceCategory, DeviceSubcategory, FirmwareVersion?) -> String?
  ) async throws -> HubProFindings {

    try await network.open()

    let versions = await network.softwareVersions
    let listing = await network.listing()
    var devices: [HubProObservedDevice] = []

    for entry in listing where !entry.isModem {

      guard let description = await network.description(of: entry.address) else {

        continue

      }

      var model: String?

      if let category = description.category, let subcategory = description.subcategory {

        model = productName(DeviceCategory(rawValue: category), DeviceSubcategory(rawValue: subcategory), description.firmwareVersion.map { FirmwareVersion(rawValue: $0) })

      }

      devices.append(HubProObservedDevice(
        deviceType: ObservationRedaction.strip(description.deviceType),
        category: description.category.map(Hex.byte),
        subcategory: description.subcategory.map(Hex.byte),
        firmware: description.firmwareVersion.map(Hex.byte),
        sku: description.sku.map(plain),
        model: model,
        commands: description.commands.map { HubProObservedCommand(name: ObservationRedaction.strip($0.name), parameters: $0.parameters.map(ObservationRedaction.strip)) }
      ))

    }

    devices.sort { left, right in

      (left.category ?? "", left.subcategory ?? "", left.firmware ?? "", left.deviceType) < (right.category ?? "", right.subcategory ?? "", right.firmware ?? "", right.deviceType)

    }

    return HubProFindings(
      configVersion: versions.map { plain($0.config.version) },
      serverVersion: versions.map { plain($0.server.version) },
      deviceTypes: Array(Set(listing.map { ObservationRedaction.strip($0.deviceType) })).sorted(),
      devices: devices
    )

  }

  /// A version or model number as the Hub Pro reports it when it looks like one, and the
  /// placeholder when it holds anything else, such as an address. Letters, digits, dots,
  /// underscores and hyphens, up to 32, are kept as they are: a model number such as 91A1D2 would
  /// otherwise read as an address.
  private static func plain(_ text: String) -> String {

    let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._-")

    guard !text.isEmpty, text.count <= 32, text.unicodeScalars.allSatisfy(allowed.contains) else {

      return ObservationRedaction.placeholder

    }

    return text

  }

}

/// What `insteon observe` writes for a Hub Pro: a small JSON file that records its software
/// versions and what it reports about its devices, for a person to share so the Insteon device
/// catalog can learn which firmware versions behave alike.
///
/// The file holds no address of a device, the modem or the Hub Pro, no host, no name or place a
/// person gave a device and no account data. The format is described by
/// `Schemas/insteon-hubpro-observation-1.schema.json` in the InsteonCLI package.
public struct HubProObservation: Encodable, Hashable, Sendable {

  /// The format's name and version, as the file's `format` holds it.
  public static let format: String = "insteon-hubpro-observation/1"

  /// The program that made the observation.
  public let tool: ObservationTool

  /// The version of the Insteon device catalog used to name the devices.
  public let catalogVersion: String

  /// What the Hub Pro reported.
  public let findings: HubProFindings

  /// The person's note, or `nil`.
  public let note: String?

  /// The day of the observation, as `YYYY-MM-DD` in the calendar's time zone.
  public let observedOn: String

  /// Builds the file from what reading the Hub Pro found.
  ///
  /// - Parameters:
  ///   - findings: What it found.
  ///   - tool: The program that read it.
  ///   - catalogVersion: The version of the catalog that named the devices.
  ///   - note: The person's note, or `nil`.
  ///   - observedOn: The moment of the observation; only its date is kept.
  ///   - calendar: The calendar, and so the time zone, whose date is kept. Defaults to the
  ///     current calendar.
  /// - Throws: ``ObservationError/noteHoldsAddress`` if the note looks like it holds an
  ///   address or a host name.
  public init(
    _ findings: HubProFindings,
    tool: ObservationTool,
    catalogVersion: String,
    note: String?,
    observedOn: Date,
    calendar: Calendar = .current
  ) throws(ObservationError) {

    if let note, ObservationRedaction.strip(note) != note {

      throw ObservationError.noteHoldsAddress

    }

    let parts: DateComponents = calendar.dateComponents([.year, .month, .day], from: observedOn)

    self.tool = tool
    self.catalogVersion = catalogVersion
    self.findings = findings
    self.note = note
    self.observedOn = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)

  }

  /// The file's JSON: pretty-printed, with sorted keys.
  ///
  /// - Returns: The JSON, ending with a newline.
  /// - Throws: An encoding error, which doesn't happen for these values.
  public func json() throws -> Data {

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    return try encoder.encode(self) + Data("\n".utf8)

  }

  private enum CodingKeys: String, CodingKey {

    case format, tool, catalog, unit, devices, note, observedOn

  }

  private enum NameKeys: String, CodingKey {

    case name, version

  }

  private enum UnitKeys: String, CodingKey {

    case configVersion, serverVersion, deviceTypes

  }

  private enum DeviceKeys: String, CodingKey {

    case deviceType, category, subcategory, firmware, sku, model, commands

  }

  private enum CommandKeys: String, CodingKey {

    case name, parameters

  }

  public func encode(to encoder: any Encoder) throws {

    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(Self.format, forKey: .format)

    var toolContainer = container.nestedContainer(keyedBy: NameKeys.self, forKey: .tool)

    try toolContainer.encode(tool.name, forKey: .name)
    try toolContainer.encode(tool.version, forKey: .version)

    var catalogContainer = container.nestedContainer(keyedBy: NameKeys.self, forKey: .catalog)

    try catalogContainer.encode(catalogVersion, forKey: .version)

    // Optional values are encoded as null, so the file always has every key.
    var unit = container.nestedContainer(keyedBy: UnitKeys.self, forKey: .unit)

    try unit.encode(findings.configVersion, forKey: .configVersion)
    try unit.encode(findings.serverVersion, forKey: .serverVersion)
    try unit.encode(findings.deviceTypes, forKey: .deviceTypes)

    var devices = container.nestedUnkeyedContainer(forKey: .devices)

    for device in findings.devices {

      var each = devices.nestedContainer(keyedBy: DeviceKeys.self)

      try each.encode(device.deviceType, forKey: .deviceType)
      try each.encode(device.category, forKey: .category)
      try each.encode(device.subcategory, forKey: .subcategory)
      try each.encode(device.firmware, forKey: .firmware)
      try each.encode(device.sku, forKey: .sku)
      try each.encode(device.model, forKey: .model)

      var commands = each.nestedUnkeyedContainer(forKey: .commands)

      for command in device.commands {

        var one = commands.nestedContainer(keyedBy: CommandKeys.self)

        try one.encode(command.name, forKey: .name)
        try one.encode(command.parameters, forKey: .parameters)

      }

    }

    try container.encodeIfPresent(note, forKey: .note)
    try container.encode(observedOn, forKey: .observedOn)

  }

}
