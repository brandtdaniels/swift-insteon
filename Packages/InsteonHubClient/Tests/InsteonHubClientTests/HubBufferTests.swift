import Testing
import InsteonHubClient

struct HubBufferTests {

  @Test func parsesContentsAndEndPosition() throws {

    let buffer = try HubBuffer(response: "<response><BS>0102030406</BS></response>")

    #expect(buffer.bytes == [0x01, 0x02, 0x03, 0x04])
    #expect(buffer.endIndex == 3)

  }

  @Test func ignoresWhitespaceAndSurroundingText() throws {

    let buffer = try HubBuffer(response: "<?xml version=\"1.0\"?>\n<response><BS>\n0A0B02\n</BS></response>\n")

    #expect(buffer.bytes == [0x0A, 0x0B])
    #expect(buffer.endIndex == 1)

  }

  @Test(arguments: [
    "",
    "<response></response>",
    "<response><BS></BS></response>",
    "<response><BS>010</BS></response>",
    "<response><BS>01GG02</BS></response>",
    "<response><BS>0102FF</BS></response>"
  ])
  func rejectsMalformedResponses(_ response: String) {

    #expect(throws: HubError.malformedBuffer) {

      try HubBuffer(response: response)

    }

  }

}
