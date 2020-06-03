import XCTest
@testable import InsteonHubClient
import RequestClient
import InsteonSerialCommand

final class InsteonHubClientTests: XCTestCase {
  
  var hubClient: InsteonHubClientProtocol!
  
  var mockRequestClient: MockRequestClient!
  
  override func setUp() {
    
    mockRequestClient = MockRequestClient()
    
    let credentials = LoginCredentials(
      user: "",
      password: ""
    )
    let address = SocketAddress(
      host: "example.com",
      port: 80
    )
    
    hubClient = InsteonHubClient(
      credentials: credentials,
      address: address,
      requestClient: mockRequestClient
    )
    
  }
  
  func testRequestClientInteraction() {
    
    let serialCommand = SerialCommand(.cancelAllLinking)
    
    hubClient.send(serialCommand) { result in
      
      XCTAssertEqual(
        self.mockRequestClient.sendCallCount,
        1
      )
      
    }
    
  }
  
  static var allTests = [
    ("testRequestClientInteraction", testRequestClientInteraction),
  ]
  
}

class MockRequestClient: RequestClientProtocol {
  
  var sendCallCount = 0
  
  func send(_ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
    
    sendCallCount += 1
    
  }
  
}
