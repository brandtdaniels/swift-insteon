import Testing
import InsteonHubDiscovery

/// The one rule for where a Hub's credentials may go, at the edges of each private range.
struct HubAddressPolicyTests {

  @Test(arguments: [
    "10.0.0.0",
    "10.0.0.1",
    "10.255.255.255",
    "172.16.0.0",
    "172.16.0.1",
    "172.31.255.255",
    "192.168.0.0",
    "192.168.1.20",
    "192.168.255.255",
  ])
  func allowsAPrivateIPv4Address(_ host: String) {

    #expect(HubAddressPolicy.allowsCredentials(to: host))

  }

  @Test(arguments: [
    // Just outside the private ranges.
    "9.255.255.255",
    "11.0.0.0",
    "172.15.255.255",
    "172.32.0.0",
    "192.167.255.255",
    "192.169.0.0",
    // Public, as a typo makes one.
    "19.168.1.20",
    "203.0.113.7",
    // Loopback, link-local, shared and unspecified.
    "127.0.0.1",
    "169.254.0.1",
    "169.254.255.254",
    "100.64.0.1",
    "0.0.0.0",
    "255.255.255.255",
    // Host names, which a name server could answer with any address.
    "hub.local",
    "localhost",
    "hub",
    // IPv6, including loopback, link-local and unique local addresses.
    "::1",
    "[::1]",
    "fe80::1",
    "fd00::1",
    "::ffff:192.168.1.20",
    // Not an address as given.
    "",
    " 192.168.1.20",
    "192.168.1.20 ",
    "192.168.1.20:25105",
    "192.168.1.20.",
    "192.168.001.020",
    "0x0A.0.0.1",
    "167772161",
  ])
  func refusesAnyOtherHost(_ host: String) {

    #expect(!HubAddressPolicy.allowsCredentials(to: host))

  }

}
