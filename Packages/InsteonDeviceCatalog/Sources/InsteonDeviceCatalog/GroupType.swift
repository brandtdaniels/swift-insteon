/// What one kind of a device's ALL-Link groups is, how to read its state, what it can be told
/// to do, and what Data 1 through Data 3 of an ALL-Link database record hold for it.
///
/// A command set describes its group types once, and a profile's groups name theirs in
/// ``DeviceProfile/Group/type``:
///
/// ```swift
/// guard
///   let commands = catalog.commandSet(category: category, subcategory: subcategory, firmwareVersion: version),
///   let name = profile.groups.first(where: { $0.number == 1 })?.type,
///   let light = commands.groupType(named: name)
/// else {
///   return
/// }
///
/// // The bytes to write in a responder's record for the group.
/// for byte in light.linkData.responder {
///   print(byte.position, byte.name, byte.value ?? byte.range?.upperBound ?? 0)
/// }
/// ```
public struct GroupType: Hashable, Sendable {

  /// What a group is.
  public struct Kind: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    /// The kind as the catalog writes it, such as `"dimmer"`.
    public let rawValue: String

    /// Creates a kind from the catalog's name for it.
    ///
    /// - Parameter rawValue: The kind as the catalog writes it.
    public init(rawValue: String) {

      self.rawValue = rawValue

    }

    /// A load that dims.
    public static let dimmer = Kind(rawValue: "dimmer")

    /// A relay or outlet, switched on and off.
    public static let relay = Kind(rawValue: "relay")

    /// A fan with speeds.
    public static let fan = Kind(rawValue: "fan")

    /// A sensor or input that only reports.
    public static let sensor = Kind(rawValue: "sensor")

    /// A button that controls other devices.
    public static let button = Kind(rawValue: "button")

    /// The kind as the catalog writes it.
    public var description: String { rawValue }

  }

  /// How to read a group's state.
  public struct State: Hashable, Sendable {

    /// A name for a range of the state's value, such as a fan speed.
    public struct Range: Hashable, Sendable {

      /// The values the name covers.
      public var values: ClosedRange<UInt8>

      /// The name, such as `"Low"`.
      public var label: String

      /// Creates a named range.
      ///
      /// - Parameters:
      ///   - values: The values the name covers.
      ///   - label: The name.
      public init(values: ClosedRange<UInt8>, label: String) {

        self.values = values
        self.label = label

      }

    }

    /// The standard command, in the command set's ``CommandSet/standardCommands``, whose
    /// acknowledgment carries the state.
    public var command: SettingName

    /// Whether the reply holds one bit per group, group 1 in bit 0, rather than the state
    /// itself.
    public var isBitPerGroup: Bool

    /// Names for ranges of the reply's value, such as a fan's speeds.
    public var ranges: [Range]

    /// Creates a way to read a group's state.
    ///
    /// - Parameters:
    ///   - command: The standard command whose acknowledgment carries the state.
    ///   - isBitPerGroup: Whether the reply holds one bit per group. Defaults to `false`.
    ///   - ranges: Names for ranges of the reply's value.
    public init(command: SettingName, isBitPerGroup: Bool = false, ranges: [Range] = []) {

      self.command = command
      self.isBitPerGroup = isBitPerGroup
      self.ranges = ranges

    }

  }

  /// Something an app can tell a group to do, for controls, scenes and schedules.
  public struct Action: Hashable, Sendable {

    /// The action's name, such as `"on"`.
    public var name: SettingName

    /// What a control calls the action, such as `"On"`.
    public var label: String

    /// The standard or extended command, in the command set, to send.
    public var command: SettingName

    /// The value to give the command's parameter, or `nil` for the caller to give it, such as
    /// a dimmer's level.
    public var value: UInt8?

    /// Whether the action makes sense in a schedule.
    public var isSchedulable: Bool

    /// Creates an action.
    ///
    /// - Parameters:
    ///   - name: The action's name.
    ///   - label: What a control calls the action.
    ///   - command: The command to send.
    ///   - value: The value to give the command's parameter.
    ///   - isSchedulable: Whether the action makes sense in a schedule. Defaults to `true`.
    public init(name: SettingName, label: String, command: SettingName, value: UInt8? = nil, isSchedulable: Bool = true) {

      self.name = name
      self.label = label
      self.command = command
      self.value = value
      self.isSchedulable = isSchedulable

    }

  }

  /// What Data 1 through Data 3 of an ALL-Link database record hold for a group.
  public struct LinkData: Hashable, Sendable {

    /// In a responder's record, the state the group goes to when its controller's group
    /// command arrives.
    public var responder: [LinkDataByte]

    /// In a controller's record, what it keeps about the responder.
    public var controller: [LinkDataByte]

    /// Creates a group's record data.
    ///
    /// - Parameters:
    ///   - responder: The bytes of a responder's record.
    ///   - controller: The bytes of a controller's record.
    public init(responder: [LinkDataByte] = [], controller: [LinkDataByte] = []) {

      self.responder = responder
      self.controller = controller

    }

  }

  /// The group type's name, which profiles' groups name.
  public var name: SettingName

  /// What a settings page or control calls a group of this type, such as `"Light"`.
  public var label: String

  /// What the group is.
  public var kind: Kind

  /// How to read the group's state, or `nil` if the command set doesn't say.
  public var state: State?

  /// What an app can tell the group to do. A group whose type has actions is a responder.
  public var actions: [Action]

  /// What an ALL-Link database record's data bytes hold for the group. Empty if the command
  /// set doesn't say.
  public var linkData: LinkData

  /// How sure the catalog is of the group type.
  public var verification: Verification

  /// Creates a group type.
  ///
  /// - Parameters:
  ///   - name: The group type's name.
  ///   - label: What a settings page or control calls a group of this type.
  ///   - kind: What the group is.
  ///   - state: How to read the group's state.
  ///   - actions: What an app can tell the group to do.
  ///   - linkData: What an ALL-Link database record's data bytes hold for the group.
  ///   - verification: How sure the catalog is of the group type. Defaults to ``Verification/documented``.
  public init(
    name: SettingName,
    label: String,
    kind: Kind,
    state: State? = nil,
    actions: [Action] = [],
    linkData: LinkData = LinkData(),
    verification: Verification = .documented
  ) {

    self.name = name
    self.label = label
    self.kind = kind
    self.state = state
    self.actions = actions
    self.linkData = linkData
    self.verification = verification

  }

  /// The action with a name.
  ///
  /// - Parameter name: The action's name, such as `"on"`.
  /// - Returns: The action, or `nil` if the group type has none by that name.
  public func action(named name: SettingName) -> Action? {

    actions.first { $0.name == name }

  }

}

