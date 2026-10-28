import Testing
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Remote and manual linking, on a ``TestClock`` that moves only when a test advances it.
struct RemoteLinkingTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let clock = TestClock()

  func linker(_ modem: InMemoryModem) -> Linker {

    Linker(modem: modem, clock: clock)

  }

  func unlinker(_ modem: InMemoryModem) -> Unlinker {

    Unlinker(modem: modem, clock: clock)

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

  // An i2cs device rejects a modem it isn't linked to, which is how it's told apart.
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

  @Test func refusesTheDevicesLinkInAnotherGroup() async throws {

    let modem = InMemoryModem()
    await modem.setReportedGroup(0x05, of: lamp)

    await #expect(throws: LinkingError.self) {

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

    await #expect(throws: LinkingError.self) {

      async let link = linker(modem).linkRemotely(lamp, modemRole: .controller, modemGroup: 0x04, deviceGroup: 0x00)
      await modem.pressSetButton(of: other)
      _ = try await link

    }

    #expect(await modem.linkingSteps.contains(.cancel))

  }

  @Test func refusesAnUnlinkReportedAsANewLink() async throws {

    let modem = InMemoryModem()

    await #expect(throws: LinkingError.self) {

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

}
