import Foundation
import Testing
import InsteonCLISupport
import InsteonCore

/// What `insteon device ADDRESS set` prints about the other settings a write changed, as text
/// and as JSON, for made-up settings.
struct SettingChangeTextTests {

  let lingerTime = DeviceSetting(
    key: "lingerTime",
    label: "Linger time",
    section: "Load",
    summary: "How long the load lingers.",
    isAdvanced: false,
    isWritable: true,
    isPerButton: false,
    control: .byte(range: nil)
  )

  let sparkle = DeviceSetting(
    key: "sparkle",
    label: "Sparkle",
    section: "Load",
    summary: "Sparkles.",
    isAdvanced: false,
    isWritable: false,
    isPerButton: false,
    control: .toggle
  )

  let glimmer = DeviceSetting(
    key: "glimmer",
    label: "Glimmer",
    section: "Load",
    summary: "How much the load glimmers.",
    isAdvanced: false,
    isWritable: true,
    isPerButton: true,
    control: .byte(range: nil)
  )

  func change(_ otherSettings: DeviceSettingChange.OtherSettings, button: Int? = nil) -> DeviceSettingChange {

    DeviceSettingChange(setting: lingerTime, button: button, before: "0x00", requested: "0x05", after: "0x05", otherSettings: otherSettings)

  }

  func report(_ change: DeviceSettingChange) -> [String] {

    SettingsText.report(change, device: "1A.2B.3C")

  }

  // MARK: - Text

  @Test func printsALineForEachOtherSettingTheWriteChanged() {

    let written: DeviceSettingChange = change(.compared([
      DeviceSettingChange.OtherChange(setting: sparkle, button: nil, before: "off", after: "on"),
      DeviceSettingChange.OtherChange(setting: glimmer, button: 2, before: "0x10", after: "0x00")
    ]))

    #expect(report(written) == [
      "Linger time: 0x00 → 0x05",
      "Also changed: Sparkle: off → on",
      "Also changed: Glimmer (button 2): 0x10 → 0x00"
    ])

  }

  @Test func printsOnlyTheSettingWrittenWhenNothingElseChangedOrNothingWasCompared() {

    #expect(report(change(.compared([]))) == ["Linger time: 0x00 → 0x05"])

    for outcome: DeviceSettingChange.OtherSettings.Outcome in [.nothingToCompare, .notReportedBefore, .notConfirmed] {

      #expect(report(change(DeviceSettingChange.OtherSettings(outcome: outcome))) == ["Linger time: 0x00 → 0x05"])

    }

  }

  @Test func namesTheOtherSettingsThatCouldntBeReadAgain() {

    let written: DeviceSettingChange = change(.compared(
      [DeviceSettingChange.OtherChange(setting: sparkle, button: nil, before: "off", after: "on")],
      unread: [DeviceSettingChange.UnreadSetting(setting: glimmer, button: 2), DeviceSettingChange.UnreadSetting(setting: sparkle, button: nil)]
    ))

    #expect(report(written) == [
      "Linger time: 0x00 → 0x05",
      "Also changed: Sparkle: off → on",
      "Couldn't be read again after the write: Glimmer (button 2), Sparkle; run 'insteon device 1A.2B.3C settings' to see them."
    ])

  }

  @Test func saysTheWriteSucceededWhenTheOtherSettingsCouldntBeReadAgain() {

    #expect(report(change(.notReread(.connectionClosed))) == [
      "Linger time: 0x00 → 0x05",
      "The write succeeded, but the device's other settings couldn't be read again (the connection to the modem closed), so what else it changed isn't known; run 'insteon device 1A.2B.3C settings' to see them."
    ])
    #expect(report(change(.notReread(.notAnswered))).last?.contains("(the device didn't answer)") == true)
    #expect(report(change(.notReread(.canceled))).last?.contains("(the command was canceled)") == true)

  }

  // MARK: - JSON

  func json(_ change: DeviceSettingChange) throws -> [String: Any] {

    let data: Data = try JSONEncoder().encode(SettingChangeJSON(change))

    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

  }

  @Test func printsTheChangedAndUnreadSettingsAsJSON() throws {

    let object: [String: Any] = try json(change(
      .compared(
        [
          DeviceSettingChange.OtherChange(setting: sparkle, button: nil, before: "off", after: "on"),
          DeviceSettingChange.OtherChange(setting: glimmer, button: 2, before: "0x10", after: "0x00")
        ],
        unread: [DeviceSettingChange.UnreadSetting(setting: glimmer, button: 3)]
      ),
      button: 2
    ))
    let changed: [[String: Any]] = try #require(object["changedSettings"] as? [[String: Any]])
    let unread: [[String: Any]] = try #require(object["unreadSettings"] as? [[String: Any]])

    #expect(object["name"] as? String == "lingerTime")
    #expect(object["label"] as? String == "Linger time")
    #expect(object["button"] as? Int == 2)
    #expect(object["before"] as? String == "0x00")
    #expect(object["requested"] as? String == "0x05")
    #expect(object["after"] as? String == "0x05")
    #expect(object["otherSettings"] as? String == "compared")
    #expect(object["rereadFailure"] == nil)
    #expect(changed.count == 2)
    #expect(changed.first?["name"] as? String == "sparkle")
    #expect(changed.first?["label"] as? String == "Sparkle")
    #expect(changed.first?["before"] as? String == "off")
    #expect(changed.first?["after"] as? String == "on")
    #expect(changed.first?["button"] == nil)
    #expect(changed.last?["button"] as? Int == 2)
    #expect(unread.count == 1)
    #expect(unread.first?["name"] as? String == "glimmer")
    #expect(unread.first?["label"] as? String == "Glimmer")
    #expect(unread.first?["button"] as? Int == 3)

  }

  @Test func leavesOutTheButtonOfASettingThatIsntPerButton() throws {

    #expect(try json(change(.compared([])))["button"] == nil)

  }

  @Test func saysHowTheComparisonEndedAsJSON() throws {

    let unread: [String: Any] = try json(change(.notReread(.connectionClosed)))

    #expect((unread["changedSettings"] as? [Any])?.isEmpty == true)
    #expect((unread["unreadSettings"] as? [Any])?.isEmpty == true)
    #expect(unread["otherSettings"] as? String == "notReread")
    #expect(unread["rereadFailure"] as? String == "connectionClosed")

    let outcomes: [DeviceSettingChange.OtherSettings.Outcome] = [.nothingToCompare, .notReportedBefore, .notConfirmed]
    let names: [String?] = try outcomes.map { (outcome: DeviceSettingChange.OtherSettings.Outcome) -> String? in

      try json(change(DeviceSettingChange.OtherSettings(outcome: outcome)))["otherSettings"] as? String

    }

    #expect(names == ["nothingToCompare", "notReportedBefore", "notConfirmed"])

  }

}