/// What one data byte of an ALL-Link database record holds for a group: Data 1, 2 or 3.
public struct LinkDataByte: Hashable, Sendable {

  /// Which data byte of the record it is, from 1 through 3.
  public var position: Int

  /// The byte's name, such as `"onLevel"`.
  public var name: SettingName

  /// What a settings page calls the byte, such as `"On-level"`.
  public var label: String?

  /// What the byte holds. The catalog's JSON calls it `description`.
  public var summary: String

  /// The value to write, when it's fixed, such as a fan's button number.
  public var value: UInt8?

  /// The values the byte can take, if the command set gives them.
  public var range: ClosedRange<UInt8>?

  /// The byte's unit once scaled, for a byte shown as a number.
  public var unit: FieldUnit?

  /// What one count is worth in ``LinkDataByte/unit``, such as 100/255 for a level shown as a
  /// percentage.
  public var scale: Double

  /// The value table, in the command set's ``CommandSet/valueTables``, that names each value,
  /// such as the ramp rate's.
  public var table: SettingName?

  /// Whether the byte is the responder's own group: the button or part of the device the
  /// record is for, as the profile's group of this type numbers it. It isn't the record's
  /// group, which is the controller's.
  public var isPerGroup: Bool

  /// How sure the catalog is of the byte.
  public var verification: Verification

