#if canImport(JavaScriptCore)
import JavaScriptCore
import Testing
@testable import InsteonHTTP

/// Runs the `createLiveLink` function that `/controls.js` embeds, inside JavaScriptCore. The
/// event sources and timers are Swift objects the test drives, so nothing waits on time.
private final class LinkHarness {
  static let connecting = 0, open = 1, closed = 2

  let context = JSContext()!
  var sources: [JSValue] = []
  var log: [String] = []
  private var timers: [(id: Int, callback: JSValue, delay: Int)] = []
  private var nextTimer = 1
  private var link: JSValue!

  init() {
    context.exceptionHandler = { _, exception in Issue.record("JavaScript raised \(String(describing: exception))") }
    // The script's last expression is the function, which a top-level const leaves out of the global object.
    let create = context.evaluateScript(LiveLink.source + "\ncreateLiveLink;")!
    let dependencies = JSValue(newObjectIn: context)!
    func provide(_ name: String, _ block: AnyObject) {
      dependencies.setObject(block, forKeyedSubscript: name as NSString)
    }
    let open: @convention(block) () -> JSValue = { [unowned self] in
      let source = context.evaluateScript("({ readyState: 0, closeCount: 0, close() { this.readyState = 2; this.closeCount++; } })")!
      sources.append(source)
      return source
    }
    let schedule: @convention(block) (JSValue, Int) -> Int = { [unowned self] callback, delay in
      defer { nextTimer += 1 }
      timers.append((nextTimer, callback, delay))
      return nextTimer
    }
    let cancel: @convention(block) (Int) -> Void = { [unowned self] id in timers.removeAll { $0.id == id } }
    let onState: @convention(block) (String) -> Void = { [unowned self] in log.append("state:" + $0) }
    let onOpen: @convention(block) () -> Void = { [unowned self] in log.append("open") }
    let onClosed: @convention(block) () -> Void = { [unowned self] in log.append("closed") }
    let onMessage: @convention(block) (String) -> Void = { [unowned self] in log.append("message:" + $0) }
    provide("open", unsafeBitCast(open, to: AnyObject.self))
    provide("schedule", unsafeBitCast(schedule, to: AnyObject.self))
    provide("cancel", unsafeBitCast(cancel, to: AnyObject.self))
    provide("onState", unsafeBitCast(onState, to: AnyObject.self))
    provide("onOpen", unsafeBitCast(onOpen, to: AnyObject.self))
    provide("onClosed", unsafeBitCast(onClosed, to: AnyObject.self))
    provide("onMessage", unsafeBitCast(onMessage, to: AnyObject.self))
    link = create.call(withArguments: [dependencies])
  }

  var states: [String] { log.filter { $0.hasPrefix("state:") }.map { String($0.dropFirst(6)) } }
  var pendingDelays: [Int] { timers.map(\.delay) }
  func count(_ entry: String) -> Int { log.filter { $0 == entry }.count }
  func start() { link.invokeMethod("start", withArguments: []) }
  func stop() { link.invokeMethod("stop", withArguments: []) }

  func fireNextTimer() {
    let timer = timers.removeFirst()
    timer.callback.call(withArguments: [])
  }

  func opens(_ index: Int) {
    sources[index].setValue(Self.open, forProperty: "readyState")
    handler("onopen", of: index)
  }
  func fails(_ index: Int, state: Int) {
    sources[index].setValue(state, forProperty: "readyState")
    handler("onerror", of: index)
  }
  func says(_ index: Int, _ data: String) {
    let event = JSValue(object: ["data": data], in: context)!
    let handler = sources[index].forProperty("onmessage")!
    if !handler.isUndefined && !handler.isNull { handler.call(withArguments: [event]) }
  }
  func closeCount(_ index: Int) -> Int { Int(sources[index].forProperty("closeCount").toInt32()) }

  private func handler(_ name: String, of index: Int) {
    let handler = sources[index].forProperty(name)!
    if !handler.isUndefined && !handler.isNull { handler.call(withArguments: []) }
  }
}

