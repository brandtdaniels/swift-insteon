import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Reading the device's settings.
extension Device {

  /// Reads the device's settings the catalog describes: each Get Operating Flags request they
  /// need, once, and an extended Get for button 1, then for each of the device's other groups
  /// when a value is per button.
  ///
  /// A request the device rejects or doesn't answer leaves its settings unreported, rather
  /// than failing the reading.
  ///
  /// - Parameters:
  ///   - includingAdvanced: Whether to read the settings a settings page keeps out of sight
  ///     unless asked. Defaults to `true`.
  ///   - beforeReading: Called once the settings are known and before the device is asked for
  ///     them, so an app can say that a reading has begun. Defaults to doing nothing.
  /// - Returns: The settings and what the device reported.
  /// - Throws: ``DeviceSettingError/notIdentified`` or ``DeviceSettingError/noSettings(product:)``
  ///   when the settings aren't known, the errors of ``info()``, and the modem's
  ///   errors.
  public func readSettings(includingAdvanced: Bool = true, beforeReading: @Sendable () -> Void = {}) async throws -> DeviceSettingsReading {

    let (description, commands): (DeviceDescription, CommandSet) = try await describedSettings()
    let items: [SettingItem] = commands.settingItems.filter { (item: SettingItem) -> Bool in includingAdvanced || !item.isAdvanced }

    beforeReading()

    var flags: [OperatingFlagsRequest: UInt8] = [:]

    for query in Self.queries(of: items) {

      if let acknowledgment = try await answer(StandardMessage(to: address, command: StandardDirectCommand.getOperatingFlags(query))) {

        flags[query] = acknowledgment.command.command2

      }

    }

    let buttons: [UInt8] = Self.buttons(for: items, in: commands, description: description)
    var values: [UInt8: [SettingName: UInt8]] = [:]

    if let settings = commands.extendedSettings, items.contains(where: { (item: SettingItem) -> Bool in Self.isValue(item) }) {

      for button in buttons {

        if let reported = try await readValues(settings: settings, button: button) {

          values[button] = reported

        }

      }

    }

    return DeviceSettingsReading(
      productName: description.displayName,
      commandSet: commands,
      items: items,
      operatingFlags: flags,
      values: values,
      buttons: buttons
    )

  }

  /// Changes one of the device's settings, and reads it back to confirm the change.
  ///
  /// Some settings are never written: turning off the device's radio or powerline, and
  /// requiring a checksum in every message, any of which can cut the device off from the
  /// modem, and any other flag the catalog guards with `FlagGuard.keep`. The programming lock,
  /// and any flag the catalog guards with `FlagGuard.neverSet`, is only turned off, never on,
  /// so a device is never left locked. A command the catalog guards with `CommandGuard.never`
  /// is never sent, nor is a Set Operating Flags command with the same bytes. All of these are
  /// refused before anything is sent, and the radio, powerline, checksum and programming lock
  /// flags are refused even when the catalog gives no guard. A value whose byte holds
  /// operating flags, which the catalog marks with `SettingValue.flagsQuery`, such as an
  /// open/close sensor's configuration byte, is refused before it's written when it would set
  /// a bit that's never set, or change a bit that's kept; the device is asked for the byte
  /// first, to compare. The guarded bits of an extended command's flags parameter are checked
  /// the same way.
  ///
  /// A flag is changed with Set Operating Flags, in the form the device takes: extended with a
  /// checksum for an i2CS device, extended with the command repeated while the flag the
  /// catalog names in `OperatingFlag.extendedWhen` is set, and standard otherwise; or with the
  /// standard command the catalog names for the state. A value is changed with an extended Set
  /// that keeps the other values it writes as the device reported them, or with the extended
  /// command the catalog names.
  ///
  /// - Parameters:
  ///   - key: The setting's key, such as `"rampRate"`, or its label, in any case.
  ///   - text: The value, such as `"on"`, `"0.5 s"`, `"50%"` or `"0x1C"`.
  ///   - button: The button or group, for a setting that's per button, or `nil` for button 1.
  ///     Defaults to `nil`.
  /// - Returns: The value before and after. A change the device didn't report afterward isn't
  ///   confirmed.
  /// - Throws: ``DeviceSettingError`` when the setting or the value isn't one the device takes,
  ///   ``DeviceSettingError/neverWritten(label:)`` or
  ///   ``DeviceSettingError/leavesProgrammingLocked(label:)`` for a setting that isn't written,
  ///   or ``DeviceSettingError/notChanged(title:requested:reported:)`` when the device reports
  ///   another value afterward; ``DeviceControlError/noSuchGroup(_:product:)`` for a button
  ///   that isn't a group number; and the modem's errors.
  public func writeSetting(_ key: String, to text: String, button: Int? = nil) async throws -> DeviceSettingChange {

    let (description, commands): (DeviceDescription, CommandSet) = try await describedSettings()

    guard let item = commands.settingItem(named: key) else {

      throw DeviceSettingError.noSuchSetting(key, product: DeviceControlModel.product(of: description))

    }

    // Refused before anything is sent, whatever the catalog says about writing it.
    if DeviceSettingSafety.isNeverWritten(item, in: commands) {

      throw DeviceSettingError.neverWritten(label: item.label)

    }

    var buttonNumber: UInt8?

    if let button {

      guard let number = UInt8(exactly: button) else {

        throw DeviceControlError.noSuchGroup(button, product: DeviceControlModel.product(of: description))

      }

      buttonNumber = number

    }

    let setting: DeviceSetting = SettingPresentation.setting(for: item, in: commands)
    let change: DeviceSettingChange

    switch item.source {
    case .reading:
      throw DeviceSettingError.isReading(label: item.label)
    case let .flag(flag):
      change = try await write(flag, item: item, setting: setting, to: text, button: buttonNumber, description: description, commands: commands)
    case let .value(value):
      change = try await write(value, item: item, setting: setting, to: text, button: buttonNumber, commands: commands)
    }

    if change.isConfirmed {

      await network.recordAnswer(of: address, level: nil)

    }

    return change

  }

}
