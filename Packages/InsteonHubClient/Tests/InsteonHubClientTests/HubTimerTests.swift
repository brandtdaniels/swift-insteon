import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonNetworking
import InsteonProtocol
import InsteonTestSupport

struct HubTimerTests {

  let endpoint = HubEndpoint(host: "hub.local")

  let plug = InsteonAddress(0x1A, 0xDC, 0x49)

  /// A page whose first slot is the plug's group 1, used, active and on, and whose second is
  /// empty.
  static let page = #"<response><S D="1A.DC.49.01"/><S D="13"/><S D="00.00.00.00"/><S D="00"/></response>"#

  func makeHub(answering body: String = page) -> (Hub, StubHTTPClient) {

    let stub = StubHTTPClient(response: HTTPResponse(statusCode: 200, body: Data(body.utf8)))

    return (Hub(endpoint: endpoint, httpClient: stub), stub)

  }

  @Test func numbersSlotsByPageAndIndex() throws {

    let slot = try #require(HubSlot(page: 2, index: 3))

    #expect(slot.rawValue == 19)
    #expect(slot.page == 2)
    #expect(slot.index == 3)
    #expect(HubSlot(rawValue: 256)?.page == 16)
    #expect(HubSlot(rawValue: 0) == nil)
    #expect(HubSlot(page: 17, index: 1) == nil)
    #expect(HubSlot.unlockCode == HubSlot(page: 15, index: 16))

  }

