import InsteonProtocol

extension CommandSet: Decodable {

  private enum CodingKeys: String, CodingKey {

    case id
    case name
    case summary = "description"
    case operatingFlags
    case readings
    case flagCommands
    case extendedSettings
    case standardCommands
    case extendedCommands
    case directMessages
    case enumerations
    case displayScale
    case notes
    case sources

  }

  private struct Flag: Decodable {

    let name: String

    let description: String

    let query: ProfileByte

    let bit: ProfileByte

    let on: ProfileByte?

    let off: ProfileByte?

    let extendedWhen: String?

  }

  private struct Reading: Decodable {

    let name: String

    let description: String

    let query: ProfileByte

  }

  private struct FlagCommand: Decodable {

    let name: String

    let description: String

    let command2: ProfileByte

    let extendedWhen: String?

  }

  private struct Settings: Decodable {

    let perButton: Bool

    let values: [Value]?

    let writes: [Write]?

  }

  private struct Value: Decodable {

    struct Range: Decodable {

      let from: ProfileByte

      let through: ProfileByte

    }

    let name: String

    let description: String

    let byte: Int

    let kind: String?

    let range: Range?

  }

  private struct Write: Decodable {

    struct Byte: Decodable {

      let position: Int

      let value: String

    }

    let name: String

    let description: String

    let selector: ProfileByte

    let perButton: Bool

    let bytes: [Byte]

  }

  private struct EnumerationEntry: Decodable {

    let value: ProfileByte

    let name: String

  }

  private struct Enumeration: Decodable {

    let name: String

    let values: [EnumerationEntry]

  }

  private struct Bit: Decodable {

    let mask: ProfileByte

    let name: String

  }

  private struct FieldRange: Decodable {

    let from: Double

    let through: Double

  }

  private struct Field: Decodable {

    let name: String

    let description: String

    let byte: Int?

    let bytes: [Int]?

    let mask: ProfileByte?

    let signed: Bool?

    let scale: Double?

    let unit: String?

    let kind: String?

    let enumeration: String?

    let bits: [Bit]?

    let range: FieldRange?

  }

  private struct FixedByte: Decodable {

    let position: Int

    let value: ProfileByte

  }

  private struct StandardCommand: Decodable {

    let name: String

    let description: String

    let command1: ProfileByte

    let command2: ProfileByte?

    let parameter: Field?

    let reply: Field?

    let followUp: Field?

    let extendedWhen: String?

  }

  private struct ExtendedReply: Decodable {

    let command1: ProfileByte?

    let command2: ProfileByte

    let match: [FixedByte]?

    let integrity: String?

    let values: [Field]

  }

  private struct ExtendedCommand: Decodable {

    let name: String

    let description: String

    let command1: ProfileByte

    let command2: ProfileByte

    let perButton: Bool?

    let fixed: [FixedByte]?

    let parameters: [Field]?

    let integrity: String?

    let reply: ExtendedReply?

  }

  private struct DirectMessage: Decodable {

    let name: String

    let description: String

    let command1: ProfileByte

    let value: Field

  }

  private struct DisplayScale: Decodable {

    let celsiusWhen: String

  }

