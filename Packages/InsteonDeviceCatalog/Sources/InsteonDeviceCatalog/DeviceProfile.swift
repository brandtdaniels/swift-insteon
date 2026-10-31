import InsteonProtocol

/// What one Insteon product is and can do: its model, the identities it reports, its ALL-Link
/// groups and its capabilities.
///
/// A ``DeviceCatalog`` finds a device's profile from the category, subcategory and firmware
/// version it reports, so an app can support a product by what its profile says rather than
/// by code written for it.
public struct DeviceProfile: Hashable, Sendable {

  /// How a product communicates.
  public enum Radio: String, Hashable, Sendable {

    /// Over the powerline only.
    case powerline

    /// Over RF only.
    case rf

    /// Over both the powerline and RF.
    case dual

  }

  /// Which ALL-Link roles a product or group can take.
  public enum LinkRole: String, Hashable, Sendable {

    /// A controller, which sends commands to its responders.
    case controller

    /// A responder, which acts on its controllers' commands.
    case responder

    /// Both a controller and a responder.
    case both

  }

  /// One of a product's ALL-Link groups.
  public struct Group: Hashable, Sendable {

    /// How a group can be linked.
    public enum Linking: String, Hashable, Sendable {

      /// From the device's own buttons, as well as by software.
      case device

      /// Only by software, such as by writing to the device's ALL-Link database.
      case software

    }

    /// An operating flag state a group is in use under.
    public struct Condition: Hashable, Sendable {

      /// The operating flag, in the command set the profile's identity uses.
      public var flag: SettingName

      /// Whether the flag is set while the group is in use.
      public var isSet: Bool

      /// Creates a condition.
      ///
      /// - Parameters:
      ///   - flag: The operating flag.
      ///   - isSet: Whether the flag is set while the group is in use.
      public init(flag: SettingName, isSet: Bool) {

        self.flag = flag
        self.isSet = isSet

      }

    }

    /// The group number.
    public var number: AllLinkGroupNumber

    /// The group's name, such as `"Wet"` or `"Button A"`.
    public var name: String

    /// The role the product takes in the group.
    public var role: LinkRole

    /// How the group can be linked.
    public var linking: Linking

    /// The name of the group's ``GroupType``, in every command set the profile's identities
    /// use, or `nil` if the catalog doesn't say what the group is.
    /// ``CommandSet/groupType(named:)`` finds it.
    public var type: SettingName?

    /// The operating flag state the group is in use under, such as a keypad's detached load,
    /// or `nil` if it's always in use.
    public var activeWhen: Condition?

    /// How sure the catalog is of the group.
    public var verification: Verification

    /// Creates a group.
    ///
    /// - Parameters:
    ///   - number: The group number.
    ///   - name: The group's name.
    ///   - role: The role the product takes in the group.
    ///   - linking: How the group can be linked. Defaults to ``DeviceProfile/Group/Linking/device``.
    ///   - type: The name of the group's type.
    ///   - activeWhen: The operating flag state the group is in use under.
    ///   - verification: How sure the catalog is of the group. Defaults to ``Verification/documented``.
    public init(
      number: AllLinkGroupNumber,
      name: String,
      role: LinkRole,
      linking: Linking = .device,
      type: SettingName? = nil,
      activeWhen: Condition? = nil,
      verification: Verification = .documented
    ) {

      self.number = number
      self.name = name
      self.role = role
      self.linking = linking
      self.type = type
      self.activeWhen = activeWhen
      self.verification = verification

    }

  }

  /// The model number printed on the product.
  public var model: ProductModel

  /// The product's name, such as `"Dimmer Switch"`.
  public var name: String

  /// Other names the product is known by, such as earlier or marketing names, like
  /// `"SwitchLinc Dimmer"`.
  public var aliases: [String]

  /// What the product is, in a sentence or two, or `nil` if the catalog doesn't say. The
  /// catalog's JSON calls it `description`.
  public var summary: String?

  /// The category, subcategory and firmware versions the product reports.
  public var identities: [DeviceIdentity]

  /// Which Insteon engine the product runs under each identity and firmware version, where a
  /// source states it. A version no entry covers runs an engine the catalog doesn't know.
  public var engines: [DeviceEngine]

  /// Which command set the product uses under each identity and firmware version, where a
  /// source states it. ``DeviceCatalog/commandSet(category:subcategory:firmwareVersion:)``
  /// finds the command set a device uses.
  public var commandSets: [CommandSetEntry]

  /// How the product communicates, or `nil` if no source states it.
  public var radio: Radio?

  /// Whether the product can be a controller, a responder, or both, or `nil` if no source
  /// states it.
  public var role: LinkRole?

  /// Whether the product runs on batteries and sleeps between messages, so it answers only
  /// shortly after it sends something.
  public var isBatteryPowered: Bool

  /// The product's ALL-Link groups.
  public var groups: [Group]