  @Test func readsAPageOfSlots() async throws {

    let (hub, stub) = makeHub()

    let statuses = try await hub.slotStatuses(page: 1)

    #expect(await stub.requests.first?.url?.absoluteString == "http://hub.local:25105/b.xml?01=01=F")
    #expect(statuses == [
      HubSlotStatus(slot: HubSlot(rawValue: 1)!, device: plug, group: 0x01, flags: [.used, .active, .on]),
      HubSlotStatus(slot: HubSlot(rawValue: 2)!, device: InsteonAddress(0, 0, 0), group: 0x00, flags: []),
    ])

  }

  // The devices and the flags pair up in order, whether or not they alternate.
  @Test func readsAPageListingDevicesThenFlagsInEitherQuotes() async throws {

    let (hub, _) = makeHub(answering: #"<S D='1A.DC.49.01'/><S D="00.00.00.00"/><S D="13"/><S D='00'/>"#)

    let statuses = try await hub.slotStatuses(page: 3)

    #expect(statuses.map(\.slot.rawValue) == [33, 34])
    #expect(statuses.map(\.device) == [plug, InsteonAddress(0, 0, 0)])
    #expect(statuses.map(\.flags) == [[.used, .active, .on], []])

  }

  @Test(arguments: [#"<S D="1A.DC.49"/><S D="13"/>"#, #"<S D="1A.DC.49.01"/>"#, #"<S D="1A.DC.49.01"/><S D="1G"/>"#])
  func refusesAMalformedPage(_ body: String) async {

    await #expect(throws: HubError.malformedSlotPage) {

      try await makeHub(answering: body).0.slotStatuses(page: 1)

    }

  }

  // An example: the plug on Monday through Sunday at 10:55, never off, keeping the
  // slot's device and group.
  @Test func writesATimerAsInsteonsAppDoes() async throws {

    let (hub, stub) = makeHub(answering: #"<S D="1A.DC.49.01"/><S D="00"/>"#)
    let timer = HubTimer(name: try #require(HubSlotName(rawValue: "PlugInModule")), on: .clock(try #require(HubClockTime(hour: 10, minute: 55))), off: nil, days: .everyDay)

    try await hub.setTimer(timer, for: try #require(HubSlot(rawValue: 1)))

    #expect(await stub.requests.map { $0.url?.absoluteString } == [
      "http://hub.local:25105/b.xml?01=01=F",
      "http://hub.local:25105/2?S1=PlugInModule=2=t=10:55=ff=00:00=ff=t=t=t=t=t=t=t=f=f=f=t=1ADC4901=t=f22",
    ])

  }

  @Test func writesSunTimesMidnightAndTheSlotsFlags() async throws {

    let (hub, stub) = makeHub()
    let days = HubWeekdays([.saturday, .sunday])
    let timer = HubTimer(name: try #require(HubSlotName(rawValue: "Porch")), on: .sunset, off: .clock(try #require(HubClockTime(hour: 0, minute: 0))), days: days)

    try await hub.setTimer(timer, for: try #require(HubSlot(rawValue: 1)))

    #expect(await stub.requests.last?.url?.absoluteString == "http://hub.local:25105/2?S1=Porch=2=t=00:00=ff=24:00=ff=f=f=f=f=f=t=t=t=t=f=t=1ADC4901=t=f12")

  }

  @Test func writesTheAlertFieldForAUsedAlertingSlotThatsOn() async throws {

    let (hub, stub) = makeHub(answering: #"<S D="1A.DC.49.01"/><S D="32"/>"#)
    let timer = HubTimer(name: try #require(HubSlotName(rawValue: "Door")), on: .sunrise, off: nil, days: [])

    try await hub.setTimer(timer, for: try #require(HubSlot(rawValue: 1)))

    #expect(await stub.requests.last?.url?.absoluteString == "http://hub.local:25105/2?S1=Door=2=t=00:00=ff=00:00=ff=f=f=f=f=f=f=f=f=t=f=t=1ADC4901=t=t32")

  }

  @Test func writesAnEmptySlotsDeviceAsZeros() async throws {

    let (hub, stub) = makeHub()
    let timer = HubTimer(name: try #require(HubSlotName(rawValue: "Lamp")), on: nil, off: nil, days: [])

    try await hub.setTimer(timer, for: try #require(HubSlot(rawValue: 2)))

    #expect(await stub.requests.last?.url?.absoluteString == "http://hub.local:25105/2?S2=Lamp=2=t=00:00=ff=00:00=ff=f=f=f=f=f=f=f=f=f=f=t=00000000=t=f22")

  }

  @Test(arguments: [240, 241, 256])
  func refusesSlotsPast239(_ number: Int) async throws {

    let (hub, stub) = makeHub()
    let slot = try #require(HubSlot(rawValue: number))
    let timer = HubTimer(name: try #require(HubSlotName(rawValue: "Lamp")), on: nil, off: nil, days: [])

    #expect(!slot.holdsTimers)

    await #expect(throws: HubError.reservedSlot(slot)) {

      try await hub.setTimer(timer, for: slot)

    }

    await #expect(throws: HubError.reservedSlot(slot)) {

      try await hub.setCommands(nil, for: slot)

    }

    #expect(await stub.requests.isEmpty)
    #expect(HubSlot(rawValue: 239)?.holdsTimers == true)

  }

  @Test func writesASlotsCommandsAsSerialCommandsInHex() async throws {

    let (hub, stub) = makeHub()
    let slot = try #require(HubSlot(rawValue: 11))
    let commands = HubSlotCommands(
      on: .sendStandardMessage(StandardMessage(to: plug, command: StandardDirectCommand.on(level: 0xFF))),
      off: .sendAllLinkCommand(group: 0x0B, command: Command(command1: 0x13, command2: 0x0B))
    )

    try await hub.setCommands(commands, for: slot)
    try await hub.setCommands(nil, for: slot)

    #expect(await stub.requests.map { $0.url?.absoluteString } == [
      "http://hub.local:25105/2?C11=02621ADC490F11FF=2tt02610B130B",
      "http://hub.local:25105/2?C11=-=2ff-",
    ])

  }

  @Test func setsTheClockAndDayOfTheWeek() async throws {

    let (hub, stub) = makeHub()

    try await hub.setClock(to: try #require(HubClockTime(hour: 23, minute: 22)), on: .thursday)
    try await hub.setClock(to: try #require(HubClockTime(hour: 0, minute: 5)), on: .monday)

    #expect(await stub.requests.map { $0.url?.absoluteString } == [
      "http://hub.local:25105/hnetwork.htm?TD=23:22=1=falsefalse",
      "http://hub.local:25105/1?D=1=1=f=f=f=t=f=f=f=",
      "http://hub.local:25105/hnetwork.htm?TD=00:05=1=falsefalse",
      "http://hub.local:25105/1?D=1=1=t=f=f=f=f=f=f=",
    ])

  }

  @Test func acceptsOnlyLettersAndDigitsInNames() {

    #expect(HubSlotName(rawValue: "Porch2") != nil)
    #expect(HubSlotName(rawValue: "Porch Light") == nil)
    #expect(HubSlotName(rawValue: "a=b") == nil)
    #expect(HubSlotName(rawValue: "Café") == nil)
    #expect(HubSlotName(rawValue: "") == nil)

  }

  @Test func refusesTimesOutOfRange() {

    #expect(HubClockTime(hour: 24, minute: 0) == nil)
    #expect(HubClockTime(hour: 0, minute: 60) == nil)
    #expect(HubClockTime(hour: -1, minute: 0) == nil)

  }

}
