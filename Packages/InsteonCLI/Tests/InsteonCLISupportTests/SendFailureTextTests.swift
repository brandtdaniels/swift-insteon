import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

/// Which failures to send Beep or a scene the commands word themselves, and how.
struct SendFailureTextTests {

  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  @Test func wordsADeviceThatRejectedOrDidntAnswerBeep() {

    #expect(DeviceText.beepFailure(.deviceRejected(device, .notLinked), device: device) == DeviceText.beepRejected(device, reason: .notLinked))
    #expect(DeviceText.beepFailure(.deviceUnanswered(device), device: device) == DeviceText.beepUnanswered(device))
    #expect(DeviceText.beepFailure(.modemUnanswered, device: device) == nil)
    #expect(DeviceText.beepFailure(nil, device: device) == nil)

  }

  @Test func saysTheModemDoesntSupportABeepItRejectedOrDidntAnswer() {

    #expect(SceneText.beepFailure(.modemRejected, isDouble: false) == "The modem doesn't support Beep: it rejected it.")
    #expect(SceneText.beepFailure(.modemUnanswered, isDouble: true) == "The modem doesn't support a double beep: it didn't answer.")
    #expect(SceneText.beepFailure(.deviceUnanswered(device), isDouble: false) == nil)
    #expect(SceneText.beepFailure(nil, isDouble: false) == nil)

  }

  @Test func explainsAGroupTheModemRejects() {

    #expect(
      SceneText.failure(.modemRejected, group: 3, isOn: true)
        == "The modem rejected Light On for group 3; it does that for a group it has no records for."
    )
    #expect(
      SceneText.failure(.modemRejected, group: 3, isOn: false)
        == "The modem rejected Light Off for group 3; it does that for a group it has no records for."
    )
    #expect(SceneText.failure(.modemUnanswered, group: 3, isOn: true) == nil)

  }

}