/// The browser's event-stream link, scripted through JavaScriptCore on Apple platforms.
@Suite(.timeLimit(.minutes(1)))
struct LiveLinkTests {
  @Test func startOpensOneSourceAndReportsConnecting() {
    let h = LinkHarness()
    h.start()
    h.start()
    #expect(h.sources.count == 1)
    #expect(h.states == ["connecting"])
  }

  @Test func openingReportsConnectedAndAsksThePageToRefresh() {
    let h = LinkHarness()
    h.start()
    h.opens(0)
    #expect(h.states == ["connecting", "connected"])
    #expect(h.count("open") == 1)
  }

  @Test func aSourceTheBrowserClosedAfterA502IsReplacedThenThePageRefreshes() {
    let h = LinkHarness()
    h.start()
    h.opens(0)
    h.fails(0, state: LinkHarness.closed)
    #expect(h.states.last == "reconnecting")
    #expect(h.pendingDelays == [500])
    h.fireNextTimer()
    #expect(h.sources.count == 2)
    #expect(h.states.last == "connecting")
    h.opens(1)
    #expect(h.states.last == "connected")
    #expect(h.count("open") == 2)
  }

  @Test func backoffDoublesToACapAndASuccessfulOpenResetsIt() {
    let h = LinkHarness()
    h.start()
    var delays: [Int] = []
    for _ in 0..<9 {
      h.fails(h.sources.count - 1, state: LinkHarness.closed)
      delays.append(h.pendingDelays[0])
      h.fireNextTimer()
    }
    #expect(delays == [500, 1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000])
    h.opens(h.sources.count - 1)
    h.fails(h.sources.count - 1, state: LinkHarness.closed)
    #expect(h.pendingDelays == [500])
  }

  @Test func eachClosureTellsThePageSoItCanCheckAuthentication() {
    let h = LinkHarness()
    h.start()
    h.fails(0, state: LinkHarness.closed)
    h.fireNextTimer()
    h.fails(1, state: LinkHarness.closed)
    #expect(h.count("closed") == 2)
  }

  @Test func whileTheBrowserRetriesByItselfTheLinkOnlyReportsPaused() {
    let h = LinkHarness()
    h.start()
    h.opens(0)
    h.fails(0, state: LinkHarness.connecting)
    #expect(h.states.last == "paused")
    #expect(h.pendingDelays.isEmpty)
    #expect(h.sources.count == 1)
    h.opens(0)
    #expect(h.states.last == "connected")
  }

  @Test func startOnAClosedSourceReconnectsAtOnceAndDropsThePendingTimer() {
    let h = LinkHarness()
    h.start()
    h.fails(0, state: LinkHarness.closed)
    h.start()
    #expect(h.sources.count == 2)
    #expect(h.pendingDelays.isEmpty)
  }

  @Test func startLeavesALiveSourceAlone() {
    let h = LinkHarness()
    h.start()
    h.opens(0)
    h.start()
    #expect(h.sources.count == 1)
  }

  @Test func stopClosesTheSourceCancelsTheTimerAndIgnoresLateEvents() {
    let h = LinkHarness()
    h.start()
    h.fails(0, state: LinkHarness.closed)
    h.stop()
    #expect(h.pendingDelays.isEmpty)
    h.start()
    h.stop()
    #expect(h.closeCount(1) == 1)
    let before = h.log.count
    h.opens(1)
    h.says(1, "{}")
    h.fails(1, state: LinkHarness.closed)
    #expect(h.log.count == before)
    #expect(h.pendingDelays.isEmpty)
  }

  @Test func eventsFromAReplacedSourceAreIgnored() {
    let h = LinkHarness()
    h.start()
    h.fails(0, state: LinkHarness.closed)
    h.fireNextTimer()
    let before = h.log.count
    h.opens(0)
    h.says(0, "stale")
    #expect(h.log.count == before)
  }

  @Test func messagesReachThePage() {
    let h = LinkHarness()
    h.start()
    h.opens(0)
    h.says(0, #"{"version":1}"#)
    #expect(h.log.last == #"message:{"version":1}"#)
  }
}
#endif
