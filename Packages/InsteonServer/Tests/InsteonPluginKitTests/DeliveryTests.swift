import Foundation
import Testing
@testable import InsteonPluginKit

/// What reaches a delivery channel, and the reference channel that writes lines.
@Suite(.timeLimit(.minutes(1)))
struct DeliveryTests {
  private func directory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-plugin-kit-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  @Test func aPayloadIsTheTimeAndTheNameByDefault() {
    #expect(DeliveryPayload(ruleName: "Basement leak", firedAt: "2027-01-15T08:00:00Z").line == "2027-01-15T08:00:00Z\tBasement leak")
  }

  @Test func detailAddsTheDeviceAndTheEvent() {
    #expect(DeliveryPayload(ruleName: "Leak", firedAt: "t", address: "1A.2B.3C", event: "wet").line == "t\tLeak\t1A.2B.3C\twet")
  }

  @Test func aControlCharacterInAFieldCannotStartAnotherLine() {
    #expect(DeliveryPayload(ruleName: "a\nb\tc", firedAt: "t").line == "t\ta b c")
  }

  @Test func theFileDelivererAppendsOneLinePerPayloadAndKeepsTheFilePrivate() async throws {
    let url = try directory().appendingPathComponent("deliveries.log")
    let deliverer = LineDeliverer.appending(to: url)
    try await deliverer.deliver(DeliveryPayload(ruleName: "One", firedAt: "t1"))
    try await deliverer.deliver(DeliveryPayload(ruleName: "Two", firedAt: "t2"))
    #expect(try String(contentsOf: url, encoding: .utf8) == "t1\tOne\nt2\tTwo\n")
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
  }

  @Test func aFileThatCannotBeWrittenIsAFailedDelivery() async throws {
    let url = try directory().appendingPathComponent("missing").appendingPathComponent("deliveries.log")
    await #expect(throws: (any Error).self) { try await LineDeliverer.appending(to: url).deliver(DeliveryPayload(ruleName: "One", firedAt: "t")) }
  }
}
