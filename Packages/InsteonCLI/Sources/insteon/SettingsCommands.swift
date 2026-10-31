import InsteonCLISupport
import InsteonCore

/// `insteon device ADDRESS settings` and `set`: reads and changes the settings the Insteon
/// device catalog describes, through a `Device`.
enum SettingsCommands {

  // MARK: - settings

  static func show(_ device: Device, showsAdvanced: Bool, printsJSON: Bool) async throws {

    let address: String = "\(device.address)"
    let reading: DeviceSettingsReading

    do {

      reading = try await device.readSettings(includingAdvanced: showsAdvanced, beforeReading: { () -> Void in

        Output.note("Reading the settings of \(address)...")

      })

    } catch let error as DeviceSettingError {

      throw CommandFailure(description: SettingsText.failure(error, device: address))

    }

    let lines: [SettingLine] = SettingsText.lines(for: reading)

    if printsJSON {

      try Output.json(lines)

      return

    }

    printLines(lines, device: address, product: reading.productName)

    let hidden: Int = reading.advancedSettingsLeftOut

    if hidden > 0 {

      Output.line("\(Wording.count(hidden, "advanced setting")) not shown; --advanced shows them.")

    }

    if lines.contains(where: \.isWritable) {

      Output.line("Change a writable one with 'insteon device \(address) set NAME VALUE'.")

    }

  }

  private static func printLines(_ lines: [SettingLine], device: String, product: String?) {

    let named: String = product.map { ", " + $0 } ?? ""

    Output.line("Settings of \(device)\(named):")

    var rows: [[String]] = []
    var section: String?

    for line in lines {

      if line.section != section {

        rows.append([""])
        rows.append([line.section])
        section = line.section

      }

      rows.append(["  " + line.title + ":", line.valueText, line.notes])

    }

    Output.table(rows)
    Output.line()

  }

  // MARK: - set

  static func set(_ request: SettingRequest, device: Device) async throws {

    let change: DeviceSettingChange

    do {

      change = try await device.writeSetting(request.name, to: request.value, button: request.button.map { (button: UInt8) -> Int in Int(button) })

    } catch let error as DeviceSettingError {

      throw CommandFailure(description: SettingsText.failure(error, device: "\(device.address)"))

    }

    Output.line(SettingsText.change(change))

  }

}
