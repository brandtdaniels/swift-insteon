import Foundation
import InsteonClient
import InsteonCore
import InsteonService
import Observation

/// What the scenes screen shows for one device that answers a scene.
public struct SceneMemberRow: Identifiable, Equatable, Sendable {
  /// The member's address, which names the row.
  public let id: InsteonAddress
  /// The member's address as text.
  public let title: String
  /// What the member does when the scene runs, in the catalog's words, or its raw bytes.
  public let detail: String
  /// Whether the device catalog says nothing about what the bytes mean.
  public let isUndescribed: Bool
}

/// What the scenes screen shows for one scene.
public struct SceneRow: Identifiable, Equatable, Sendable {
  /// The scene's ALL-Link group number, which names the row.
  public let id: Int
  /// The scene's name on the screen.
  public let title: String
  /// What starts the scene.
  public let source: String
  /// The devices that answer the scene.
  public let members: [SceneMemberRow]
  /// Whether the scene can be run from here: the modem starts it and it has members.
  public let canRun: Bool
  /// Why the scene can't be run, or `nil` when it can.
  public let note: String?
}

/// How a run of a scene ended, in words for a person.
public struct RunOutcome: Equatable, Sendable {
  /// What kind of ending it was.
  public enum Kind: Equatable, Sendable {
    /// The modem reached every member.
    case complete
    /// The modem accepted the command and didn't report reaching every member.
    case incomplete
    /// The command may have gone out and the answer was lost, so the lights may have changed.
    case unknown
    /// The service refused the request and nothing was sent.
    case refused
  }

  /// What kind of ending it was.
  public let kind: Kind
  /// A short headline.
  public let title: String
  /// What the person should know.
  public let message: String

  /// Creates an outcome.
  public init(kind: Kind, title: String, message: String) {
    self.kind = kind
    self.title = title
    self.message = message
  }
}

