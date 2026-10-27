import Foundation
import Testing
import InsteonNetworking

struct HTTPResponseTests {

  @Test(arguments: [(200, true), (204, true), (299, true), (199, false), (301, false), (401, false), (500, false)])
  func successMeans2xx(_ statusCode: Int, _ isSuccess: Bool) {

    #expect(HTTPResponse(statusCode: statusCode).isSuccess == isSuccess)

  }

  @Test func looksUpHeadersCaseInsensitively() {

    let response = HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/xml"])

    #expect(response.value(forHeader: "content-type") == "text/xml")
    #expect(response.value(forHeader: "Accept") == nil)

  }

}