  /// What the product can do.
  public var capabilities: [DeviceCapability]

  /// For a modem, what Data 1 through Data 3 hold in the ALL-Link database records it writes
  /// itself when it links, or `nil` if the catalog doesn't say. The catalog's JSON gives it in
  /// the ``DeviceCapability/modem`` capability's `linkData`.
  public var modemLinkData: ModemLinkData?

  /// How to install the product, link it, wake it, reset it and take it out of service, or
  /// `nil` if the catalog doesn't say.
  public var lifecycle: DeviceLifecycle?

  /// Behavior worth knowing that no capability describes.
  public var notes: [String]

  /// The documents the profile's values come from.
  public var sources: [String]

  /// How sure the catalog is of the profile itself, such as its model and name.
  public var verification: Verification

  /// Creates a profile.
  ///
  /// - Parameters:
  ///   - model: The model number.
  ///   - name: The product's name.
  ///   - aliases: Other names the product is known by.
  ///   - summary: What the product is.
  ///   - identities: The identities the product reports.
  ///   - engines: The engine the product runs under each identity and firmware version.
  ///   - commandSets: The command set the product uses under each identity and firmware
  ///     version.
  ///   - radio: How the product communicates.
  ///   - role: The ALL-Link roles the product can take.
  ///   - isBatteryPowered: Whether the product runs on batteries.
  ///   - groups: The product's ALL-Link groups.
  ///   - capabilities: What the product can do.
  ///   - modemLinkData: For a modem, what the records it writes itself hold. Defaults to `nil`.
  ///   - lifecycle: How to install, link, wake, reset and remove the product.
  ///   - notes: Behavior worth knowing.
  ///   - sources: The documents the values come from.
  ///   - verification: How sure the catalog is of the profile itself. Defaults to ``Verification/documented``.
  public init(
    model: ProductModel,
    name: String,
    aliases: [String] = [],
    summary: String? = nil,
    identities: [DeviceIdentity],
    engines: [DeviceEngine] = [],
    commandSets: [CommandSetEntry] = [],
    radio: Radio? = nil,
    role: LinkRole? = nil,
    isBatteryPowered: Bool = false,
    groups: [Group] = [],
    capabilities: [DeviceCapability] = [],
    modemLinkData: ModemLinkData? = nil,
    lifecycle: DeviceLifecycle? = nil,
    notes: [String] = [],
    sources: [String] = [],
    verification: Verification = .documented
  ) {

    self.model = model
    self.name = name
    self.aliases = aliases
    self.summary = summary
    self.identities = identities
    self.engines = engines
    self.commandSets = commandSets
    self.radio = radio
    self.role = role
    self.isBatteryPowered = isBatteryPowered
    self.groups = groups
    self.capabilities = capabilities
    self.modemLinkData = modemLinkData
    self.lifecycle = lifecycle
    self.notes = notes
    self.sources = sources
    self.verification = verification

  }

  /// What the product means by a command it sent to one of its groups.
  ///
  /// ```swift
  /// if let profile = catalog.profile(category: 0x10, subcategory: 0x08, firmwareVersion: nil),
  ///    profile.event(group: command.group, command1: command.command1) == "wet" {
  ///   print("The leak sensor is wet")
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - group: The group the command was sent to.
  ///   - command1: The command's cmd1.
  /// - Returns: The event, or `nil` if the profile doesn't say what the command means.
  public func event(group: AllLinkGroupNumber, command1: UInt8) -> DeviceEventName? {

    for case let .groupEvents(events) in capabilities {

      if let match = events.first(where: { $0.group == group && $0.command1 == command1 }) {

        return match.event

      }

    }

    return nil

  }

  /// The group the product sends its heartbeat to, or `nil` if it sends none to a group.
  public var heartbeatGroup: AllLinkGroupNumber? {

    for case let .heartbeat(group, _) in capabilities {

      return group

    }

    return nil

  }

  /// Whether every word of a search appears in the profile's model, name, aliases or
  /// identities, ignoring case.
  ///
  /// An identity matches as its category and subcategory written `0x01/0x20`.
  ///
  /// - Parameter query: The words to look for, separated by spaces.
  /// - Returns: `true` if every word appears; `true` for an empty search.
  public func matches(_ query: String) -> Bool {

    let text = ([model.rawValue, name] + aliases + identities.map { "\($0.category)/\($0.subcategory)" })
      .joined(separator: " ")
      .lowercased()

    return query.lowercased().split(whereSeparator: \.isWhitespace).allSatisfy { text.contains($0) }

  }

