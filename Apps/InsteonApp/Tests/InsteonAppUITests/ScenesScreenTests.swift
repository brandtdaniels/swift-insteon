import Foundation
import InsteonClient
import InsteonCore
import InsteonService
import Testing

@testable import InsteonAppUI

/// The scenes screen's acceptance tests, through the calls the screen makes and without a view.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ScenesScreenTests {

  private typealias Fixtures = SceneFixtures

  private func loaded(_ list: SceneList, read: SceneList? = nil) async -> (ScenesScreen<ScriptedScenes>, ScriptedScenes) {
    let network = ScriptedScenes(listed: list, read: read)
    let screen = ScenesScreen(network: network)
    await screen.load()
    return (screen, network)
  }

  // MARK: Listing

  @Test func loadingListsTheScenesWithTheirSourceAndMembers() async {
    let (screen, _) = await loaded(Fixtures.whole([Fixtures.evening, Fixtures.fromKeypad]))

    #expect(screen.state == .loaded)
    #expect(screen.rows.map(\.id) == [3, 2])
    #expect(screen.rows.map(\.title) == ["Scene 3", "Scene 2"])
    #expect(screen.rows.map(\.source) == ["Started by the modem", "Started by 7A.8B.9C"])
    #expect(screen.rows[0].members.map(\.title) == ["1A.2B.3C", "4D.5E.6F"])
  }

  @Test func aSourceTheClientHasNoCaseForIsNamedAsTheServiceWroteIt() async {
    let scene = SceneList.Scene(number: 6, source: .other("cloud"), isWritable: false, members: [Fixtures.described], halfLinks: [])
    let (screen, _) = await loaded(Fixtures.whole([scene]))

    #expect(screen.rows.map(\.source) == ["Started by cloud"])
    #expect(screen.rows[0].canRun == false)
  }

  @Test func aDescribedMemberShowsWhatEachByteMeansAndLeavesOutTheGroupByte() async {
    let (screen, _) = await loaded(Fixtures.whole())

    let member = screen.rows[0].members[0]

    #expect(member.detail == "On-level: On. Ramp rate: 0x1F.")
    #expect(!member.isUndescribed)
  }

  @Test func anUndescribedMemberShowsItsRawBytesAndSaysTheCatalogDoesNotDescribeThem() async {
    let (screen, _) = await loaded(Fixtures.whole())

    let member = screen.rows[0].members[1]

    #expect(member.detail == "Data 0x80 0x1C 0x00. The device catalog doesn't describe these bytes.")
    #expect(member.isUndescribed)
  }

  @Test func aSceneTheModemStartsWithMembersCanRunAndOthersSayWhyNot() async {
    let (screen, _) = await loaded(Fixtures.whole([Fixtures.evening, Fixtures.empty, Fixtures.fromKeypad]))

    #expect(screen.rows.map(\.canRun) == [true, false, false])
    #expect(screen.rows[0].note == nil)
    #expect(screen.rows[1].note == "It has no members, so there is nothing to run.")
    #expect(screen.rows[2].note == "A device starts this scene, so it can't be run from here.")
  }

  @Test func aWholeListSaysItIsWholeAndHasNoGaps() async {
    let (screen, _) = await loaded(Fixtures.whole())

    #expect(screen.isWhole)
    #expect(screen.gaps.isEmpty)
  }

  @Test func aListThatIsNotWholeSaysWhichDevicesWereNotReadAndWhy() async {
    let list = Fixtures.partial(
      unreadable: [
        SceneList.UnreadableDevice(address: Fixtures.lamp, reason: .noAnswer),
        SceneList.UnreadableDevice(address: Fixtures.ceiling, reason: .rejectedModem),
        SceneList.UnreadableDevice(address: Fixtures.keypad, reason: .notCached)
      ])
    let (screen, _) = await loaded(list)

    #expect(!screen.isWhole)
    #expect(screen.gaps == [
      "1A.2B.3C wasn't read: it didn't answer.",
      "4D.5E.6F wasn't read: it rejected the modem.",
      "7A.8B.9C wasn't read: the service hasn't read it yet."
    ])
  }

  @Test func everyReasonADeviceCanBeUnreadHasItsOwnWords() async {
    let reasons: [SceneList.UnreadableReason] = [
      .noAnswer, .rejectedModem, .damagedRecords, .notCached, .unavailableFromSource, .modemStoppedEchoing, .hubStoppedAnswering, .failed, .incomplete, .other("laterReason")
    ]
    var seen: Set<String> = []
    for reason in reasons {
      let (screen, _) = await loaded(Fixtures.partial(unreadable: [SceneList.UnreadableDevice(address: Fixtures.lamp, reason: reason)]))
      #expect(screen.gaps.count == 1)
      seen.insert(screen.gaps[0])
    }

    #expect(seen.count == reasons.count)
    #expect(seen.allSatisfy { !$0.contains("other(") })
  }

  @Test func theModemNotReadDevicesWithNoListAndHalfLinksAreGapsToo() async {
    let half = SceneList.HalfLink(endpoint: .modem, group: 9, address: Fixtures.lamp, role: .controller, data: [0, 0, 0])
    let list = Fixtures.partial(unlisted: [Fixtures.keypad], isModemUnread: true, looseHalfLinks: [half])
    let (screen, _) = await loaded(list)

    #expect(screen.gaps == [
      "The modem's own database wasn't read.",
      "7A.8B.9C has no ALL-Link database the service could read.",
      "1 record has no matching record on the other device."
    ])
  }

  @Test func halfLinksInAScenesCountWithTheLooseOnes() async {
    let half = SceneList.HalfLink(endpoint: .modem, group: 3, address: Fixtures.lamp, role: .controller, data: [0, 0, 0])
    let scene = SceneList.Scene(number: 3, source: .modem, isWritable: true, members: [Fixtures.described], halfLinks: [half, half])
    let (screen, _) = await loaded(Fixtures.partial([scene], looseHalfLinks: [half]))

    #expect(screen.gaps == ["3 records have no matching record on the other device."])
  }

  @Test func aListThatIsNotWholeForAReasonTheScreenCannotNameStillSaysSo() async {
    let (screen, _) = await loaded(Fixtures.partial())

    #expect(!screen.isWhole)
    #expect(screen.gaps == ["The list may be incomplete."])
  }

  // MARK: Empty and failed

  @Test func aNetworkWithNoScenesSaysSoWhenTheListIsWhole() async {
    let (screen, _) = await loaded(Fixtures.whole([]))

    #expect(screen.isEmpty)
    #expect(screen.emptyMessage == "This network has no scenes.")
  }

  @Test func anEmptyListThatWasNotReadSaysToReadIt() async {
    let (screen, _) = await loaded(Fixtures.partial([], isModemUnread: true))

    #expect(screen.isEmpty)
    #expect(screen.emptyMessage == "No scenes have been read yet. Read them from the network to see them.")
  }

  @Test func aFailedLoadKeepsTheRowsFromBeforeAndSaysWhy() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setListFailure(ConnectionError.noPathReached([]))

    await screen.load()

    #expect(screen.rows.map(\.id) == [3])
    #expect(screen.failure == "The service couldn't be reached.")
    #expect(!screen.isEmpty)
  }

  @Test func aFailedFirstLoadHasNoRowsAndAFailure() async {
    let network = ScriptedScenes(listed: Fixtures.whole())
    await network.setListFailure(ConnectionError.unauthorized(paths: ["lan"]))
    let screen = ScenesScreen(network: network)

    await screen.load()

    #expect(screen.rows.isEmpty)
    #expect(screen.failure == "The service refused this device's credential. Pair this device again.")
    #expect(screen.state == .failed("The service refused this device's credential. Pair this device again."))
  }

  @Test func aLaterGoodLoadClearsTheFailure() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setListFailure(ConnectionError.noPathReached([]))
    await screen.load()
    await network.setListFailure(nil)

    await screen.load()

    #expect(screen.failure == nil)
    #expect(screen.state == .loaded)
  }

  // MARK: Refreshing

  @Test func refreshingReadsTheHardwareAndShowsWhatWasRead() async {
    let (screen, network) = await loaded(Fixtures.partial([], isModemUnread: true), read: Fixtures.whole())

    await screen.refresh()

    #expect(await network.calls == ["scenes", "refreshScenes"])
    #expect(screen.rows.map(\.id) == [3])
    #expect(screen.isWhole)
    #expect(!screen.isRefreshing)
  }

  @Test func whileARefreshIsOutTheScreenSaysSoAndNothingElseCanStart() async {
    let (screen, network) = await loaded(Fixtures.whole([]), read: Fixtures.whole())
    await network.holdNextRefresh()

    async let refreshed: Void = screen.refresh()
    await network.waitForHeldRefresh()
    #expect(screen.isRefreshing)
    #expect(screen.isBusy)
    await screen.refresh()
    #expect(await network.calls == ["scenes", "refreshScenes"], "a second refresh is not sent")
    await network.releaseRefresh()
    await refreshed

    #expect(!screen.isRefreshing && !screen.isBusy)
    #expect(screen.rows.map(\.id) == [3])
  }

  @Test func aFailedRefreshKeepsTheRowsAndSaysWhy() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setRefreshFailure(ServiceControlError.busy)

    await screen.refresh()

    #expect(screen.rows.map(\.id) == [3])
    #expect(screen.failure == "The service is busy with another request. Try again.")
    #expect(!screen.isRefreshing)
  }

  @Test func aRefreshThatLostItsConnectionSaysTheServiceMayStillBeReading() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setRefreshFailure(ConnectionError.interrupted(path: "lan"))

    await screen.refresh()

    #expect(screen.failure == "The connection was lost during the read. The service may still be reading: load the list again in a minute.")
  }

  @Test func aHubProSaysItDoesNotGiveOutItsDatabases() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setRefreshFailure(ServiceControlError.databasesUnavailable)

    await screen.refresh()

    #expect(screen.failure == "This network doesn't give out its ALL-Link databases.")
  }

  // MARK: Running

  @Test func runningASceneOnSendsItsNumberAndActionOnce() async {
    let (screen, network) = await loaded(Fixtures.whole())

    await screen.run(screen.rows[0], .on)

    let runs = await network.runs
    #expect(runs.count == 1 && runs[0].number == 3 && runs[0].action == .on)
  }

  @Test func runningASceneOffSendsOff() async {
    let (screen, network) = await loaded(Fixtures.whole())

    await screen.run(screen.rows[0], .off)

    #expect(await network.runs.map(\.action) == [.off])
  }

  @Test func aSceneThatCannotRunIsNeverSent() async {
    let (screen, network) = await loaded(Fixtures.whole([Fixtures.empty, Fixtures.fromKeypad]))

    await screen.run(screen.rows[0], .on)
    await screen.run(screen.rows[1], .on)

    #expect(await network.runs.isEmpty)
    #expect(screen.outcome == nil)
  }

  @Test func aRunThatReachedEveryMemberSaysSoAndCountsWhoAcknowledged() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setReceipt(SceneRunReceipt(scene: 3, action: .on, acknowledged: [Fixtures.lamp, Fixtures.ceiling], unacknowledged: [], isComplete: true, responderCount: 2, persistence: .saved))

    await screen.run(screen.rows[0], .on)

    #expect(screen.outcome == RunOutcome(kind: .complete, title: "Scene 3 turned on.", message: "The modem reached every member, and 2 acknowledged."))
  }

  @Test func aModemThatReportsNoPerMemberAcknowledgmentIsNotReadAsNoMemberActed() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setReceipt(SceneRunReceipt(scene: 3, action: .off, acknowledged: [], unacknowledged: [], isComplete: true, responderCount: 2, persistence: .notConfigured))

    await screen.run(screen.rows[0], .off)

    #expect(screen.outcome == RunOutcome(kind: .complete, title: "Scene 3 turned off.", message: "The modem reports that it reached every member. It doesn't say which acknowledged."))
  }

  @Test func aRunThatDidNotReachEveryMemberSaysWhichDidNotAcknowledgeAndThatTheyMayHaveActed() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setReceipt(SceneRunReceipt(scene: 3, action: .on, acknowledged: [Fixtures.lamp], unacknowledged: [Fixtures.ceiling], isComplete: false, responderCount: 2, persistence: .saved))

    await screen.run(screen.rows[0], .on)

    #expect(screen.outcome == RunOutcome(
      kind: .incomplete, title: "Scene 3 turned on, but not every member answered.",
      message: "The modem didn't report reaching every member, so some lights may not have changed. Not acknowledged: 4D.5E.6F. They may still have acted."))
  }

  @Test func anIncompleteRunWithNoMemberListedStillSaysSomeLightsMayNotHaveChanged() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setReceipt(SceneRunReceipt(scene: 3, action: .on, acknowledged: [], unacknowledged: [], isComplete: false, responderCount: 2, persistence: .notConfigured))

    await screen.run(screen.rows[0], .on)

    #expect(screen.outcome?.kind == .incomplete)
    #expect(screen.outcome?.message == "The modem didn't report reaching every member, so some lights may not have changed.")
  }

  @Test func aRunThatReachedEveryMemberButSomeDidNotAcknowledgeIsNotCalledComplete() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setReceipt(SceneRunReceipt(scene: 3, action: .on, acknowledged: [Fixtures.lamp], unacknowledged: [Fixtures.ceiling], isComplete: true, responderCount: 2, persistence: .saved))

    await screen.run(screen.rows[0], .on)

    #expect(screen.outcome == RunOutcome(
      kind: .incomplete, title: "Scene 3 turned on, but not every member answered.",
      message: "The modem reached every member, but some didn't acknowledge. Not acknowledged: 4D.5E.6F. They may still have acted."))
  }

  @Test func aRunWhoseAnswerWasLostSaysTheLightsMayHaveChanged() async {
    let lights = "The command may have gone out before the answer was lost. The lights may have changed. Check the devices before running the scene again."
    let losses: [any Error] = [ConnectionError.interrupted(path: "lan"), ConnectionError.badResponse(path: "lan"), ConnectionError.outcomeUnknown(sent: true), ConnectionError.rejected(code: "later", sent: true)]
    for loss in losses {
      let (screen, network) = await loaded(Fixtures.whole())
      await network.setRunFailure(loss)

      await screen.run(screen.rows[0], .on)

      #expect(screen.outcome == RunOutcome(kind: .unknown, title: "Scene 3 may have run.", message: lights), "\(loss)")
    }
  }

  @Test func aRunTheServiceRefusedBeforeSendingSaysNothingWasSent() async {
    let table: [(any Error, String)] = [
      (ServiceControlError.busy, "The service is busy with another request. Try again."),
      (ServiceControlError.modemUnavailable(.hubUnreachable), "The service can't reach its modem right now."),
      (ServiceControlError.unknownScene, "The service doesn't know that scene. Read the scenes again."),
      (ServiceControlError.sceneEmpty, "That scene has no members."),
      (ServiceControlError.databasesUnavailable, "This network doesn't give out its ALL-Link databases."),
      (ConnectionError.invalidScene, "That isn't a scene the service can run."),
      (ConnectionError.idempotencyKeyReused, "The service already used that request's key for a different command."),
      (ConnectionError.noPathReached([]), "The service couldn't be reached."),
      (ConnectionError.unauthorized(paths: ["lan"]), "The service refused this device's credential. Pair this device again."),
      (ConnectionError.forbidden(path: "lan"), "This device isn't allowed to control the service."),
      (ConnectionError.unsupported(paths: ["lan"]), "This connection can't run scenes."),
      (ConnectionError.rejected(code: "modemRejected", sent: false), "The service refused the request (modemRejected)."),
      (ConnectionError.modemUnavailable(cause: "hubErrorStatus"), "The service can't reach its modem right now.")
    ]
    for (error, text) in table {
      let (screen, network) = await loaded(Fixtures.whole())
      await network.setRunFailure(error)

      await screen.run(screen.rows[0], .on)

      #expect(screen.outcome == RunOutcome(kind: .refused, title: "Scene 3 wasn't run.", message: text + " Nothing was sent."), "\(error)")
    }
  }

  @Test func aErrorOfAnotherKindIsTreatedAsUnknownSinceTheScreenCannotTellIfItWasSent() async {
    struct Odd: Error {}
    let (screen, network) = await loaded(Fixtures.whole())
    await network.setRunFailure(Odd())

    await screen.run(screen.rows[0], .on)

    #expect(screen.outcome?.kind == .unknown)
  }

  @Test func whileARunIsOutTheScreenIsBusyAndAnotherRunIsNotSent() async {
    let (screen, network) = await loaded(Fixtures.whole([Fixtures.evening, SceneList.Scene(number: 5, source: .modem, isWritable: true, members: [Fixtures.described], halfLinks: [])]))
    await network.holdNextRun()
    let first = screen.rows[0]

    async let ran: Void = screen.run(first, .on)
    await network.waitForHeldRun()
    #expect(screen.isBusy)
    #expect(screen.isRunning(first))
    #expect(!screen.isRunning(screen.rows[1]))
    await screen.run(screen.rows[1], .off)
    await screen.refresh()
    #expect(await network.calls == ["scenes", "runScene"], "nothing else is sent while a run is out")
    await network.releaseRun()
    await ran

    #expect(!screen.isBusy)
    #expect(screen.outcome?.kind == .complete)
  }

  @Test func aNewRunReplacesTheOutcomeOfTheLastAndItCanBeDismissed() async {
    let (screen, network) = await loaded(Fixtures.whole())
    await screen.run(screen.rows[0], .on)
    #expect(screen.outcome?.title == "Scene 3 turned on.")

    await screen.run(screen.rows[0], .off)
    #expect(screen.outcome?.title == "Scene 3 turned off.")
    screen.dismissOutcome()

    #expect(screen.outcome == nil)
    #expect(await network.runs.count == 2)
  }

  @Test func aRunDoesNotChangeTheListedScenes() async {
    let (screen, network) = await loaded(Fixtures.whole())
    let before = screen.rows

    await screen.run(screen.rows[0], .on)

    #expect(screen.rows == before)
    #expect(await network.calls == ["scenes", "runScene"], "a run reads nothing afterward")
  }

  // MARK: Overlapping calls

  @Test func aLoadWhileARefreshIsOutIsNotSentSoTheRefreshDecidesWhatIsShown() async {
    let (screen, network) = await loaded(Fixtures.whole([]), read: Fixtures.whole())
    await network.holdNextRefresh()

    async let refreshed: Void = screen.refresh()
    await network.waitForHeldRefresh()
    await screen.load()
    #expect(await network.calls == ["scenes", "refreshScenes"])
    await network.releaseRefresh()
    await refreshed

    #expect(screen.rows.map(\.id) == [3])
    #expect(screen.state == .loaded)
  }

  @Test func aLaterLoadReplacesTheRows() async {
    let network = ScriptedScenes(listed: Fixtures.whole([Fixtures.evening]))
    let screen = ScenesScreen(network: network)

    await screen.load()
    await network.setListed(Fixtures.whole([Fixtures.fromKeypad]))
    await screen.load()

    #expect(screen.rows.map(\.id) == [2])
  }
}
