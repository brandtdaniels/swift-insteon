import InsteonProtocol

/// What the Insteon device catalog says about a device that reported its category,
/// subcategory and firmware version: its profile, command set, name, engine and groups.
///
/// ```swift
/// let plug = catalog.describe(category: 0x02, subcategory: 0x2A, firmwareVersion: 0x41)
/// plug.displayName            // the catalog's name and model, if it has the identity
/// plug.mainGroupType?.kind    // GroupType.Kind.relay for a device switched on and off
/// ```
///
/// A device the catalog doesn't have is still described, with no profile, so code can treat
/// every device alike and fall back on its category, as ``GroupType/Kind/fallback(for:)``
/// does.
public struct DeviceDescription: Hashable, Sendable {

  /// The category the device reported.
  public var category: DeviceCategory

  /// The subcategory the device reported.
  public var subcategory: DeviceSubcategory

  /// The firmware version the device reported, or `nil` if it didn't report one.
  public var firmwareVersion: FirmwareVersion?

  /// The catalog's profile for the identity, or `nil` if the catalog doesn't have it or wasn't
  /// loaded.
  public var profile: DeviceProfile?

  /// The command set the profile names for the identity and firmware version, if any.
  public var commandSet: CommandSet?

  /// Looks a device's identity up in a catalog.
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  ///   - catalog: The catalog, or `nil` if it couldn't be loaded, which describes the device
  ///     by its identity alone.
  public init(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?, catalog: DeviceCatalog?) {

    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion
    profile = catalog?.profile(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)
    commandSet = catalog?.commandSet(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)

  }

  /// The product's name, model and first alias, as ``DeviceProfile/displayName`` writes them,
  /// such as "Dimmer Switch 2477D (SwitchLinc Dimmer)", or `nil` without a profile.
  public var displayName: String? {

    profile?.displayName

  }

  /// The Insteon engine the catalog says the device runs, or `nil` without a profile or if the
  /// profile doesn't say for the identity and firmware version.
  ///
  /// A device's reply to Get Insteon Engine Version is the surer source.
  public var engine: InsteonEngine? {

    profile?.engine(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)

  }

  /// The type of one of the device's groups, or `nil` if the catalog doesn't say.
  ///
  /// - Parameter number: The device's group number, such as 1 for its load.
  /// - Returns: The type the profile's group names, from the command set.
  public func groupType(forGroup number: AllLinkGroupNumber) -> GroupType? {

    guard let group = profile?.groups.first(where: { $0.number == number }) else {

      return nil

    }

    return groupType(of: group)

  }

  /// The device's main group: group 1 if the catalog gives its type, or else the first group
  /// whose type it gives. `nil` without a profile, a command set, or a group with a type.
  public var mainGroup: DeviceProfile.Group? {

    guard let profile else {

      return nil

    }

    let typed: [DeviceProfile.Group] = profile.groups.filter { groupType(of: $0) != nil }

    let first: DeviceProfile.Group? = typed.first(where: { $0.number == 1 })

    return first ?? typed.first

  }

  /// The type of the device's main group, ``DeviceDescription/mainGroup``. A relay's kind is
  /// ``GroupType/Kind/relay``, which turns only on and off.
  public var mainGroupType: GroupType? {

    guard let group = mainGroup else {

      return nil

    }

    return groupType(of: group)

  }

  /// The group type that explains a responder record in the device's own ALL-Link database.
  ///
  /// A responder record's group is its controller's, not the device's. A device with several
  /// groups keeps its own group in one of the data bytes, which the main group's type marks
  /// with ``LinkDataByte/isPerGroup``; otherwise the main group's type explains the record.
  ///
  /// - Parameter data: The record's Data 1 through Data 3.
  /// - Returns: The group type, or `nil` if the catalog doesn't say.
  public func responderGroupType(forRecordData data: [UInt8]) -> GroupType? {

    guard let main = mainGroupType else {

      return nil

    }

    guard
      let perGroup = main.linkData.responder.first(where: \.isPerGroup),
      perGroup.position <= data.count,
      let type = groupType(forGroup: AllLinkGroupNumber(rawValue: data[perGroup.position - 1]))
    else {

      return main

    }

    return type

  }