  /// Decodes a command set from the catalog's JSON.
  ///
  /// A value of a kind from a later version of the catalog reads as
  /// ``SettingValue/Kind/number``, and a field's as a ``FieldKind/number(isSigned:scale:unit:)``.
  /// A unit from a later version reads as none, and an extended command whose integrity scheme
  /// is from a later version is left out.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a command set, a byte isn't written as `0x`
  ///   and two hexadecimal digits, a position is outside its message's user data, a field's bytes
  ///   or mask can't be read, a range ends before it starts, a standard command has both a
  ///   fixed cmd2 and a parameter, or a field names an enumeration the command set doesn't
  ///   have.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      id: CommandSetID(rawValue: try container.decode(String.self, forKey: .id)),
      name: try container.decode(String.self, forKey: .name),
      summary: try container.decode(String.self, forKey: .summary),
      operatingFlags: try (container.decodeIfPresent([Flag].self, forKey: .operatingFlags) ?? []).map { flag in

        OperatingFlag(
          name: SettingName(rawValue: flag.name),
          summary: flag.description,
          query: OperatingFlagsRequest(rawValue: flag.query.value),
          bit: flag.bit.value,
          on: flag.on?.value,
          off: flag.off?.value,
          extendedWhen: flag.extendedWhen.map(SettingName.init(rawValue:))
        )

      },
      readings: try (container.decodeIfPresent([Reading].self, forKey: .readings) ?? []).map { reading in

        OperatingReading(name: SettingName(rawValue: reading.name), summary: reading.description, query: OperatingFlagsRequest(rawValue: reading.query.value))

      },
      flagCommands: try (container.decodeIfPresent([FlagCommand].self, forKey: .flagCommands) ?? []).map { command in

        OperatingFlagCommand(
          name: SettingName(rawValue: command.name),
          summary: command.description,
          command2: command.command2.value,
          extendedWhen: command.extendedWhen.map(SettingName.init(rawValue:))
        )

      },
      extendedSettings: try container.decodeIfPresent(Settings.self, forKey: .extendedSettings).map { settings throws in

        try Self.extendedSettings(settings, in: container)

      },
      notes: try container.decodeIfPresent([String].self, forKey: .notes) ?? [],
      sources: try container.decode([String].self, forKey: .sources)
    )

    try decodeMessages(from: container)

  }

  private mutating func decodeMessages(from container: KeyedDecodingContainer<CodingKeys>) throws {

    let enumerations = Dictionary(
      try (container.decodeIfPresent([Enumeration].self, forKey: .enumerations) ?? []).map { enumeration in

        (enumeration.name, FieldEnumeration(
          name: SettingName(rawValue: enumeration.name),
          entries: enumeration.values.map { FieldEnumeration.Entry(value: $0.value.value, name: SettingName(rawValue: $0.name)) }
        ))

      }
    ) { first, _ in first }

    func corrupted(_ key: CodingKeys, _ description: String) -> DecodingError {

      DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: description)

    }

    func field(_ field: Field, in key: CodingKeys, extended: Bool) throws -> MessageField {

      let positions = field.byte.map { [$0] } ?? field.bytes ?? []
      let location: FieldLocation = extended ? .userData(positions) : .command2

      guard
        field.byte == nil || field.bytes == nil,
        extended == !positions.isEmpty,
        MessageField.isValid(location: location, mask: field.mask?.value)
      else {

        throw corrupted(key, "The \(field.name) value isn't in cmd2 or one to four distinct bytes from D1 through D14 as its message needs, or its mask isn't contiguous bits of one byte.")

      }

      var kind = FieldKind.number(isSigned: field.signed ?? false, scale: field.scale ?? 1, unit: field.unit.flatMap(FieldUnit.init(rawValue:)))

      switch field.kind {
      case "buttons":
        kind = .buttons
      case "enumeration":
        guard let enumeration = field.enumeration.flatMap({ enumerations[$0] }) else {

          throw corrupted(key, "The \(field.name) value names an enumeration the command set doesn't have.")

        }

        kind = .enumeration(enumeration)
      case "flags":
        kind = .flags((field.bits ?? []).map { FieldBit(mask: $0.mask.value, name: SettingName(rawValue: $0.name)) })
      case "boolean":
        kind = .boolean
      default:
        break
      }

      var range: ClosedRange<Double>?

      if let bounds = field.range {

        guard bounds.from <= bounds.through else {

          throw corrupted(key, "The \(field.name) value's range ends before it starts.")

        }

        range = bounds.from...bounds.through

      }

      return MessageField(
        name: SettingName(rawValue: field.name),
        summary: field.description,
        location: location,
        mask: field.mask?.value,
        kind: kind,
        range: range
      )

    }

    func fixedBytes(_ bytes: [FixedByte]?, in key: CodingKeys) throws -> [FixedUserDataByte] {

      try (bytes ?? []).map { byte in

        guard (1...UserData.count).contains(byte.position) else {

          throw corrupted(key, "A fixed byte isn't in D1 through D14.")

        }

        return FixedUserDataByte(position: byte.position, value: byte.value.value)

      }

    }

    // A scheme from a later version of the catalog reads as nil, so its command is skipped.
    func integrity(_ name: String?) -> MessageIntegrity? {

      guard let name else {

        return .unprotected

      }

      return MessageIntegrity(rawValue: name)

    }

    standardCommands = try (container.decodeIfPresent([StandardCommand].self, forKey: .standardCommands) ?? []).map { command -> DeviceStandardCommand in

      guard command.parameter == nil || command.command2 == nil else {

        throw corrupted(.standardCommands, "The \(command.name) command has both a fixed cmd2 and a parameter.")

      }

      return DeviceStandardCommand(
        name: SettingName(rawValue: command.name),
        summary: command.description,
        command1: command.command1.value,
        command2: try command.parameter.map { DeviceStandardCommand.Command2.parameter(try field($0, in: .standardCommands, extended: false)) }
          ?? .fixed(command.command2?.value ?? 0x00),
        reply: try command.reply.map { try field($0, in: .standardCommands, extended: false) },
        followUp: try command.followUp.map { try field($0, in: .standardCommands, extended: false) },
        extendedWhen: command.extendedWhen.map(SettingName.init(rawValue:))
      )

    }

    extendedCommands = try (container.decodeIfPresent([ExtendedCommand].self, forKey: .extendedCommands) ?? []).compactMap { command -> DeviceExtendedCommand? in

      guard let commandIntegrity = integrity(command.integrity) else {

        return nil

      }

      var reply: DeviceExtendedReply?

      if let decoded = command.reply {

        guard let replyIntegrity = integrity(decoded.integrity) else {

          return nil

        }

        reply = DeviceExtendedReply(
          command: Command(command1: decoded.command1?.value ?? command.command1.value, command2: decoded.command2.value),
          match: try fixedBytes(decoded.match, in: .extendedCommands),
          integrity: replyIntegrity,
          values: try decoded.values.map { try field($0, in: .extendedCommands, extended: true) }
        )

      }

      return DeviceExtendedCommand(
        name: SettingName(rawValue: command.name),
        summary: command.description,
        command: Command(command1: command.command1.value, command2: command.command2.value),
        isPerButton: command.perButton ?? false,
        fixedBytes: try fixedBytes(command.fixed, in: .extendedCommands),
        parameters: try (command.parameters ?? []).map { try field($0, in: .extendedCommands, extended: true) },
        integrity: commandIntegrity,
        reply: reply
      )

    }

    directMessages = try (container.decodeIfPresent([DirectMessage].self, forKey: .directMessages) ?? []).map { message in

      DeviceDirectMessage(
        name: SettingName(rawValue: message.name),
        summary: message.description,
        command1: message.command1.value,
        value: try field(message.value, in: .directMessages, extended: false)
      )

    }

    celsiusIndicator = try container.decodeIfPresent(DisplayScale.self, forKey: .displayScale).map { SettingName(rawValue: $0.celsiusWhen) }

  }

  private static func extendedSettings(_ settings: Settings, in container: KeyedDecodingContainer<CodingKeys>) throws -> ExtendedSettings {

    let positions = 3...14

    func corrupted(_ description: String) -> DecodingError {

      DecodingError.dataCorruptedError(forKey: .extendedSettings, in: container, debugDescription: description)

    }

    let values = try (settings.values ?? []).map { value in

      guard positions.contains(value.byte) else {

        throw corrupted("The \(value.name) value isn't in D3 through D14.")

      }

      var range: ClosedRange<UInt8>?

      if let bounds = value.range {

        guard bounds.from.value <= bounds.through.value else {

          throw corrupted("The \(value.name) value's range ends before it starts.")

        }

        range = bounds.from.value...bounds.through.value

      }

      return SettingValue(
        name: SettingName(rawValue: value.name),
        summary: value.description,
        position: value.byte,
        kind: value.kind.flatMap(SettingValue.Kind.init(rawValue:)) ?? .number,
        range: range
      )

    }

    let writes = try (settings.writes ?? []).map { write in

      guard write.bytes.allSatisfy({ positions.contains($0.position) }) else {

        throw corrupted("The \(write.name) write fills a byte outside D3 through D14.")

      }

      return SettingWrite(
        name: SettingName(rawValue: write.name),
        summary: write.description,
        selector: write.selector.value,
        isPerButton: write.perButton,
        bytes: write.bytes.map { SettingWrite.Byte(position: $0.position, value: SettingName(rawValue: $0.value)) }
      )

    }

    return ExtendedSettings(isPerButton: settings.perButton, values: values, writes: writes)

  }

}
