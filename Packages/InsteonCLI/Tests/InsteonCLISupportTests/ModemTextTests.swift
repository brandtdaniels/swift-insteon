import Testing
import InsteonCLISupport
import InsteonProtocol

struct ModemTextTests {

  @Test func aModemThatNeverAnswersIsCheckedForConnectionAndPower() {

    let message: String = ModemText.unanswered(command: "Send Insteon Standard or Extended Message")

    #expect(message == "The modem didn't answer Send Insteon Standard or Extended Message. Check that it's connected and powered.")

  }

  @Test func aModemThatStopsEchoingAMessageToADeviceNamesTheDevice() {

    let device: InsteonAddress = InsteonAddress(0x4D, 0x5E, 0x6F)
    let message: String = ModemText.didntConfirmSending(to: device)

    #expect(message == "The modem didn't confirm sending to 4D.5E.6F; it may still be busy with a device that isn't answering. Check that 4D.5E.6F is powered and in range, then try again.")
    #expect(!message.contains("connected and powered"))

  }

}
