import Testing
import InsteonCLISupport

/// What `--hub` and `INSTEON_HUB` accept as a Hub's name, and what counts as an address.
struct HubNameTests {

  @Test(arguments: ["basement", "hub2", "a", "garage_hub", "hub-pro", "0", "123", "a-b_c-9", String(repeating: "a", count: 32)])
  func acceptsLettersDigitsHyphenAndUnderscore(name: String) {

    #expect(HubName.isValid(name))

  }

  @Test(arguments: [
    "", String(repeating: "a", count: 33), "Basement", "base ment", "base.ment", ".", "..", "../etc/passwd", "a/b", "/etc/passwd",
    "a\\b", "~", "hub.env", "caf\u{E9}", "hub\u{0}", "a\nb", "hub:80", "a b"
  ])
  func rejectsAnythingElse(name: String) {

    #expect(!HubName.isValid(name))

  }

  @Test(arguments: ["192.168.1.20", "192.168.1.20:25105", "10.0.0.1", "8.8.8.8", "192.168.1.20:", "192.168.1.20:abc"])
  func recognizesAnIPv4AddressWithAnOptionalPort(text: String) {

    #expect(HubName.isAddress(text))

  }

  @Test(arguments: ["basement", "192.168.1", "192.168.1.20.5", "hub.local", "::1", "fe80::1", "a.b.c.d", "192.168.1.x", "1234", "[::1]:80"])
  func doesNotTakeAnythingElseForAnAddress(text: String) {

    #expect(!HubName.isAddress(text))

  }

}
