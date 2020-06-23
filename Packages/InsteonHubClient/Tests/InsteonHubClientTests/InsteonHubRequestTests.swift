import XCTest
@testable import InsteonHubClient
import InsteonMessage
import InsteonSerialCommand

final class InsteonHubRequestTests: XCTestCase {

  var baseUrlComponents: URLComponents!

  override func setUp() {

    super.setUp()

    baseUrlComponents = URLComponents()
    baseUrlComponents.scheme = "http"
    baseUrlComponents.host = "example.com"
    baseUrlComponents.port = 25105

  }

  func testClearCommandBufferRequest() {

    let request = ClearCommandBufferRequest()

    let urlRequest = request.urlRequest(baseUrlComponents: baseUrlComponents)

    XCTAssertEqual(
      urlRequest.url?.absoluteString,
      "http://example.com:25105/1?XB=M=1"
    )

  }

  func testCommandBufferRequest() {

    let request = CommandBufferRequest()

    let urlRequest = request.urlRequest(baseUrlComponents: baseUrlComponents)

    XCTAssertEqual(
      urlRequest.url?.absoluteString,
      "http://example.com:25105/buffstatus.xml"
    )

  }
  func testExtendedCommandRequest() {

    let insteonId = InsteonIdentifier(0xAA, 0xBB, 0xCC)

    let command = ExtendedLengthDirectCommand.extendedSetGet

    let request = ExtendedCommandRequest(insteonId: insteonId, command: command)

    let urlRequest = request.urlRequest(baseUrlComponents: baseUrlComponents)

    XCTAssertEqual(
      urlRequest.url?.absoluteString,
      "http://example.com:25105/ex.xml?AABBCC=1F=2E00=28"
    )

  }

  func testExtendedCommandWaitRequest() {

    let insteonId = InsteonIdentifier(0xAA, 0xBB, 0xCC)

    let command = ExtendedLengthDirectCommand.extendedSetGet

    let request = ExtendedCommandWaitRequest(insteonId: insteonId, command: command)

    let urlRequest = request.urlRequest(baseUrlComponents: baseUrlComponents)

    XCTAssertEqual(
      urlRequest.url?.absoluteString,
      "http://example.com:25105/exw.xml?AABBCC=1F=2E00=28"
    )

  }

  func testSensorStatusRequest() {

    let request = SensorStatusRequest(page: .one)

    let urlRequest = request.urlRequest(baseUrlComponents: baseUrlComponents)

    XCTAssertEqual(
      urlRequest.url?.absoluteString,
      "http://example.com:25105/b.xml?01=01=F"
    )

  }

  func testSerialCommandRequest() {

    let serialCommand = SerialCommand(.cancelAllLinking)

    let request = SerialCommandRequest(serialCommand)

    let urlRequest = request.urlRequest(baseUrlComponents: baseUrlComponents)

    XCTAssertEqual(
      urlRequest.url?.absoluteString,
      "http://example.com:25105/0?0265=I=0"
    )

  }

  func testStandardCommandRequest() {

    let insteonId = InsteonIdentifier(0xAA, 0xBB, 0xCC)

    let command = StandardLengthDirectCommand.cancelLinkingMode

    let request = StandardCommandRequest(insteonId: insteonId, command: command)

    let urlRequest = request.urlRequest(baseUrlComponents: baseUrlComponents)

    XCTAssertEqual(
      urlRequest.url?.absoluteString,
      "http://example.com:25105/sx.xml?AABBCC=0800"
    )

  }

  func testUpdateCredentialsRequest() {

    let request = UpdateCredentialsRequest(username: "abc", password: "123")

    let urlRequest = request.urlRequest(baseUrlComponents: baseUrlComponents)

    XCTAssertEqual(
      urlRequest.url?.absoluteString,
      "http://example.com:25105/1?L=abc=1=123"
    )

  }

  static var allTests = [
    ("testClearCommandBufferRequest", testClearCommandBufferRequest),
    ("testCommandBufferRequest", testCommandBufferRequest),
    ("testExtendedCommandRequest", testExtendedCommandRequest),
    ("testExtendedCommandWaitRequest", testExtendedCommandWaitRequest),
    ("testSensorStatusRequest", testSensorStatusRequest),
    ("testSerialCommandRequest", testSerialCommandRequest),
    ("testStandardCommandRequest", testStandardCommandRequest),
    ("testUpdateCredentialsRequest", testUpdateCredentialsRequest)
  ]

}
