import InsteonClient
import InsteonCore
import InsteonService

/// Scenes that answer from values a test gives them, record what they are asked, and can hold a run
/// or a refresh so a test can act while one is in flight.
actor ScriptedScenes: SceneManaging {

  private var listing: SceneList
  private var readListing: SceneList
  private var listFailure: (any Error)?
  private var refreshFailure: (any Error)?
  private var runFailure: (any Error)?
  private var receipt: SceneRunReceipt?
  private(set) var calls: [String] = []
  private(set) var runs: [(number: Int, action: SceneAction)] = []
  private var holdsRun = false
  private var heldRuns: [CheckedContinuation<Void, Never>] = []
  private var runAnnounced = 0
  private var runObserved = 0
  private var runWatcher: CheckedContinuation<Void, Never>?
  private var holdsRefresh = false
  private var heldRefreshes: [CheckedContinuation<Void, Never>] = []
  private var refreshAnnounced = 0
  private var refreshObserved = 0
  private var refreshWatcher: CheckedContinuation<Void, Never>?

  /// - Parameters:
  ///   - listed: What a listing answers before a refresh.
  ///   - read: What a refresh answers, and every listing after it.
  init(listed: SceneList, read: SceneList? = nil) {
    listing = listed
    readListing = read ?? listed
  }

  func setListFailure(_ error: (any Error)?) { listFailure = error }
  func setRefreshFailure(_ error: (any Error)?) { refreshFailure = error }
  func setRunFailure(_ error: (any Error)?) { runFailure = error }
  func setReceipt(_ receipt: SceneRunReceipt) { self.receipt = receipt }
  func setListed(_ list: SceneList) { listing = list }

  /// Makes the next run wait, after it is recorded, until ``releaseRun()``.
  func holdNextRun() { holdsRun = true }

  /// Returns once a run is waiting.
  func waitForHeldRun() async {
    if runAnnounced == runObserved { await withCheckedContinuation { runWatcher = $0 } }
    runObserved += 1
  }

  func releaseRun() {
    let waiting = heldRuns
    heldRuns = []
    for continuation in waiting { continuation.resume() }
  }

  /// Makes the next refresh wait, after it is recorded, until ``releaseRefresh()``.
  func holdNextRefresh() { holdsRefresh = true }

  /// Returns once a refresh is waiting.
  func waitForHeldRefresh() async {
    if refreshAnnounced == refreshObserved { await withCheckedContinuation { refreshWatcher = $0 } }
    refreshObserved += 1
  }

  func releaseRefresh() {
    let waiting = heldRefreshes
    heldRefreshes = []
    for continuation in waiting { continuation.resume() }
  }

  func scenes() async throws -> SceneList {
    calls.append("scenes")
    if let listFailure { throw listFailure }
    return listing
  }

  func refreshScenes() async throws -> SceneList {
    calls.append("refreshScenes")
    if holdsRefresh {
      holdsRefresh = false
      refreshAnnounced += 1
      refreshWatcher?.resume()
      refreshWatcher = nil
      await withCheckedContinuation { heldRefreshes.append($0) }
    }
    if let refreshFailure { throw refreshFailure }
    listing = readListing
    return readListing
  }

  func runScene(_ number: Int, action: SceneAction, idempotencyKey: String?) async throws -> SceneRunReceipt {
    calls.append("runScene")
    runs.append((number, action))
    if holdsRun {
      holdsRun = false
      runAnnounced += 1
      runWatcher?.resume()
      runWatcher = nil
      await withCheckedContinuation { heldRuns.append($0) }
    }
    if let runFailure { throw runFailure }
    return receipt ?? SceneRunReceipt(scene: number, action: action, acknowledged: [], unacknowledged: [], isComplete: true, responderCount: 0, persistence: .notConfigured)
  }
}

/// Invented scenes and members for the scenes screen's tests.
enum SceneFixtures {
  static let lamp = InsteonAddress("1A.2B.3C")!
  static let ceiling = InsteonAddress("4D.5E.6F")!
  static let keypad = InsteonAddress("7A.8B.9C")!

  static let describedBytes = [
    SceneList.Byte(position: 1, name: "onLevel", label: "On-level", value: 0xFF, valueName: "On", isPerGroup: false, verification: .observed),
    SceneList.Byte(position: 2, name: "rampRate", label: "Ramp rate", value: 0x1F, valueName: nil, isPerGroup: false, verification: .documented),
    SceneList.Byte(position: 3, name: "group", label: nil, value: 0x01, valueName: nil, isPerGroup: true, verification: .inferred)
  ]

  static let described = SceneList.Member(address: lamp, data: [0xFF, 0x1F, 0x01], isDescribed: true, bytes: describedBytes)
  static let undescribed = SceneList.Member(address: ceiling, data: [0x80, 0x1C, 0x00], isDescribed: false, bytes: [])

  static let evening = SceneList.Scene(number: 3, source: .modem, isWritable: true, members: [described, undescribed], halfLinks: [])
  static let empty = SceneList.Scene(number: 4, source: .modem, isWritable: true, members: [], halfLinks: [])
  static let fromKeypad = SceneList.Scene(number: 2, source: .device(keypad), isWritable: false, members: [described], halfLinks: [])

  /// A whole list of these scenes.
  static func whole(_ scenes: [SceneList.Scene] = [evening]) -> SceneList {
    SceneList(scenes: scenes, looseHalfLinks: [], unreadable: [], unlisted: [], isModemUnread: false, undescribedMembers: [], isWhole: true)
  }

  /// A list that is not whole for the reasons given.
  static func partial(
    _ scenes: [SceneList.Scene] = [evening], unreadable: [SceneList.UnreadableDevice] = [], unlisted: [InsteonAddress] = [],
    isModemUnread: Bool = false, looseHalfLinks: [SceneList.HalfLink] = []
  ) -> SceneList {
    SceneList(scenes: scenes, looseHalfLinks: looseHalfLinks, unreadable: unreadable, unlisted: unlisted, isModemUnread: isModemUnread, undescribedMembers: [], isWhole: false)
  }
}
