import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

/// What `insteon transfer verify` takes and prints.
@Suite(.timeLimit(.minutes(1)))
struct TransferVerifyTests {

  static let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  static let plug = InsteonAddress(0x4D, 0x5E, 0x6F)

  @Test func readsTheBackupsFile() throws {

    #expect(try Invocation.parse(["transfer", "verify", "home.json"]).subcommand == .transferVerify(path: "home.json"))

  }

  @Test func needsAFileAndTakesNoOptions() {

    #expect(throws: ArgumentError.missingArgument("FILE", subcommand: "transfer verify")) { try Invocation.parse(["transfer", "verify"]) }
    #expect(throws: ArgumentError.self) { try Invocation.parse(["transfer", "verify", "home.json", "--yes"]) }
    #expect(throws: ArgumentError.self) { try Invocation.parse(["transfer", "verify", "home.json", "other.json"]) }

  }

  @Test func helpDescribesVerifyAndAHubProCanRunIt() {

    #expect(HelpText.text(for: "transfer")?.contains("transfer verify FILE") == true)
    #expect(HubProText.runsOnAHubPro(.transferVerify(path: "home.json")))

  }

  @Test func listsEachDeviceWithWhetherItAnswered() {

    let result = TransferVerification(checks: [
      TransferDeviceCheck(address: Self.lamp, name: "Porch"),
      TransferDeviceCheck(address: Self.plug, problem: "The device didn't answer.")
    ])

    #expect(TransferVerifyText.rows(result) == [
      ["ADDRESS", "NAME", "RESULT"],
      ["1A.2B.3C", "Porch", "answered"],
      ["4D.5E.6F", "-", "The device didn't answer."]
    ])

  }

  @Test func summarizesHowManyAnswered() {

    let all = TransferVerification(checks: [TransferDeviceCheck(address: Self.lamp)])
    let some = TransferVerification(checks: [TransferDeviceCheck(address: Self.lamp), TransferDeviceCheck(address: Self.plug, problem: "no")])

    #expect(TransferVerifyText.summary(all) == "All 1 device answered.")
    #expect(TransferVerifyText.summary(some) == "1 of 2 devices answered. Link the others by hand, as the plan lists, and run this again.")
    #expect(TransferVerifyText.summary(TransferVerification(checks: [])) == "The backup holds no devices, so there is nothing to ask.")

  }

}
