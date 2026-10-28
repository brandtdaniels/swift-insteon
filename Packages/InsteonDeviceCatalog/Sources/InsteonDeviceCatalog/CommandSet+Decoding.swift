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

  /// Decodes a command set from the catalog's JSON.
  ///
  /// A value of a kind from a later version of the catalog reads as
  /// ``SettingValue/Kind/number``.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a command set, a byte isn't written as `0x`
  ///   and two hexadecimal digits, a position is outside D3 through D14, or a range ends
  ///   before it starts.
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
          off: flag.off?.value
        )

      },
      readings: try (container.decodeIfPresent([Reading].self, forKey: .readings) ?? []).map { reading in

        OperatingReading(name: SettingName(rawValue: reading.name), summary: reading.description, query: OperatingFlagsRequest(rawValue: reading.query.value))

      },
      flagCommands: try (container.decodeIfPresent([FlagCommand].self, forKey: .flagCommands) ?? []).map { command in

        OperatingFlagCommand(name: SettingName(rawValue: command.name), summary: command.description, command2: command.command2.value)

      },
      extendedSettings: try container.decodeIfPresent(Settings.self, forKey: .extendedSettings).map { settings throws in

        try Self.extendedSettings(settings, in: container)

      },
      notes: try container.decodeIfPresent([String].self, forKey: .notes) ?? [],
      sources: try container.decode([String].self, forKey: .sources)
    )

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
