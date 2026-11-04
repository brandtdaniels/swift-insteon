import InsteonDeviceCatalog
import InsteonModem
import InsteonProtocol

// Reading the device's other settings before and after a write, to say what else it changed.
extension Device {

  /// The device's writable settings other than the one a write changes, read before the write
  /// and again after it with the reads ``readSettings(includingAdvanced:beforeReading:)``
  /// makes, reusing what the write's own reads already reported.
  struct OtherSettingsCheck {

    /// The device.
    let device: Device

    /// The settings compared: every one the catalog describes that software can write, as
    /// ``DeviceSetting/isWritable`` says, but the setting written. A setting nothing writes,
    /// such as a reading or a value the device measures, changes on its own rather than as a
    /// write's side effect, so it's left out.
    let items: [SettingItem]

    /// The buttons whose values are compared: button 1, which holds the values that aren't
    /// per button, and the button written when some of the values compared are per button.
    /// Empty when no value is compared.
    let buttons: [UInt8]

    /// The device's command set.
    let commands: CommandSet

    /// The device's description.
    let description: DeviceDescription

    /// A check of the writable settings other than `written`, for a write to `button`.
    init(device: Device, besides written: SettingItem, button: UInt8, description: DeviceDescription, commands: CommandSet) {

      let items: [SettingItem] = commands.settingItems.filter { (item: SettingItem) -> Bool in

        item.name != written.name && SettingPresentation.setting(for: item, in: commands).isWritable

      }
      let values: [SettingItem] = items.filter(Device.isValue)
      let isAnyPerButton: Bool = values.contains { (item: SettingItem) -> Bool in commands.extendedSettings?.isValuePerButton(item.name) ?? false }

      self.device = device
      self.items = items
      self.buttons = values.isEmpty ? [] : (isAnyPerButton && button != 0x01 ? [0x01, button] : [0x01])
      self.commands = commands
      self.description = description

    }

    /// Whether there's another setting to compare.
    var isEmpty: Bool {

      items.isEmpty

    }

    /// Reads the other settings, asking only for what `flags` and `values` don't already hold.
    ///
    /// - Parameters:
    ///   - flags: Get Operating Flags replies already read, by request.
    ///   - values: Extended Get replies already read, by button.
    /// - Returns: The reading.
    func read(knowing flags: [OperatingFlagsRequest: UInt8], values: [UInt8: [SettingName: UInt8]]) async throws -> DeviceSettingsReading {

      var reportedFlags: [OperatingFlagsRequest: UInt8] = flags
      var reportedValues: [UInt8: [SettingName: UInt8]] = values

      for query in Device.queries(of: items) where reportedFlags[query] == nil {

        if let acknowledgment = try await device.answer(StandardMessage(to: device.address, command: StandardDirectCommand.getOperatingFlags(query))) {

          reportedFlags[query] = acknowledgment.command.command2

        }

      }

      if let settings = commands.extendedSettings {

        for button in buttons where reportedValues[button] == nil {

          if let reported = try await device.readValues(settings: settings, button: button) {

            reportedValues[button] = reported

          }

        }

      }

      return DeviceSettingsReading(
        productName: description.displayName,
        commandSet: commands,
        items: items,
        operatingFlags: reportedFlags.filter { (query: OperatingFlagsRequest, _: UInt8) -> Bool in Device.queries(of: items).contains(query) },
        values: reportedValues.filter { (button: UInt8, _: [SettingName: UInt8]) -> Bool in buttons.contains(button) },
        buttons: buttons
      )

    }

    /// Reads the other settings before the write, once the write's own read was answered.
    ///
    /// - Parameters:
    ///   - isOwnReported: Whether the device answered the write's own read. When it didn't,
    ///     nothing more is asked, so a device that doesn't answer isn't kept waiting on.
    ///   - flags: Get Operating Flags replies the write's own read already holds.
    ///   - values: Extended Get replies the write's own read already holds.
    /// - Returns: The reading, or how the comparison ended before it began.
    func readBefore(
      isOwnReported: Bool,
      knowing flags: [OperatingFlagsRequest: UInt8] = [:],
      values: [UInt8: [SettingName: UInt8]] = [:]
    ) async throws -> Before {

      guard !isEmpty else {

        return .skipped(.nothingToCompare)

      }

      guard isOwnReported else {

        return .skipped(.notReportedBefore)

      }

      let reading: DeviceSettingsReading = try await read(knowing: flags, values: values)

      guard reading.entries.contains(where: { (entry: DeviceSettingsReading.Entry) -> Bool in entry.text != nil }) else {

        return .skipped(.notReportedBefore)

      }

      return .read(reading)

    }

    /// Reads the other settings again after a confirmed write and compares them with what was
    /// read before.
    ///
    /// The write already succeeded, so nothing here fails it: a read that throws, or is
    /// canceled, ends the comparison with ``DeviceSettingChange/OtherSettings/rereadFailure``
    /// saying why, and a canceled task stays canceled for the caller's next wait.
    ///
    /// - Parameters:
    ///   - before: What was read before the write.
    ///   - flags: Get Operating Flags replies the write's read-back already holds.
    ///   - values: Extended Get replies the write's read-back already holds.
    /// - Returns: What the other settings did across the write.
    func compare(
      with before: Before,
      knowing flags: [OperatingFlagsRequest: UInt8] = [:],
      values: [UInt8: [SettingName: UInt8]] = [:]
    ) async -> DeviceSettingChange.OtherSettings {

      let earlier: DeviceSettingsReading

      switch before {
      case let .read(reading):
        earlier = reading
      case let .skipped(outcome):
        return DeviceSettingChange.OtherSettings(outcome: outcome)
      }

      let later: DeviceSettingsReading

      do {

        later = try await read(knowing: flags, values: values)

      } catch is CancellationError {

        return .notReread(.canceled)

      } catch ModemError.connectionClosed {

        return .notReread(.connectionClosed)

      } catch {

        return .notReread(.failed)

      }

      return earlier.otherSettings(after: later)

    }

  }

  /// What was read of the other settings before a write.
  enum Before {

    /// The reading.
    case read(DeviceSettingsReading)

    /// Nothing was read, for the reason the outcome gives.
    case skipped(DeviceSettingChange.OtherSettings.Outcome)

  }

}

extension DeviceSettingsReading {

  /// What the settings did between this reading and a later one of the same items and
  /// buttons: each entry whose value differs, in order; each one this reading reported that
  /// the later one didn't, as unread; and ``DeviceSettingChange/OtherSettings/ReadFailure/notAnswered``
  /// when the later reading has none of the values this one has. An entry this reading didn't
  /// report is left out.
  func otherSettings(after later: DeviceSettingsReading) -> DeviceSettingChange.OtherSettings {

    var changes: [DeviceSettingChange.OtherChange] = []
    var unread: [DeviceSettingChange.UnreadSetting] = []

    // The readings are of the same items and buttons, so their entries line up one for one.
    for (entry, match) in zip(entries, later.entries) {

      guard let before = entry.text else {

        continue

      }

      guard let reported = match.text else {

        unread.append(DeviceSettingChange.UnreadSetting(setting: entry.setting, button: entry.button))

        continue

      }

      if reported != before {

        changes.append(DeviceSettingChange.OtherChange(setting: entry.setting, button: entry.button, before: before, after: reported))

      }

    }

    if changes.isEmpty, unread.count == entries.count(where: { (entry: Entry) -> Bool in entry.text != nil }) {

      return .notReread(.notAnswered)

    }

    return .compared(changes, unread: unread)

  }

}
