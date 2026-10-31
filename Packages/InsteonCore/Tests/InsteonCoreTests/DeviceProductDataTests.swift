import Testing
@testable import InsteonCore
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// A modem whose device answers Product Data Request one way: by rejecting it, by
/// acknowledging it and sending nothing more, or by acknowledging it and sending its Product
/// Data Response.
actor ProductDataModem: LinkingModem {

  /// How the device answers.
  enum Answer: Sendable {

    case rejects

    case acknowledgesOnly

    case responds(UserData)

  }

  let answer: Answer

  /// The modem's address.
  static let address = InsteonAddress(0x11, 0x22, 0x33)

  private var subscribers: [AsyncStream<ModemReply>.Continuation] = []

  init(answer: Answer) {

    self.answer = answer

  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    let device: InsteonAddress = message.destination

    if case .rejects = answer {

      throw ModemError.deviceRejected(device, NAKReason(rawValue: 0xFF))

    }

    if case let .responds(data) = answer {

      let response = ReceivedMessage(
        sender: device,
        destination: ProductDataModem.address,
        flags: MessageFlags(messageType: .direct),
        command: Command(command1: 0x03, command2: 0x00),
        userData: data
      )

      for subscriber in subscribers {

        subscriber.yield(.messageReceived(response))

      }

    }

    return ReceivedMessage(
      sender: device,
      destination: ProductDataModem.address,
      flags: MessageFlags(messageType: .directAcknowledgment),
      command: message.command
    )

  }

  func replies() -> AsyncStream<ModemReply> {

    let (stream, continuation) = AsyncStream<ModemReply>.makeStream()

    subscribers.append(continuation)

    return stream

  }

  func send(_ command: SerialCommand) async throws {}

  func modemInfo() async throws -> ModemInfo {

    ModemInfo(address: ProductDataModem.address, category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    throw ModemError.deviceTimedOut(message.destination)

  }

  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    []

  }

  func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    throw ModemError.deviceTimedOut(device)

  }

  func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    []

  }

  func allLinkRecords() async throws -> [AllLinkRecord] {

    []

  }

}

/// Asking a device for its product data.
struct DeviceProductDataTests {

  @Test(.timeLimit(.minutes(1))) func givesNoProductDataForADeviceThatRejectsTheRequest() async throws {

    let clock = TestClock()
    let network = DeviceNetwork(modem: ProductDataModem(answer: .rejects), catalog: nil, clock: clock)

    #expect(try await network.productData(of: Example.plug) == nil)

  }

  @Test(.timeLimit(.minutes(1))) func givesNoProductDataWhenTheDeviceSendsNoResponseInTime() async throws {

    let clock = TestClock()
    let network = DeviceNetwork(modem: ProductDataModem(answer: .acknowledgesOnly), catalog: nil, clock: clock)
    let request = Task { () async throws -> DeviceProductData? in try await network.productData(of: Example.plug) }

    // The wait for the response starts once the request is acknowledged, at the clock's start.
    await clock.waitForSleeper(until: Modem.defaultExtendedRequestTimeout)
    clock.advance(by: Modem.defaultExtendedRequestTimeout)

    #expect(try await request.value == nil)

  }

  @Test(.timeLimit(.minutes(1))) func readsTheProductDataResponse() async throws {

    let data = try UserData([0x00, 0x00, 0x10, 0x2A, 0x02, 0x7A, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    let network = DeviceNetwork(modem: ProductDataModem(answer: .responds(data)), catalog: nil, clock: TestClock())

    let result: DeviceProductData? = try await network.productData(of: Example.plug)
    let productData = try #require(result)

    #expect(productData == DeviceProductData(category: 0x02, subcategory: 0x7A, productKey: ProductKey(0x00, 0x10, 0x2A)))

  }

}