  /// The groups the catalog says the device controls, in the profile's order: those whose role
  /// is ``DeviceProfile/LinkRole/controller`` or ``DeviceProfile/LinkRole/both``. Empty without
  /// a profile.
  ///
  /// A profile without groups can still say the product controls, in
  /// ``DeviceProfile/role``.
  public var controllerGroups: [DeviceProfile.Group] {

    guard let profile else {

      return []

    }

    return profile.groups.filter { $0.role.includesController }

  }

  /// What the data bytes of a record in the device's own ALL-Link database hold, from its
  /// group type.
  ///
  /// A controller record's group is the device's own, so its type explains the record, or the
  /// main group's if the catalog doesn't give it. A responder record's group is its
  /// controller's, so ``DeviceDescription/responderGroupType(forRecordData:)`` finds the type.
  ///
  /// - Parameters:
  ///   - record: The record, from the device's ALL-Link database.
  ///   - isController: Whether it's a controller record, as its flags say with
  ///     `AllLinkRecordFlags.controller`.
  /// - Returns: The explanation, or `nil` if the catalog doesn't describe the record's bytes.
  public func explain(_ record: AllLinkRecord, isController: Bool) -> RecordDataExplanation? {

    let data: [UInt8] = [record.data1, record.data2, record.data3]
    let found: GroupType?

    if isController {

      found = groupType(forGroup: record.group) ?? mainGroupType

    } else {

      found = responderGroupType(forRecordData: data)

    }

    guard let type = found else {

      return nil

    }

    let described: [LinkDataByte] = isController ? type.linkData.controller : type.linkData.responder
    let tables: [ValueTable] = commandSet?.valueTables ?? []
    let ordered: [LinkDataByte] = described.sorted { $0.position < $1.position }
    var bytes: [RecordDataExplanation.DataByte] = []

    for byte in ordered where (1...data.count).contains(byte.position) {

      let value: UInt8 = data[byte.position - 1]
      let table: ValueTable? = byte.table.flatMap { name in tables.first(where: { $0.name == name }) }

      bytes.append(RecordDataExplanation.DataByte(
        position: byte.position,
        name: byte.name,
        label: byte.label,
        value: value,
        tableEntry: table?.entry(for: value),
        isPerGroup: byte.isPerGroup,
        verification: byte.verification,
        documentedValue: byte.value
      ))

    }

    guard !bytes.isEmpty else {

      return nil

    }

    return RecordDataExplanation(groupType: type, bytes: bytes)

  }

  /// The type a profile's group names, from the command set.
  private func groupType(of group: DeviceProfile.Group) -> GroupType? {

    guard let commandSet, let name = group.type else {

      return nil

    }

    return commandSet.groupType(named: name)

  }

}

/// What the data bytes of an ALL-Link database record hold, as the Insteon device catalog
/// gives them for the group type that explains the record.
///
/// ``DeviceDescription/explain(_:isController:)`` makes one. An app shows each byte by its
/// label and value, with the value's name from its table when there is one:
///
/// ```swift
/// if let explanation = device.explain(record, isController: record.flags.contains(.controller)) {
///   for byte in explanation.bytes {
///     print(byte.label ?? byte.name.rawValue, byte.tableEntry?.label ?? "\(byte.value)")
///   }
/// }
/// ```
public struct RecordDataExplanation: Hashable, Sendable {

  /// One data byte of the record, with what it holds.
  public struct DataByte: Hashable, Sendable {

    /// Which data byte of the record it is, from 1 through 3.
    public var position: Int

    /// The byte's name, such as `"onLevel"`.
    public var name: SettingName

    /// What a settings page calls the byte, such as `"On-level"`, if the catalog says.
    public var label: String?

