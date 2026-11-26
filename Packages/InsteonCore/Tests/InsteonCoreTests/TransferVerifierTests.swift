import Foundation
import InsteonProtocol
import Testing
@testable import InsteonCore

/// Which of a backup's devices answer through the connected modem.
@Suite(.timeLimit(.minutes(1)))
struct TransferVerifierTests {

  typealias Example = BackupExample

  struct NoAnswer: Error, CustomStringConvertible {
    var description: String { "no answer" }
  }

  static func backup() -> HomeBackup {

    Example.backup([
      Example.device(Example.lamp, name: "Porch"),
      Example.device(Example.plug),
      Example.unreadable(Example.sensor)
    ])

  }

  @Test func asksEveryDeviceInTheBackupOnceInOrderAndSaysWhichAnswered() async throws {

    let asked = Asked()
    let result = try await TransferVerifier.verify(Self.backup()) { address in
      await asked.add(address)
      if address == Example.plug { throw NoAnswer() }
    }

    let order: [InsteonAddress] = Self.backup().devices.map(\.address)
    let answered: Set<InsteonAddress> = Set(result.checks.filter(\.answered).map(\.address))

    #expect(await asked.addresses == order)
    #expect(result.checks.map(\.address) == order)
    #expect(answered == [Example.lamp, Example.sensor])
    #expect(result.checks.first { $0.address == Example.plug }?.problem == "no answer")
    #expect(!result.isComplete)

  }

  @Test func carriesTheDevicesNameAndIsCompleteWhenEveryDeviceAnswers() async throws {

    let result = try await TransferVerifier.verify(Self.backup()) { _ in }

    #expect(result.isComplete)
    #expect(result.checks.first { $0.address == Example.lamp }?.name == "Porch")
    #expect(result.checks.allSatisfy { $0.problem == nil })

  }

  @Test func asksOneDeviceAtATime() async throws {

    let gate = Concurrency()

    _ = try await TransferVerifier.verify(Self.backup()) { _ in
      await gate.enter()
      await Task.yield()
      await gate.leave()
    }

    #expect(await gate.most == 1)

  }

  @Test func passesCancellationOnInsteadOfCallingItAnAnswer() async throws {

    await #expect(throws: CancellationError.self) {
      try await TransferVerifier.verify(Self.backup()) { _ in throw CancellationError() }
    }

  }

  @Test func hasNothingToCheckInABackupWithNoDevices() async throws {

    let result = try await TransferVerifier.verify(Example.backup([])) { _ in Issue.record("asked") }

    #expect(result.checks.isEmpty)
    #expect(result.isComplete)

  }

}

private actor Asked {
  private(set) var addresses: [InsteonAddress] = []
  func add(_ address: InsteonAddress) { addresses.append(address) }
}

private actor Concurrency {
  private var current = 0
  private(set) var most = 0
  func enter() { current += 1; most = max(most, current) }
  func leave() { current -= 1 }
}
