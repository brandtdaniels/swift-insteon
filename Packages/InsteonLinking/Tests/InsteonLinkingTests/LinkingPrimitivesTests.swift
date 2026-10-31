import Testing
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Collects values a callback reports, so a test can check them afterwards.
actor Recorder<Value: Sendable> {

  private(set) var values: [Value] = []

  func record(_ value: Value) {

    values.append(value)

  }

}

/// Waiting for replies, manual linking with a ready callback, link mismatches, the modem's
/// links with a device, responder state and remote unlinking, on a ``TestClock`` that moves
/// only when a test advances it.
@Suite(.timeLimit(.minutes(1)))
struct LinkingPrimitivesTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let other = InsteonAddress(0x44, 0x55, 0x66)

  let clock = TestClock()

  func linker(_ modem: InMemoryModem) -> Linker {

    Linker(modem: modem, clock: clock)

  }

  func unlinker(_ modem: InMemoryModem) -> Unlinker {

    Unlinker(modem: modem, clock: clock)

  }

  func completed(_ mode: AllLinkMode, group: AllLinkGroupNumber, address: InsteonAddress) -> AllLinkingCompleted {

    AllLinkingCompleted(linkCode: mode.rawValue, group: group, address: address, category: nil, subcategory: nil, firmwareVersion: nil)

  }

  // MARK: - Waiting for a reply

  @Test func hearsAReplyToWhatItSends() async throws {

    let modem = InMemoryModem()
    let device = lamp
    await modem.setIdentity(SetButtonPressed(sender: device, role: .responder, category: 0x01, subcategory: 0x19, firmwareVersion: 0x41))

    let sender: InsteonAddress? = try await modem.firstReply(
      within: .seconds(1),
      clock: clock,
      after: { await modem.broadcastIdentity(of: device) },
      matching: { (reply: ModemReply) -> InsteonAddress? in

        guard case let .messageReceived(message) = reply else {

          return nil

        }

        return message.sender

      }
    )

    #expect(sender == device)

  }

  @Test func returnsNothingWhenNoReplyMatchesInTime() async throws {

    let modem = InMemoryModem()
    let clock = clock

    async let reply: Int? = modem.firstReply(
      within: .seconds(2),
      clock: clock,
      after: {},
      matching: { (_: ModemReply) -> Int? in 1 }
    )
    await clock.waitForSleeper(until: .seconds(2))
    clock.advance(by: .seconds(2))

    #expect(try await reply == nil)

  }

  @Test func throwsWhatTheMatchThrows() async throws {

    let modem = InMemoryModem()
    let device = lamp
    await modem.setIdentity(SetButtonPressed(sender: device, role: .responder, category: 0x01, subcategory: 0x19, firmwareVersion: 0x41))

    await #expect(throws: LinkingError.linkingTimedOut) {

      _ = try await modem.firstReply(
        within: .seconds(1),
        clock: clock,
        after: { await modem.broadcastIdentity(of: device) },
        matching: { (_: ModemReply) throws -> Int? in throw LinkingError.linkingTimedOut }
      )

    }

  }

  // MARK: - Mismatches

  @Test func acceptsTheLinkAskedFor() {

    #expect(LinkMismatch(completed(.controller, group: 0, address: lamp), direction: .linking, device: lamp) == nil)
    #expect(LinkMismatch(completed(.delete, group: 0, address: lamp), direction: .unlinking, device: nil) == nil)

  }

  @Test func namesAnotherDeviceBeforeTheWrongDirection() {

    let link = completed(.delete, group: 0, address: other)

    #expect(LinkMismatch(link, direction: .linking, device: lamp) == LinkMismatch(link: link, reason: .otherDevice(expected: lamp)))

  }

  @Test func tellsLinkingAndUnlinkingApart() {

    let linked = completed(.responder, group: 1, address: lamp)
    let removed = completed(.delete, group: 1, address: lamp)

    #expect(LinkMismatch(linked, direction: .unlinking, device: lamp)?.reason == .linkedInsteadOfUnlinking)
    #expect(LinkMismatch(removed, direction: .linking, device: nil)?.reason == .unlinkedInsteadOfLinking)

  }

  // MARK: - Manual linking

  @Test func linksInEitherRoleOnceTheModemIsReady() async throws {

    let modem = InMemoryModem()
    let device = lamp

    // The device's SET button is pressed only once the modem says it's ready.
    let link = try await linker(modem).linkManually(as: .either, group: 0x00) {

      await modem.pressSetButton(of: device)

    }

    #expect(link.address == lamp)
    #expect(await modem.linkingSteps == [.modem(.controllerOrResponder, 0x00)])

  }

  @Test func throwsAMismatchWhenAnotherDeviceLinksManually() async throws {

    let modem = InMemoryModem()
    let device = other
    let expected = LinkMismatch(link: completed(.controller, group: 0x00, address: other), reason: .otherDevice(expected: lamp))

    await #expect(throws: expected) {

      try await linker(modem).linkManually(as: .controller, group: 0x00, device: lamp) {

        await modem.pressSetButton(of: device)

      }

    }

    // The modem left linking mode on its own when it reported the link.
    #expect(await modem.linkingSteps == [.modem(.controller, 0x00)])

  }

  @Test func takesTheModemOutOfLinkingModeWhenNoDeviceLinks() async throws {

    let modem = InMemoryModem()

    await #expect(throws: LinkingError.linkingTimedOut) {

      async let link = linker(modem).linkManually(as: .responder, group: 0x01)
      await clock.waitForSleeper(until: Linker.defaultManualLinkingTimeout)
      clock.advance(by: Linker.defaultManualLinkingTimeout)
      _ = try await link

    }

    #expect(await modem.linkingSteps == [.modem(.responder, 0x01), .cancel])

  }

  @Test func refusesAManualLinkTheModemControlsInAnotherGroup() async throws {

    let modem = InMemoryModem()
    let device = lamp
    await modem.setReportedGroup(0x05, of: lamp)

    await #expect(throws: LinkingError.unexpectedLink(completed(.controller, group: 0x05, address: lamp))) {

      try await linker(modem).linkManually(as: .controller, group: 0x01) {

        await modem.pressSetButton(of: device)

      }

    }

  }

  @Test func unlinksManuallyOnceTheModemIsReady() async throws {

    let modem = InMemoryModem()
    let device = lamp

    let link = try await unlinker(modem).unlinkManually(as: .controller, group: 0x00, device: lamp) {

      await modem.pressSetButton(of: device)

    }

    #expect(link.mode == .delete)
    #expect(await modem.linkingSteps == [.modem(.delete, 0x00)])

  }

  @Test func throwsAMismatchWhenADeviceLinksInsteadOfUnlinking() async throws {

    let modem = InMemoryModem()
    let device = lamp
    let expected = LinkMismatch(link: completed(.responder, group: 0x01, address: lamp), reason: .linkedInsteadOfUnlinking)

    await #expect(throws: expected) {

      // The device was put into linking mode, not unlinking mode.
      await modem.pressSetButton(of: device)
      try await unlinker(modem).unlinkManually(as: .responder, group: 0x01, device: lamp)

    }

  }

  // MARK: - The modem's links

  @Test func listsTheModemsLinksWithADevice() async throws {

    let modem = InMemoryModem()
    let controls = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: lamp)
    let responds = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp)
    let unused = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x22), group: 0x02, address: lamp)
    let others = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: other)
    await modem.setModemRecords([controls, others, responds, unused])

    let links = try await AllLinkDatabaseCache(modem: modem).modemLinks(of: lamp)

    #expect(links == [controls, responds])
    #expect(ModemLink.links(in: links + [controls]) == [
      ModemLink(modemRole: .responder, group: 0x01),
      ModemLink(modemRole: .controller, group: 0x00),
    ])

  }

  // The modem's group 0 keeps the device reachable, so its link goes last.
  @Test func takesTheDeviceOutOfTheModemsGroupZeroLast() {

    let groupZero = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: lamp)
    let groupOne = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x01, address: lamp)

    #expect(ModemLink.links(in: [groupZero, groupOne]) == [
      ModemLink(modemRole: .controller, group: 0x01),
      ModemLink(modemRole: .controller, group: 0x00),
    ])

  }

  // MARK: - Responder state

  @Test func turnsAResponderOnSoItMemorizesFullOn() async throws {

    let modem = InMemoryModem()
    let links = linker(modem)

    try await links.prepareResponder(lamp)
    try await links.linkRemotely(lamp, modemRole: .controller, modemGroup: 0x00, deviceGroup: 0x01)

    #expect(await modem.linkingSteps.first == .device(lamp, Command(command1: 0x11, command2: 0xFF), isExtended: false))
    #expect(await modem.record(of: lamp, at: 0x0FFF).data1 == 0xFF)

  }

  @Test func turnsAResponderOffWhenAsked() async throws {

    let modem = InMemoryModem()

    try await linker(modem).prepareResponder(lamp, state: .off)

    #expect(await modem.linkingSteps == [.device(lamp, Command(command1: 0x13), isExtended: false)])

  }

  @Test func turnsAResponderOffForALevelOfZero() async throws {

    let modem = InMemoryModem()

    try await linker(modem).prepareResponder(lamp, state: .on(level: 0x00))

    #expect(await modem.linkingSteps == [.device(lamp, Command(command1: 0x13), isExtended: false)])

  }

  @Test func throwsWhenAnUnlinkedResponderRejectsTheModem() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(lamp)

    await #expect(throws: ModemError.self) {

      try await linker(modem).prepareResponder(lamp)

    }

  }

  // MARK: - Remote unlinking

  func linkedBothWays(_ modem: InMemoryModem) async {

    await modem.setModemRecords([
      AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: lamp),
      AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp),
    ])

  }

  // The device's own link goes first: it enters unlinking mode, standard length, and the
  // modem joins as responder. Then the modem enters unlinking mode and the device follows.
  @Test func unlinksBothDirectionsWithoutTheSetButton() async throws {

    let modem = InMemoryModem()
    let recorder = Recorder<ModemLink>()
    await modem.setEngine(.i2cs, of: lamp)
    await linkedBothWays(modem)

    let removed = try await unlinker(modem).unlinkAllRemotely(lamp) { (link: ModemLink) async -> Void in

      await recorder.record(link)

    }

    let expected = [ModemLink(modemRole: .responder, group: 0x01), ModemLink(modemRole: .controller, group: 0x00)]

    #expect(removed == expected)
    #expect(await recorder.values == expected)
    #expect(await modem.linkingSteps == [
      .device(lamp, Command(command1: 0x0D), isExtended: false),
      .device(lamp, Command(command1: 0x0A, command2: 0x01), isExtended: false),
      .modem(.responder, 0x01),
      .device(lamp, Command(command1: 0x0D), isExtended: false),
      .modem(.delete, 0x00),
      .device(lamp, Command(command1: 0x09, command2: 0x01), isExtended: true),
    ])

  }

  @Test func sendsABatteryPoweredI2csDeviceTheExtendedUnlinkingMode() async throws {

    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: lamp)
    await modem.setModemRecords([AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp)])

    try await unlinker(modem).unlinkAllRemotely(lamp, unlinkingMode: .extendedForI2cs)

    #expect(await modem.linkingSteps.contains(.device(lamp, Command(command1: 0x0A, command2: 0x01), isExtended: true)))

  }

  @Test func unlinksNothingWhenTheModemHasNoLinks() async throws {

    let modem = InMemoryModem()

    let removed = try await unlinker(modem).unlinkAllRemotely(lamp)

    #expect(removed.isEmpty)
    #expect(await modem.linkingSteps.isEmpty)

  }

  @Test func refusesToUnlinkAnI1DeviceRemotely() async throws {

    let modem = InMemoryModem()
    await modem.setEngine(.i1, of: lamp)
    await linkedBothWays(modem)

    await #expect(throws: LinkingError.remoteLinkingUnsupported(lamp)) {

      try await unlinker(modem).unlinkAllRemotely(lamp)

    }

  }

  // A modem that removes a responder record may not report it, so its database is checked.
  @Test func countsAnUnreportedUnlinkWhoseRecordIsGone() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinkUnreported(lamp)
    await modem.setModemRecords([AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp)])

    async let removed: [ModemLink] = unlinker(modem).unlinkAllRemotely(lamp)
    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    clock.advance(by: Linker.defaultRemoteLinkingTimeout)

    #expect(try await removed == [ModemLink(modemRole: .responder, group: 0x01)])
    #expect(await modem.modemRecords.isEmpty)

  }

  @Test func throwsWhenAnUnreportedUnlinksRecordIsStillThere() async throws {

    let modem = InMemoryModem()
    let responds = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp)
    let unlinks: Unlinker = unlinker(modem)
    await modem.setSilent(lamp)
    await modem.setModemRecords([responds])

    await #expect(throws: LinkingError.linkingTimedOut) {

      async let removed: [ModemLink] = unlinks.unlinkAllRemotely(lamp)
      await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
      clock.advance(by: Linker.defaultRemoteLinkingTimeout)
      _ = try await removed

    }

    #expect(await modem.modemRecords == [responds])

  }

  // A cache that still lists a record the modem no longer has can't make an unreported
  // unlink count as removed: the modem itself is read before the unlink.
  @Test func doesntCountAnUnreportedUnlinkFromAStaleCache() async throws {

    let modem = InMemoryModem()
    let cache = AllLinkDatabaseCache(modem: modem)
    let unlinks = Unlinker(modem: modem, clock: clock, cache: cache)
    await modem.setSilent(lamp)
    await modem.setModemRecords([AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp)])

    let cached: [AllLinkRecord] = try await cache.modemLinks(of: lamp)

    #expect(cached.count == 1)

    await modem.setModemRecords([])

    await #expect(throws: LinkingError.linkingTimedOut) {

      async let removed: [ModemLink] = unlinks.unlinkAllRemotely(lamp)
      await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
      clock.advance(by: Linker.defaultRemoteLinkingTimeout)
      _ = try await removed

    }

  }

  @Test func takesTheModemAndDeviceOutOfTheirModesWhenUnlinkingIsCanceled() async throws {

    let modem = InMemoryModem()
    let unlinks: Unlinker = unlinker(modem)
    await modem.setSilent(lamp)
    await linkedBothWays(modem)

    let device: InsteonAddress = lamp
    let unlinking = Task { () async throws -> [ModemLink] in try await unlinks.unlinkAllRemotely(device) }
    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    unlinking.cancel()

    await #expect(throws: CancellationError.self) { try await unlinking.value }

    let steps = await modem.linkingSteps

    #expect(steps.suffix(2) == [.cancel, .device(lamp, Command(command1: 0x08), isExtended: false)])
    #expect(!steps.contains(.modem(.delete, 0x00)))

  }

  // The device's own link is removed, unreported; then the modem's link times out, so it
  // stays, with the device still in the modem's group 0.
  @Test func leavesTheRestWhenALinkFailsPartway() async throws {

    let modem = InMemoryModem()
    let recorder = Recorder<ModemLink>()
    let unlinks: Unlinker = unlinker(modem)
    let controls = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: lamp)
    let responds = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp)
    let timeout: Duration = Linker.defaultRemoteLinkingTimeout
    await modem.setUnlinkUnreported(lamp)
    await modem.setSilent(lamp)
    await modem.setModemRecords([controls, responds])

    await #expect(throws: LinkingError.linkingTimedOut) {

      async let removed: [ModemLink] = unlinks.unlinkAllRemotely(lamp) { (link: ModemLink) async -> Void in

        await recorder.record(link)

      }

      await clock.waitForSleeper(until: timeout)
      clock.advance(by: timeout)
      await clock.waitForSleeper(until: timeout * 2)
      clock.advance(by: timeout)
      _ = try await removed

    }

    #expect(await recorder.values == [ModemLink(modemRole: .responder, group: 0x01), ModemLink(modemRole: .controller, group: 0x00)])
    #expect(await modem.modemRecords == [controls])

  }

}