  /// The Insteon engine a device of this product runs, given the identity and firmware version
  /// it reported.
  ///
  /// ```swift
  /// let integrity: any UserDataIntegrity = profile.engine(category: category, subcategory: subcategory, firmwareVersion: version) == .i2cs
  ///   ? ChecksumIntegrity()
  ///   : UnprotectedIntegrity()
  /// ```
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  /// - Returns: The engine of the entry in ``DeviceProfile/engines`` that covers the device, or
  ///   `nil` if none does.
  public func engine(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> InsteonEngine? {

    engines.first { $0.covers(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion) }?.engine

  }

  /// The interval between the product's heartbeats, or `nil` if it sends none or its profile
  /// doesn't give the interval.
  public var heartbeatInterval: Duration? {

    for case let .heartbeat(_, interval) in capabilities {

      return interval

    }

    return nil

  }

}

extension DeviceProfile: Decodable {

  private enum CodingKeys: String, CodingKey {

    case model
    case name
    case aliases
    case summary = "description"
    case identities
    case engines
    case commandSets
    case radio
    case role
    case batteryPowered
    case groups
    case capabilities
    case lifecycle
    case notes
    case sources
    case verification

  }

  private struct GroupEntry: Decodable {

    let number: ProfileByte

    let name: String

    let role: String

    let linkable: String?

    let type: String?

    let activeWhen: ActiveWhen?

    let verification: Verification?

    /// The group, or `nil` for one with a role this package doesn't read.
    var group: Group? {

      guard let linkRole = LinkRole(rawValue: self.role) else {

        return nil

      }

      var activeWhenCondition: Group.Condition?

      if let activeWhen {

        activeWhenCondition = Group.Condition(flag: SettingName(rawValue: activeWhen.flag), isSet: activeWhen.set)

      }

      return Group(
        number: AllLinkGroupNumber(rawValue: number.value),
        name: name,
        role: linkRole,
        linking: linkable.map { Group.Linking(rawValue: $0) ?? .software } ?? .device,
        type: self.type.map(SettingName.init(rawValue:)),
        activeWhen: activeWhenCondition,
        verification: verification ?? .documented
      )

    }

  }

  private struct ActiveWhen: Decodable {

    let flag: String

    let set: Bool

  }

  /// An engine entry, or `nil` for an engine this package doesn't read.
  private struct EngineEntry: Decodable {

    let engine: DeviceEngine?

    init(from decoder: any Decoder) throws {

      engine = try DeviceEngine(from: decoder)

    }

  }

  /// A capability, or `nil` for one this package doesn't read, and a modem's record data.
  private struct CapabilityEntry: Decodable {

    private enum CodingKeys: String, CodingKey {

      case linkData

    }

    let capability: DeviceCapability?

    let modemLinkData: ModemLinkData?

    init(from decoder: any Decoder) throws {

      let capability = try DeviceCapability(from: decoder)

      self.capability = capability

      if capability == .modem {

        modemLinkData = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(ModemLinkData.self, forKey: .linkData)

      } else {

        modemLinkData = nil

      }

    }

  }

  /// Decodes a profile from its JSON.
  ///
  /// Values from a later version of the catalog that this package doesn't read are passed
  /// over rather than failing the profile: an unknown radio or role reads as `nil`, a group
  /// with an unknown role is skipped, a group with an unknown way of linking reads as
  /// ``DeviceProfile/Group/Linking/software``, and an unknown capability or engine is skipped.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a profile.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)
    let capabilities: [CapabilityEntry] = try container.decode([CapabilityEntry].self, forKey: .capabilities)

    self.init(
      model: try container.decode(ProductModel.self, forKey: .model),
      name: try container.decode(String.self, forKey: .name),
      aliases: try container.decodeIfPresent([String].self, forKey: .aliases) ?? [],
      summary: try container.decodeIfPresent(String.self, forKey: .summary),
      identities: try container.decode([DeviceIdentity].self, forKey: .identities),
      engines: try (container.decodeIfPresent([EngineEntry].self, forKey: .engines) ?? []).compactMap(\.engine),
      commandSets: try container.decodeIfPresent([CommandSetEntry].self, forKey: .commandSets) ?? [],
      radio: try container.decodeIfPresent(String.self, forKey: .radio).flatMap(Radio.init(rawValue:)),
      role: try container.decodeIfPresent(String.self, forKey: .role).flatMap(LinkRole.init(rawValue:)),
      isBatteryPowered: try container.decodeIfPresent(Bool.self, forKey: .batteryPowered) ?? false,
      groups: try (container.decodeIfPresent([GroupEntry].self, forKey: .groups) ?? []).compactMap(\.group),
      capabilities: capabilities.compactMap(\.capability),
      modemLinkData: capabilities.lazy.compactMap(\.modemLinkData).first,
      lifecycle: try container.decodeIfPresent(DeviceLifecycle.self, forKey: .lifecycle),
      notes: try container.decodeIfPresent([String].self, forKey: .notes) ?? [],
      sources: try container.decode([String].self, forKey: .sources),
      verification: try container.decodeIfPresent(Verification.self, forKey: .verification) ?? .documented
    )

  }

}
