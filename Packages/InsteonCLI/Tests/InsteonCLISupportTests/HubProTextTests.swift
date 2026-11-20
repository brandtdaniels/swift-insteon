import Testing
import InsteonCLISupport
import Foundation
import InsteonCore
import InsteonHubPro
import InsteonProtocol

/// What `insteon` says when a Hub Pro is the target: which commands it runs and what it tells
/// a person about the ones it doesn't.
@Suite(.timeLimit(.minutes(1)))
struct HubProTextTests {

  let lamp = InsteonAddress(0x3A, 0x4B, 0x01)

  @Test(arguments: [
    Subcommand.info,
    .hubs,
    .observe(ObserveOptions(device: nil)),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .id),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .ping),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .on(levelPercent: 50)),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .onFast(levelPercent: nil)),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .off),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .offFast),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .beep),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .status),
  ])
  func runsTheReadsAndControlsAHubProOffers(subcommand: Subcommand) {

    #expect(HubProText.runsOnAHubPro(subcommand))

  }

  @Test(arguments: [
    Subcommand.links(LinksOptions()),
    .cancelLinking,
    .beep(isDouble: false),
    .watch(WatchOptions()),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .instant(levelPercent: 10)),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .settings(showsAdvanced: false)),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .links),
    .device(InsteonAddress(0x3A, 0x4B, 0x01), .selfTest(actuates: false, showsChecklist: false)),
  ])
  func refusesTheRestBeforeSendingAnything(subcommand: Subcommand) {

    #expect(!HubProText.runsOnAHubPro(subcommand))

  }

  @Test func sayswhatAHubProCantDo() {

    let message = HubProText.cannot(.device(lamp, .settings(showsAdvanced: false)), host: "192.168.7.20")

    #expect(message.hasPrefix("A Hub Pro can't read or change a device's settings."))
    #expect(message.contains("device ADDRESS status"))

  }

  @Test(arguments: [["link", "3A.4B.01"], ["unlink"], ["remove", "3A.4B.01"]])
  func sendsAddingAndRemovingToTheSetButtons(arguments: [String]) throws {

    let message = HubProText.cannot(try Invocation.parse(arguments).subcommand, host: "192.168.7.20")

    #expect(message.contains("SET button"))
    #expect(message.contains("Hub Pro's manual"))

  }

  @Test func namesNoCommandThatChangesALink() {

    for subcommand in [Subcommand.cancelLinking, .beep(isDouble: true), .links(LinksOptions())] {

      #expect(!HubProText.cannot(subcommand, host: "192.168.7.20").contains("WriteLink"))

    }

  }

  @Test func saysAHubProDidNotAnswerForAnyRequestThatWentUnanswered() {

    let message = HubProText.failure(URLError(.timedOut), host: "192.168.7.20")

    #expect(message == "The Hub Pro at 192.168.7.20 didn't answer. Check that it has power and is on this network.")
    #expect(HubProText.failure(URLError(.cannotConnectToHost), host: "192.168.7.20") == message)

  }

  @Test func saysWhatStatusAHubProAnsweredWith() {

    #expect(HubProText.failure(HubProError.unexpectedStatus(503), host: "192.168.7.20") == "The Hub Pro at 192.168.7.20 answered with HTTP status 503.")
    #expect(HubProText.failure(HubProError.malformedResponse, host: "192.168.7.20") == "The Hub Pro at 192.168.7.20 sent an answer 'insteon' can't read.")

  }

  @Test func leavesAnyOtherErrorToTheCaller() {

    #expect(HubProText.failure(CancellationError(), host: "192.168.7.20") == nil)

  }

  @Test func saysACommandMayHaveReachedTheDevice() {

    let message = HubProText.unconfirmed(lamp)

    #expect(message == "The Hub Pro didn't confirm that 3A.4B.01 took the command, which may have reached it. Read its status before sending the command again.")

  }

}