  /// Creates a data byte.
  ///
  /// - Parameters:
  ///   - position: Which data byte of the record it is, from 1 through 3.
  ///   - name: The byte's name.
  ///   - label: What a settings page calls the byte.
  ///   - summary: What the byte holds.
  ///   - value: The value to write, when it's fixed.
  ///   - range: The values the byte can take.
  ///   - unit: The byte's unit once scaled.
  ///   - scale: What one count is worth in the unit. Defaults to 1.
  ///   - table: The value table that names each value.
  ///   - isPerGroup: Whether the byte is the responder's own group. Defaults to `false`.
  ///   - verification: How sure the catalog is of the byte. Defaults to ``Verification/documented``.
  public init(
    position: Int,
    name: SettingName,
    label: String? = nil,
    summary: String,
    value: UInt8? = nil,
    range: ClosedRange<UInt8>? = nil,
    unit: FieldUnit? = nil,
    scale: Double = 1,
    table: SettingName? = nil,
    isPerGroup: Bool = false,
    verification: Verification = .documented
  ) {

    precondition((1...3).contains(position), "An ALL-Link database record's data bytes are Data 1 through Data 3.")

    self.position = position
    self.name = name
    self.label = label
    self.summary = summary
    self.value = value
    self.range = range
    self.unit = unit
    self.scale = scale
    self.table = table
    self.isPerGroup = isPerGroup
    self.verification = verification

  }

}

/// Names for the values of a setting whose raw values mean something else, such as ramp rates
/// and the durations they stand for.
public struct ValueTable: Hashable, Sendable {

  /// One named value.
  public struct Entry: Hashable, Sendable {

    /// The raw value.
    public var value: UInt8

    /// What a settings page shows for it, such as `"2 s"`.
    public var label: String

    /// The duration the value stands for, if it stands for one.
    public var duration: Duration?

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - value: The raw value.
    ///   - label: What a settings page shows for it.
    ///   - duration: The duration the value stands for.
    public init(value: UInt8, label: String, duration: Duration? = nil) {

      self.value = value
      self.label = label
      self.duration = duration

    }

  }

  /// The table's name, which values and data bytes name.
  public var name: SettingName

  /// What the table is, if the command set says. The catalog's JSON calls it `description`.
  public var summary: String?

  /// The named values.
  public var entries: [Entry]

  /// How sure the catalog is of the table.
  public var verification: Verification

  /// Creates a value table.
  ///
  /// - Parameters:
  ///   - name: The table's name.
  ///   - summary: What the table is.
  ///   - entries: The named values.
  ///   - verification: How sure the catalog is of the table. Defaults to ``Verification/documented``.
  public init(name: SettingName, summary: String? = nil, entries: [Entry], verification: Verification = .documented) {

    self.name = name
    self.summary = summary
    self.entries = entries
    self.verification = verification

  }

  /// The entry for a raw value.
  ///
  /// - Parameter value: The raw value.
  /// - Returns: The entry, or `nil` if the table doesn't name the value.
  public func entry(for value: UInt8) -> Entry? {

    entries.first { $0.value == value }

  }

}

// MARK: - Decodable

/// A range of bytes as the catalog writes it, `{ "from": "0x00", "through": "0xFF" }`.
private struct ByteRange: Decodable {

  let from: ProfileByte

  let through: ProfileByte

  /// The range, or `nil` if it ends before it starts.
  var values: ClosedRange<UInt8>? {

    from.value <= through.value ? from.value...through.value : nil

  }

}

extension GroupType: Decodable {

  private enum CodingKeys: String, CodingKey {

    case name
    case label
    case kind
    case state
    case actions
    case linkData
    case verification

  }

  private struct StateEntry: Decodable {

    struct RangeEntry: Decodable {

      let from: ProfileByte

      let through: ProfileByte

      let label: String

    }

    let command: String

    let bitPerGroup: Bool?

    let ranges: [RangeEntry]?

  }

  private struct ActionEntry: Decodable {

    let name: String

    let label: String

    let command: String

    let value: ProfileByte?

    let schedulable: Bool?

  }

  private struct LinkDataEntry: Decodable {

    let responder: [LinkDataByte]?

    let controller: [LinkDataByte]?

  }

  /// Decodes a group type from a command set's `groupTypes`.
  ///
  /// A kind from a later version of the catalog keeps its name.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a group type, a byte isn't written as `0x`
  ///   and two hexadecimal digits, a range ends before it starts, or a data byte isn't Data 1
  ///   through Data 3.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    let state = try container.decodeIfPresent(StateEntry.self, forKey: .state).map { entry in

