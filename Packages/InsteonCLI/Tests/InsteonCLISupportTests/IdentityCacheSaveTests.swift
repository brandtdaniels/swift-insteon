import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

struct IdentityCacheSaveTests {

  let path = "/home/example/.cache/insteon/identities.json"
  let device = InsteonAddress(0x11, 0x22, 0x33)
  let hub = HubLocation(host: "192.168.0.20", port: 25105)
  let otherHub = HubLocation(host: "192.168.0.21", port: 25105)

  /// The cache file as a test sets it: what it holds or why it can't be read, and why it
  /// can't be written.
  final class File: IdentityCacheFile {

    var contents: Result<NetworkSnapshot, DeviceRegistryStoreError>
    var writeFailure: DeviceRegistryStoreError?
    var reads: Int = 0
    var written: [NetworkSnapshot] = []

    init(_ contents: Result<NetworkSnapshot, DeviceRegistryStoreError>, writeFailure: DeviceRegistryStoreError? = nil) {

      self.contents = contents
      self.writeFailure = writeFailure

    }

    func loadNetwork() throws -> NetworkSnapshot {

      reads += 1

      return try contents.get()

    }

    func saveNetwork(_ snapshot: NetworkSnapshot) throws {

      if let writeFailure {

        throw writeFailure

      }

      written.append(snapshot)

    }

  }

  private var identified: NetworkSnapshot {

    NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [device: ReportedIdentity(category: 0x02, subcategory: 0x03, firmwareVersion: 0x04)]))

  }

  @Test func readsAndWritesNothingWhenNothingWasLearned() {

    let file = File(.success(NetworkSnapshot()))

    #expect(IdentityCache.save(NetworkSnapshot(hub: hub), since: NetworkSnapshot(hub: hub), to: file, path: path) == .unchanged)
    #expect(file.reads == 0)
    #expect(file.written.isEmpty)

  }

  @Test func mergesWhatWasLearnedIntoWhatTheCacheHolds() {

    let current = NetworkSnapshot(registry: identified.registry)
    let file = File(.success(current))
    let learned = NetworkSnapshot(hub: hub)

    #expect(IdentityCache.save(learned, since: NetworkSnapshot(), to: file, path: path) == .saved)
    #expect(file.written == [current.merging(changesFrom: NetworkSnapshot(), to: learned)])
    #expect(file.written.first?.registry == identified.registry)
    #expect(file.written.first?.hub == hub)

  }

  @Test func writesNothingWhenTheCacheAlreadyHoldsTheChange() {

    let file = File(.success(NetworkSnapshot(hub: hub)))

    #expect(IdentityCache.save(NetworkSnapshot(hub: hub), since: NetworkSnapshot(hub: otherHub), to: file, path: path) == .unchanged)
    #expect(file.written.isEmpty)

  }

  @Test func leavesAnUnreadableCacheAsItIsAndWarnsWhenAnIdentityWouldBeLost() {

    let file = File(.failure(.malformedContents))

    #expect(
      IdentityCache.save(identified, since: NetworkSnapshot(), to: file, path: path)
        == .notSaved(warning: IdentityCache.warning(for: DeviceRegistryStoreError.malformedContents, path: path))
    )
    #expect(file.written.isEmpty)

  }

  @Test func leavesAnUnreadableCacheAsItIsQuietlyWhenNoIdentityWouldBeLost() {

    let file = File(.failure(.unreadableFile))

    #expect(IdentityCache.save(NetworkSnapshot(hub: hub), since: NetworkSnapshot(), to: file, path: path) == .notSaved(warning: nil))
    #expect(file.written.isEmpty)

  }

  @Test func warnsWhenTheChangesCantBeWritten() {

    let file = File(.success(NetworkSnapshot()), writeFailure: .writeFailed(code: 28))

    #expect(
      IdentityCache.save(NetworkSnapshot(hub: hub), since: NetworkSnapshot(), to: file, path: path)
        == .notSaved(warning: IdentityCache.warning(for: DeviceRegistryStoreError.writeFailed(code: 28), path: path))
    )

  }

  @Test func saysWhyIdentitiesWontBeRemembered() {

    let format = "insteon: warning: the identity cache \(path) isn't in a format this command reads, so it's left as it is "
      + "and the identities devices report won't be remembered. Delete it to start a new one."

    #expect(IdentityCache.warning(for: DeviceRegistryStoreError.malformedContents, path: path) == format)
    #expect(IdentityCache.warning(for: DeviceRegistryStoreError.unsupportedVersion(9), path: path) == format)
    #expect(
      IdentityCache.warning(for: DeviceRegistryStoreError.unreadableFile, path: path)
        == "insteon: warning: the identity cache \(path) couldn't be read, so it's left as it is and the identities devices report won't be remembered."
    )
    #expect(
      IdentityCache.warning(for: DeviceRegistryStoreError.writeFailed(code: 13), path: path)
        == "insteon: warning: the identity cache \(path) couldn't be written, so the identities devices report won't be remembered."
    )

  }

}
