import Testing
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol

@Suite(.timeLimit(.minutes(1)))
struct AllLinkGroupReaderTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let keypad = InsteonAddress(0x00, 0x5E, 0x5D)

  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)

  func controller(of address: InsteonAddress, group: AllLinkGroupNumber) -> AllLinkRecord {

    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: group, address: address)

  }

  func responder(of address: InsteonAddress, group: AllLinkGroupNumber, onLevel: UInt8 = 0xFF) -> AllLinkRecord {

    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: group, address: address, data1: onLevel, data2: 0x1F, data3: 0x01)

  }

  func read(_ modem: InMemoryModem, devices: [InsteonAddress]) async throws -> AllLinkGroupReading {

    try await AllLinkGroupReader(cache: AllLinkDatabaseCache(modem: modem)).read(devices: devices)

  }

  @Test func readsTheModemsGroupWithItsRespondersData() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords([controller(of: lamp, group: 0x05)])
    await modem.setDatabase([0x0FFF: responder(of: modemAddress, group: 0x05, onLevel: 0x80)], of: lamp)

    let reading = try await read(modem, devices: [lamp])

    #expect(reading.groups == [
      AllLinkGroup(controller: .modem, number: 0x05, responders: [.init(.device(lamp), data1: 0x80, data2: 0x1F, data3: 0x01)]),
    ])
    #expect(reading.halfLinks.isEmpty)

  }

  @Test func readsAGroupBetweenTwoDevicesAndTheModemAsResponder() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords([responder(of: keypad, group: 0x03)])
    await modem.setDatabase([
      0x0FFF: controller(of: lamp, group: 0x03),
      0x0FF7: controller(of: modemAddress, group: 0x03),
    ], of: keypad)
    await modem.setDatabase([0x0FFF: responder(of: keypad, group: 0x03)], of: lamp)

    let reading = try await read(modem, devices: [lamp, keypad])

    #expect(reading.groups == [
      AllLinkGroup(controller: .device(keypad), number: 0x03, responders: [
        .init(.device(lamp), data1: 0xFF, data2: 0x1F, data3: 0x01),
        .init(.modem, data1: 0xFF, data2: 0x1F, data3: 0x01),
      ]),
    ])

  }

  // A keypad responds to the modem's group 1 with two of its buttons.
  @Test func keepsEachRecordAResponderHasForAGroup() async throws {

    let modem = InMemoryModem()
    var buttonA = responder(of: modemAddress, group: 0x01)
    var buttonB = responder(of: modemAddress, group: 0x01)
    buttonA.data3 = 0x01
    buttonB.data3 = 0x02
    await modem.setModemRecords([controller(of: keypad, group: 0x01)])
    await modem.setDatabase([0x0FFF: buttonA, 0x0FF7: buttonB], of: keypad)

    let reading = try await read(modem, devices: [keypad])

    #expect(reading.groups.first?.responders.map(\.data3) == [0x01, 0x02])

  }

  // The lamp was reset, so the keypad still records a link the lamp forgot.
  @Test func reportsALinkMissingItsOtherHalf() async throws {

    let modem = InMemoryModem()
    let record = controller(of: lamp, group: 0x01)
    await modem.setDatabase([0x0FFF: record], of: keypad)

    let reading = try await read(modem, devices: [lamp, keypad])

    #expect(reading.groups.isEmpty)
    #expect(reading.halfLinks == [.init(endpoint: .device(keypad), record: record)])

  }

  @Test func listsDevicesItCouldntReadOrWasntGiven() async throws {

    let modem = InMemoryModem()
    let sensor = InsteonAddress(0x2A, 0x3B, 0x4C)
    await modem.setModemRecords([controller(of: lamp, group: 0x01), responder(of: sensor, group: 0x01)])
    await modem.setUnlinked(lamp)

    let reading = try await read(modem, devices: [lamp])

    #expect(reading.unreadable == [lamp])
    #expect(reading.unlisted == [sensor])
    #expect(reading.groups.isEmpty)
    #expect(reading.halfLinks.isEmpty)

  }

}