    /// The byte's value in the record.
    public var value: UInt8

    /// The value's entry in the byte's value table, such as the ramp rate's, or `nil` if the
    /// byte has no table or the table doesn't name the value.
    public var tableEntry: ValueTable.Entry?

    /// Whether the byte is the responder's own group, as ``LinkDataByte/isPerGroup`` says, so
    /// the value is a group number.
    public var isPerGroup: Bool

    /// How sure the catalog is of the byte.
    public var verification: Verification

    /// The value the catalog gives for the byte when it's fixed, as ``LinkDataByte/value``
    /// says, such as an on-level of `0xFE`, or `nil` if the byte can take any value. A record
    /// whose ``RecordDataExplanation/DataByte/value`` differs isn't as Insteon's documents
    /// write it.
    public var documentedValue: UInt8?

    /// Creates an explained data byte.
    ///
    /// - Parameters:
    ///   - position: Which data byte of the record it is, from 1 through 3.
    ///   - name: The byte's name.
    ///   - label: What a settings page calls the byte.
    ///   - value: The byte's value in the record.
    ///   - tableEntry: The value's entry in the byte's value table.
    ///   - isPerGroup: Whether the byte is the responder's own group. Defaults to `false`.
    ///   - verification: How sure the catalog is of the byte. Defaults to ``Verification/documented``.
    ///   - documentedValue: The value the catalog gives for the byte when it's fixed. Defaults
    ///     to `nil`.
    public init(
      position: Int,
      name: SettingName,
      label: String? = nil,
      value: UInt8,
      tableEntry: ValueTable.Entry? = nil,
      isPerGroup: Bool = false,
      verification: Verification = .documented,
      documentedValue: UInt8? = nil
    ) {

      self.position = position
      self.name = name
      self.label = label
      self.value = value
      self.tableEntry = tableEntry
      self.isPerGroup = isPerGroup
      self.verification = verification
      self.documentedValue = documentedValue

    }

  }

  /// The group type that explains the record.
  public var groupType: GroupType

  /// The bytes the group type describes, from Data 1 through Data 3.
  public var bytes: [DataByte]

  /// Creates an explanation.
  ///
  /// - Parameters:
  ///   - groupType: The group type that explains the record.
  ///   - bytes: The bytes the group type describes.
  public init(groupType: GroupType, bytes: [DataByte]) {

    self.groupType = groupType
    self.bytes = bytes

  }

}

extension DeviceCatalog {

  /// What the catalog says about a device that reported a category, subcategory and firmware
  /// version.
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, if any.
  /// - Returns: The description, with no profile if the catalog doesn't have the identity.
  public func describe(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> DeviceDescription {

    DeviceDescription(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion, catalog: self)

  }

}

extension DeviceProfile {

  /// The product's name and model, then its first alias in parentheses, as the docs name
  /// products, such as "Dimmer Switch 2477D (SwitchLinc Dimmer)".
  public var displayName: String {

    let name = "\(self.name) \(model)"

    guard let alias = aliases.first else {

      return name

    }

    return "\(name) (\(alias))"

  }

}

extension DeviceProfile.LinkRole {

  /// Whether the role includes a controller's: ``DeviceProfile/LinkRole/controller`` or
  /// ``DeviceProfile/LinkRole/both``.
  public var includesController: Bool {

    self == .controller || self == .both

  }

}

extension GroupType.Kind {

  /// The kind to assume for a device's main group when the catalog doesn't give one, from the
  /// device's category.
  ///
  /// - Parameter category: The category the device reported.
  /// - Returns: ``GroupType/Kind/dimmer`` for dimmable lighting control, `0x01`,
  ///   ``GroupType/Kind/relay`` for switched lighting control, `0x02`, and otherwise `nil`.
  public static func fallback(for category: DeviceCategory) -> GroupType.Kind? {

    switch category {
    case .dimmableLightingControl:
      return .dimmer
    case .switchedLightingControl:
      return .relay
    default:
      return nil
    }

  }

}