      State(
        command: SettingName(rawValue: entry.command),
        isBitPerGroup: entry.bitPerGroup ?? false,
        ranges: try (entry.ranges ?? []).map { range in

          guard range.from.value <= range.through.value else {

            throw DecodingError.dataCorruptedError(forKey: .state, in: container, debugDescription: "The \(range.label) range ends before it starts.")

          }

          return State.Range(values: range.from.value...range.through.value, label: range.label)

        }
      )

    }

    let linkData = try container.decodeIfPresent(LinkDataEntry.self, forKey: .linkData)

    self.init(
      name: SettingName(rawValue: try container.decode(String.self, forKey: .name)),
      label: try container.decode(String.self, forKey: .label),
      kind: Kind(rawValue: try container.decode(String.self, forKey: .kind)),
      state: state,
      actions: try (container.decodeIfPresent([ActionEntry].self, forKey: .actions) ?? []).map { action in

        Action(
          name: SettingName(rawValue: action.name),
          label: action.label,
          command: SettingName(rawValue: action.command),
          value: action.value?.value,
          isSchedulable: action.schedulable ?? true
        )

      },
      linkData: LinkData(responder: linkData?.responder ?? [], controller: linkData?.controller ?? []),
      verification: try container.decodeIfPresent(Verification.self, forKey: .verification) ?? .documented
    )

  }

}

extension LinkDataByte: Decodable {

  private enum CodingKeys: String, CodingKey {

    case byte
    case name
    case label
    case summary = "description"
    case value
    case range
    case unit
    case scale
    case table
    case perGroup
    case verification

  }

  /// Decodes a data byte from a group type's `linkData`.
  ///
  /// A unit from a later version of the catalog reads as none.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a data byte, it isn't Data 1 through Data 3,
  ///   a byte isn't written as `0x` and two hexadecimal digits, its range ends before it
  ///   starts, or its scale isn't above 0.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)
    let position = try container.decode(Int.self, forKey: .byte)

    guard (1...3).contains(position) else {

      throw DecodingError.dataCorruptedError(forKey: .byte, in: container, debugDescription: "An ALL-Link database record's data bytes are Data 1 through Data 3.")

    }

    var range: ClosedRange<UInt8>?

    if let bounds = try container.decodeIfPresent(ByteRange.self, forKey: .range) {

      guard let values = bounds.values else {

        throw DecodingError.dataCorruptedError(forKey: .range, in: container, debugDescription: "The range ends before it starts.")

      }

      range = values

    }

    let scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1

    guard scale > 0 else {

      throw DecodingError.dataCorruptedError(forKey: .scale, in: container, debugDescription: "A scale is above 0.")

    }

    self.init(
      position: position,
      name: SettingName(rawValue: try container.decode(String.self, forKey: .name)),
      label: try container.decodeIfPresent(String.self, forKey: .label),
      summary: try container.decode(String.self, forKey: .summary),
      value: try container.decodeIfPresent(ProfileByte.self, forKey: .value)?.value,
      range: range,
      unit: try container.decodeIfPresent(String.self, forKey: .unit).flatMap(FieldUnit.init(rawValue:)),
      scale: scale,
      table: try container.decodeIfPresent(String.self, forKey: .table).map(SettingName.init(rawValue:)),
      isPerGroup: try container.decodeIfPresent(Bool.self, forKey: .perGroup) ?? false,
      verification: try container.decodeIfPresent(Verification.self, forKey: .verification) ?? .documented
    )

  }

}

extension ValueTable: Decodable {

  private enum CodingKeys: String, CodingKey {

    case name
    case summary = "description"
    case values
    case verification

  }

  private struct EntryValue: Decodable {

    private enum CodingKeys: String, CodingKey {

      case value
      case label
      case seconds

    }

    let entry: ValueTable.Entry

    init(from decoder: any Decoder) throws {

      let container = try decoder.container(keyedBy: CodingKeys.self)

      entry = ValueTable.Entry(
        value: try container.decode(ProfileByte.self, forKey: .value).value,
        label: try container.decode(String.self, forKey: .label),
        duration: try container.decodeSecondsIfPresent(forKey: .seconds)
      )

    }

  }

  /// Decodes a value table from a command set's `valueTables`.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a value table, a value isn't written as `0x`
  ///   and two hexadecimal digits, or a number of seconds is negative or longer than a year.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      name: SettingName(rawValue: try container.decode(String.self, forKey: .name)),
      summary: try container.decodeIfPresent(String.self, forKey: .summary),
      entries: try container.decode([EntryValue].self, forKey: .values).map(\.entry),
      verification: try container.decodeIfPresent(Verification.self, forKey: .verification) ?? .documented
    )

  }

}