/// The scenes screen: what the network lists, a refresh that reads the hardware, and a run for each
/// scene the modem starts.
///
/// It calls the network and presents the answer. The network decides what a scene is, whether it can
/// run and what a refusal means; the screen only says so in words.
@MainActor
@Observable
public final class ScenesScreen<Network: SceneManaging> {
  /// Where the screen's load stands.
  public enum State: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
  }

  /// Where the screen's loading stands.
  public private(set) var state: State = .idle
  /// The scenes, in the order the network lists them. A failed load leaves the previous rows.
  public private(set) var rows: [SceneRow] = []
  /// Whether every database was read and every record has its other half.
  public private(set) var isWhole = true
  /// What is missing from the list when it isn't whole, one sentence each.
  public private(set) var gaps: [String] = []
  /// How the last run ended, until it is dismissed or another run starts.
  public private(set) var outcome: RunOutcome?
  /// Whether a read of the hardware is out.
  public private(set) var isRefreshing = false

  private var running: (scene: Int, action: SceneAction)?
  private var settled: State = .idle
  private let network: Network

  /// Whether a load is out.
  public var isLoading: Bool { state == .loading }

  /// Whether any call is out, so the screen sends nothing else: the service takes one at a time.
  public var isBusy: Bool { isLoading || isRefreshing || running != nil }

  /// Whether the last load succeeded and the network lists no scenes.
  public var isEmpty: Bool { state == .loaded && rows.isEmpty }

  /// What to say when the list is empty, or `nil` when it isn't.
  public var emptyMessage: String? {
    guard isEmpty else { return nil }
    return isWhole ? "This network has no scenes." : "No scenes have been read yet. Read them from the network to see them."
  }

  /// What the last load or refresh failed with, to show beside any rows kept from before, until one succeeds.
  public var failure: String? {
    if case let .failed(message) = settled { message } else { nil }
  }

  /// Whether a run of this scene is out.
  public func isRunning(_ row: SceneRow) -> Bool { running?.scene == row.id }

  /// Creates a screen over a network.
  public init(network: Network) {
    self.network = network
  }

  /// Asks the network for the scenes it holds. Nothing is sent to hardware. It does nothing while a
  /// load or a refresh is out.
  public func load() async {
    guard !isLoading, !isRefreshing else { return }
    state = .loading
    do {
      show(try await network.scenes())
      settled = .loaded
    } catch is CancellationError {
      // A cancelled load changes nothing.
    } catch {
      settled = .failed(Self.failureMessage(for: error, refreshing: false))
    }
    state = settled
  }

  /// Has the network read the ALL-Link databases from the hardware, which can take a while, then
  /// shows what was read. It does nothing while another call is out.
  public func refresh() async {
    guard !isBusy else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      show(try await network.refreshScenes())
      settled = .loaded
    } catch is CancellationError {
      return
    } catch {
      settled = .failed(Self.failureMessage(for: error, refreshing: true))
    }
    state = settled
  }

  /// Tells a scene to turn on or off, once, and says how it went in ``outcome``.
  ///
  /// A scene that can't run, or a screen with a call out, sends nothing. The run reads no member
  /// afterward, so the listed scenes stay as they were.
  public func run(_ row: SceneRow, _ action: SceneAction) async {
    guard rows.first(where: { $0.id == row.id })?.canRun == true, !isBusy else { return }
    running = (row.id, action)
    defer { running = nil }
    outcome = nil
    do {
      outcome = Self.outcome(of: try await network.runScene(row.id, action: action), title: row.title)
    } catch is CancellationError {
      return
    } catch {
      outcome = Self.outcome(of: error, title: row.title)
    }
  }

  /// Clears the outcome once it has been shown.
  public func dismissOutcome() { outcome = nil }

  // MARK: Mapping the answers

  private func show(_ list: SceneList) {
    rows = list.scenes.map(Self.row)
    isWhole = list.isWhole
    gaps = Self.gaps(in: list)
  }

  private static func row(_ scene: SceneList.Scene) -> SceneRow {
    let canRun = scene.isWritable && !scene.members.isEmpty
    let note: String? = if !scene.isWritable {
      "A device starts this scene, so it can't be run from here."
    } else if scene.members.isEmpty {
      "It has no members, so there is nothing to run."
    } else {
      nil
    }
    return SceneRow(
      id: scene.number, title: "Scene \(scene.number)", source: source(scene.source), members: scene.members.map(member), canRun: canRun, note: note)
  }

  private static func source(_ source: SceneList.Source) -> String {
    switch source {
    case .modem: "Started by the modem"
    case let .device(address): "Started by \(address)"
    }
  }

  private static func member(_ member: SceneList.Member) -> SceneMemberRow {
    // The group byte names the member's own group, which says nothing about what the scene does.
    let shown = member.bytes.filter { !$0.isPerGroup }
    if member.isDescribed, !shown.isEmpty {
      let detail = shown.map { "\($0.label ?? $0.name): \($0.valueName ?? hex($0.value))." }.joined(separator: " ")
      return SceneMemberRow(id: member.address, title: member.address.description, detail: detail, isUndescribed: false)
    }
    return SceneMemberRow(
      id: member.address, title: member.address.description,
      detail: "Data \(member.data.map(hex).joined(separator: " ")). The device catalog doesn't describe these bytes.", isUndescribed: true)
  }

  private static func hex(_ value: UInt8) -> String { "0x" + String(format: "%02X", value) }

  private static func gaps(in list: SceneList) -> [String] {
    var gaps: [String] = []
    if list.isModemUnread { gaps.append("The modem's own database wasn't read.") }
    for device in list.unreadable { gaps.append("\(device.address) wasn't read: \(reason(device.reason)).") }
    for address in list.unlisted { gaps.append("\(address) has no ALL-Link database the service could read.") }
    let halves = list.looseHalfLinks.count + list.scenes.reduce(0) { $0 + $1.halfLinks.count }
    if halves == 1 { gaps.append("1 record has no matching record on the other device.") }
    if halves > 1 { gaps.append("\(halves) records have no matching record on the other device.") }
    if gaps.isEmpty, !list.isWhole { gaps.append("The list may be incomplete.") }
    return gaps
  }

  private static func reason(_ reason: SceneList.UnreadableReason) -> String {
    switch reason {
    case .noAnswer: "it didn't answer"
    case .rejectedModem: "it rejected the modem"
    case .damagedRecords: "its records were damaged"
    case .notCached: "the service hasn't read it yet"
    case .unavailableFromSource: "this network doesn't give out ALL-Link databases"
    case .modemStoppedEchoing: "the modem stopped confirming requests"
    case .hubStoppedAnswering: "the Hub stopped answering"
    case .failed: "the read failed"
    case .incomplete: "its database ended early"
    case let .other(name): "the service gave a reason this app doesn't know (\(name))"
    }
  }

  // MARK: Runs

  private static func outcome(of receipt: SceneRunReceipt, title: String) -> RunOutcome {
    let word = receipt.action == .on ? "on" : "off"
    let missing = receipt.unacknowledged.map(\.description).joined(separator: ", ")
    let mayHaveActed = receipt.unacknowledged.isEmpty ? "" : " Not acknowledged: \(missing). They may still have acted."
    if !receipt.isComplete {
      return RunOutcome(
        kind: .incomplete, title: "\(title) turned \(word), but not every member answered.",
        message: "The modem didn't report reaching every member, so some lights may not have changed." + mayHaveActed)
    }
    if !receipt.unacknowledged.isEmpty {
      return RunOutcome(
        kind: .incomplete, title: "\(title) turned \(word), but not every member answered.",
        message: "The modem reached every member, but some didn't acknowledge." + mayHaveActed)
    }
    // A modem that passes no per-member acknowledgment up leaves the list empty, which never means no member acted.
    let message = receipt.acknowledged.isEmpty
      ? "The modem reports that it reached every member. It doesn't say which acknowledged."
      : "The modem reached every member, and \(receipt.acknowledged.count) acknowledged."
    return RunOutcome(kind: .complete, title: "\(title) turned \(word).", message: message)
  }

  private static func outcome(of error: any Error, title: String) -> RunOutcome {
    switch refusal(of: error) {
    case let .refused(text):
      return RunOutcome(kind: .refused, title: "\(title) wasn't run.", message: text + " Nothing was sent.")
    case .mayHaveBeenSent:
      return RunOutcome(
        kind: .unknown, title: "\(title) may have run.",
        message: "The command may have gone out before the answer was lost. The lights may have changed. Check the devices before running the scene again.")
    }
  }

  /// What an error from a scene call says about whether anything was sent.
  private enum Refusal {
    /// The service refused, or the call never left: nothing was sent.
    case refused(String)
    /// The call may have reached the service, and what it did is not known.
    case mayHaveBeenSent
  }

  private static func refusal(of error: any Error) -> Refusal {
    switch error {
    case let error as ConnectionError:
      switch error {
      case .interrupted, .badResponse: return .mayHaveBeenSent
      case let .outcomeUnknown(sent): return sent ? .mayHaveBeenSent : .refused("The service couldn't finish the request.")
      case .noPathReached: return .refused("The service couldn't be reached.")
      case .unauthorized: return .refused("The service refused this device's credential. Pair this device again.")
      case .forbidden: return .refused("This device isn't allowed to control the service.")
      case .unsupported: return .refused("This connection can't run scenes.")
      case .invalidScene: return .refused("That isn't a scene the service can run.")
      case .modemUnavailable: return .refused("The service can't reach its modem right now.")
      case let .rejected(code, sent): return sent ? .mayHaveBeenSent : .refused("The service refused the request (\(code)).")
      }
    case let error as ServiceControlError:
      return .refused(error == .unknownScene ? "The service doesn't know that scene. Read the scenes again." : AppErrorText.message(for: error))
    default:
      // The screen can't tell what an error of another kind says about what was sent.
      return .mayHaveBeenSent
    }
  }

  private static func failureMessage(for error: any Error, refreshing: Bool) -> String {
    switch refusal(of: error) {
    case let .refused(text): return text
    case .mayHaveBeenSent:
      if case ConnectionError.interrupted = error {
        return refreshing
          ? "The connection was lost during the read. The service may still be reading: load the list again in a minute."
          : "The connection was lost. Try again."
      }
      if case let ConnectionError.rejected(code, _) = error { return "The service refused the request (\(code))." }
      if case ConnectionError.outcomeUnknown = error { return "The service couldn't finish the request." }
      return "The service gave an answer this app couldn't read."
    }
  }
}
