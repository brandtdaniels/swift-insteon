import InsteonDeviceCatalog

// Reading the device's other settings before and after a write, to say what else it changed.
extension Device {

  /// The device's settings other than the one a write changes, read before the write and
  /// again after it, the same way ``readSettings(includingAdvanced:beforeReading:)`` reads
  /// them.
  struct OtherSettingsCheck {

    /// The device.
    let device: Device

    /// The settings compared: every one the catalog describes but the setting written and the
    /// readings, which the device reports rather than keeps.
    let items: [SettingItem]

    /// The device's description.
    let description: DeviceDescription

    /// The device's command set.
    let commands: CommandSet

    /// A check of the settings other than `written`.
    init(device: Device, besides written: SettingItem, description: DeviceDescription, commands: CommandSet) {

      self.device = device
      self.items = commands.settingItems.filter { (item: SettingItem) -> Bool in

        if case .reading = item.source {

          return false

        }

        return item.name != written.name

      }
      self.description = description
      self.commands = commands

    }

    /// Reads the other settings before the write, or sends nothing when there are none.
    ///
    /// - Returns: The reading, or `nil` when there are no other settings or the device reported
    ///   none of them.
    func readBefore() async throws -> DeviceSettingsReading? {

      guard !items.isEmpty else {

        return nil

      }

      let reading: DeviceSettingsReading = try await device.read(items, description: description, commands: commands)

      return reading.entries.contains(where: { (entry: DeviceSettingsReading.Entry) -> Bool in entry.text != nil }) ? reading : nil

    }

    /// Reads the other settings again after a write and compares them with `before`.
    ///
    /// A failure to read them doesn't fail the write, which already succeeded: it's reported as
    /// ``DeviceSettingChange/OtherSettings/notReread``. Only cancellation is thrown.
    ///
    /// - Parameter before: The reading before the write.
    /// - Returns: What the other settings did across the write.
    func compare(with before: DeviceSettingsReading?) async throws(CancellationError) -> DeviceSettingChange.OtherSettings {

      guard let before else {

        return .notCompared

      }

      let after: DeviceSettingsReading

      do {

        after = try await device.read(items, description: description, commands: commands)

      } catch let error as CancellationError {

        throw error

      } catch {

        return .notReread

      }

      return before.otherSettings(after: after)

    }

  }

}

extension DeviceSettingsReading {

  /// What the settings did between this reading and a later one of the same items: each one
  /// whose value differs, in order, leaving out one either reading didn't report; or
  /// ``DeviceSettingChange/OtherSettings/notReread`` when the later reading has none of the
  /// values this one has.
  func otherSettings(after: DeviceSettingsReading) -> DeviceSettingChange.OtherSettings {

    let later: [Entry] = after.entries
    var isAnyReread: Bool = false
    var changes: [DeviceSettingChange.OtherChange] = []

    for entry in entries {

      guard
        let before = entry.text,
        let match = later.first(where: { (other: Entry) -> Bool in other.setting.key == entry.setting.key && other.button == entry.button }),
        let reported = match.text
      else {

        continue

      }

      isAnyReread = true

      if reported != before {

        changes.append(DeviceSettingChange.OtherChange(setting: entry.setting, button: entry.button, before: before, after: reported))

      }

    }

    return isAnyReread ? .compared(changes) : .notReread

  }

}
