import Testing
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Remote and manual linking, on a ``TestClock`` that moves only when a test advances it.
@Suite(.timeLimit(.minutes(1)))
struct RemoteLinkingTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let clock = TestClock()

  func linker(_ modem: InMemoryModem) -> Linker {

    Linker(modem: modem, clock: clock)

  }

  func unlinker(_ modem: InMemoryModem) -> Unlinker {

    Unlinker(modem: modem, clock: clock)

  }

  /// A link the in-memory modem reports, which carries no category, subcategory or firmware.
  func reported(_ address: InsteonAddress, linkCode: UInt8, group: AllLinkGroupNumber) -> AllLinkingCompleted {

    AllLinkingCompleted(linkCode: linkCode, group: group, address: address, category: nil, subcategory: nil, firmwareVersion: nil)

  }

  // Insteon's trace: the modem enters linking mode as controller of group 4, then the device
  // is sent Enter Linking Mode, and the modem reports the link.
  @Test func linksAnI2DeviceAsTheModemsResponder() async throws {

    let modem = InMemoryModem()

    let link = try await linker(modem).linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00)

    #expect(link.address == lamp)
    #expect(link.mode == .controller)
    #expect(await modem.linkingSteps == [
      .device(lamp, Command(command1: 0x0D), isExtended: false),
      .modem(.controller, 0x04),
      .device(lamp, Command(command1: 0x09, command2: 0x00), isExtended: false),
    ])

  }

  @Test func sendsAnI2csDeviceTheExtendedCommand() async throws {

    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: lamp)

    try await linker(modem).linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00)

    #expect(await modem.linkingSteps.last == .device(lamp, Command(command1: 0x09, command2: 0x00), isExtended: true))

  }

  // An i2CS device rejects a modem it isn't linked to, which is how it's told apart.
  @Test func treatsADeviceThatRejectsAnUnlinkedModemAsI2cs() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(lamp)

    try await linker(modem).linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00)

    #expect(await modem.linkingSteps.last == .device(lamp, Command(command1: 0x09, command2: 0x00), isExtended: true))

  }

  @Test func refusesToLinkAnI1DeviceRemotely() async throws {

    let modem = InMemoryModem()
    await modem.setEngine(.i1, of: lamp)

    await #expect(throws: LinkingError.remoteLinkingUnsupported(lamp)) {

      try await linker(modem).linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00)

    }

    // The modem never entered linking mode.
    #expect(await modem.linkingSteps == [.device(lamp, Command(command1: 0x0D), isExtended: false)])

  }

  @Test func putsTheDeviceInLinkingModeFirstWhenTheModemResponds() async throws {

    let modem = InMemoryModem()

    let link = try await linker(modem).linkRemotely(lamp, modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)

    #expect(link.mode == .responder)
    #expect(await modem.linkingSteps.suffix(2) == [
      .device(lamp, Command(command1: 0x09, command2: 0x01), isExtended: false),
      .modem(.responder, 0x01),
    ])

  }

  @Test func takesTheModemAndDeviceOutOfLinkingModeWhenNoLinkArrives() async throws {

    let modem = InMemoryModem()
    await modem.setSilent(lamp)

    await #expect(throws: LinkingError.linkingTimedOut) {

      async let link = linker(modem).linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00)
      await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
      clock.advance(by: Linker.defaultRemoteLinkingTimeout)
      _ = try await link

    }

    #expect(await modem.linkingSteps.suffix(2) == [.cancel, .device(lamp, Command(command1: 0x08), isExtended: false)])

  }

  @Test func takesTheModemAndDeviceOutOfLinkingModeBeforeACanceledLinkReturns() async throws {

    let modem = InMemoryModem()
    let links = linker(modem)
    await modem.setSilent(lamp)

    let link = Task { try await links.linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00) }
    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    link.cancel()

    await #expect(throws: CancellationError.self) { try await link.value }
    #expect(await modem.linkingSteps.suffix(2) == [.cancel, .device(lamp, Command(command1: 0x08), isExtended: false)])

  }

  // The wait times out, and the task is canceled while Cancel ALL-Linking waits its turn: the
  // modem and the device still leave linking mode.
  @Test(.timeLimit(.minutes(1)))
  func takesTheModemAndDeviceOutOfLinkingModeWhenCanceledDuringCleanup() async throws {

    let modem = InMemoryModem()
    let links = linker(modem)
    await modem.setSilent(lamp)

    let (reached, reachedSignal) = AsyncStream<Void>.makeStream()
    let (release, releaseSignal) = AsyncStream<Void>.makeStream()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      guard case .send(.cancelAllLinking) = operation else {

        return

      }

      reachedSignal.yield()

      // Ends at once if this runs in the canceled task, so the test can't hang.
      for await _ in release {

        break

      }

    }

    let link = Task { try await links.linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00) }
    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    clock.advance(by: Linker.defaultRemoteLinkingTimeout)

    var reachedCleanup = reached.makeAsyncIterator()
    _ = await reachedCleanup.next()

    link.cancel()
    releaseSignal.yield()

    await #expect(throws: LinkingError.linkingTimedOut) { try await link.value }
    #expect(await modem.linkingSteps.suffix(2) == [.cancel, .device(lamp, Command(command1: 0x08), isExtended: false)])

  }

  @Test func refusesTheDevicesLinkInAnotherGroup() async throws {

    let modem = InMemoryModem()
    await modem.setReportedGroup(0x05, of: lamp)

    await #expect(throws: LinkingError.unexpectedLink(reported(lamp, linkCode: 0x01, group: 0x05))) {

      try await linker(modem).linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00)

    }

    #expect(await modem.linkingSteps.contains(.cancel))

  }

  @Test func linksWhicheverDeviceHasItsSetButtonPressed() async throws {

    let modem = InMemoryModem()

    async let link = linker(modem).linkManually(modemRole: .controller, group: 0x01)
    await modem.pressSetButton(of: lamp)
    let linked = try await link

    #expect(linked.address == lamp)
    #expect(await modem.linkingSteps == [.modem(.controller, 0x01)])

  }

  @Test func unlinksADeviceTheModemControls() async throws {

    let modem = InMemoryModem()

    try await unlinker(modem).unlinkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00)

    #expect(await modem.linkingSteps.suffix(2) == [
      .modem(.delete, 0x04),
      .device(lamp, Command(command1: 0x09, command2: 0x00), isExtended: false),
    ])

  }

  @Test func unlinksADeviceThatControlsTheModem() async throws {

    let modem = InMemoryModem()

    try await unlinker(modem).unlinkRemotely(lamp, modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)

    #expect(await modem.linkingSteps.suffix(2) == [
      .device(lamp, Command(command1: 0x0A, command2: 0x01), isExtended: false),
      .modem(.responder, 0x01),
    ])

  }

  @Test func reportsAnotherDeviceLinkingWhileTheModemWaits() async throws {

    let modem = InMemoryModem()
    let other = InsteonAddress(0x44, 0x55, 0x66)
    await modem.setSilent(lamp)

    await #expect(throws: LinkingError.unexpectedLink(reported(other, linkCode: 0x01, group: 0x04))) {

      async let link = linker(modem).linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00)
      await modem.pressSetButton(of: other)
      _ = try await link

    }

    #expect(await modem.linkingSteps.contains(.cancel))

  }

  @Test func refusesAnUnlinkReportedAsANewLink() async throws {

    let modem = InMemoryModem()

    // The modem, as the responder, reports a new link: link code 0x00 rather than 0xFF.
    await #expect(throws: LinkingError.unexpectedLink(reported(lamp, linkCode: 0x00, group: 0x01))) {

      async let unlink = unlinker(modem).unlinkManually(modemRole: .responder, group: 0x01)
      // The device links instead of unlinking.
      await modem.pressSetButton(of: lamp)
      _ = try await unlink

    }

  }

  // A modem that removes a responder record may not report it, so its database is checked.
  @Test func checksTheModemsDatabaseWhenAResponderUnlinkIsntReported() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinkUnreported(lamp)
    await modem.setModemRecords([AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp)])

    async let unlink: Void = unlinker(modem).unlinkRemotely(lamp, modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)
    await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
    clock.advance(by: Linker.defaultRemoteLinkingTimeout)

    try await unlink
    #expect(await modem.modemRecords.isEmpty)

  }

  // Without a record to begin with, the database can't show that anything was unlinked.
  @Test func failsAnUnreportedResponderUnlinkWhenTheModemHadNoRecord() async throws {

    let modem = InMemoryModem()
    await modem.setSilent(lamp)

    await #expect(throws: LinkingError.linkingTimedOut) {

      async let unlink: Void = unlinker(modem).unlinkRemotely(lamp, modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)
      await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
      clock.advance(by: Linker.defaultRemoteLinkingTimeout)
      try await unlink

    }

  }

  @Test func failsAResponderUnlinkWhenTheModemStillHasTheRecord() async throws {

    let modem = InMemoryModem()
    await modem.setSilent(lamp)
    await modem.setModemRecords([AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: lamp)])

    await #expect(throws: LinkingError.linkingTimedOut) {

      async let unlink: Void = unlinker(modem).unlinkRemotely(lamp, modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)
      await clock.waitForSleeper(until: Linker.defaultRemoteLinkingTimeout)
      clock.advance(by: Linker.defaultRemoteLinkingTimeout)
      try await unlink

    }

  }

  // MARK: - Pinned before the manual linking moves out of the command

  @Test func takesTheModemOutOfLinkingModeWhenNoDeviceLinksManually() async throws {

    let modem = InMemoryModem()

    await #expect(throws: LinkingError.linkingTimedOut) {

      async let link = linker(modem).linkManually(modemRole: .controller, group: 0x01)
      await clock.waitForSleeper(until: Linker.defaultManualLinkingTimeout)
      clock.advance(by: Linker.defaultManualLinkingTimeout)
      _ = try await link

    }

    #expect(await modem.linkingSteps == [.modem(.controller, 0x01), .cancel])

  }

  @Test func refusesAManualLinkInAnotherGroupWhenTheModemControls() async throws {

    let modem = InMemoryModem()
    await modem.setReportedGroup(0x05, of: lamp)

    await #expect(throws: LinkingError.unexpectedLink(reported(lamp, linkCode: 0x01, group: 0x05))) {

      async let link = linker(modem).linkManually(modemRole: .controller, group: 0x01)
      await modem.pressSetButton(of: lamp)
      _ = try await link

    }

  }

  // The modem reports the controller's group when it responds, so it isn't checked.
  @Test func acceptsAManualLinkInTheDevicesGroupWhenTheModemResponds() async throws {

    let modem = InMemoryModem()
    await modem.setReportedGroup(0x05, of: lamp)

    async let link = linker(modem).linkManually(modemRole: .responder, group: 0x01)
    await modem.pressSetButton(of: lamp)
    let linked = try await link

    #expect(linked.group == 0x05)
    #expect(linked.mode == .responder)

  }

  @Test func unlinksWhicheverDeviceHasItsSetButtonPressed() async throws {

    let modem = InMemoryModem()

    async let unlink = unlinker(modem).unlinkManually(modemRole: .controller, group: 0x00)
    await modem.pressSetButton(of: lamp)
    let unlinked = try await unlink

    #expect(unlinked.address == lamp)
    #expect(unlinked.mode == .delete)
    #expect(await modem.linkingSteps == [.modem(.delete, 0x00)])

  }

}
