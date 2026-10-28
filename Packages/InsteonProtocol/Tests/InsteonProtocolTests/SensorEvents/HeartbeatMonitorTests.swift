import Testing
import InsteonProtocol

struct HeartbeatMonitorTests {

  let leakSensor = InsteonAddress(0x2A, 0x3B, 0x4C)

  let motionSensor = InsteonAddress(0x1A, 0x2B, 0x3C)

  let start = ContinuousClock.now

  let hours = Duration.seconds(3_600)

  @Test func reportsADeviceOnceItsAllowancePasses() {

    var monitor = HeartbeatMonitor<ContinuousClock.Instant>(allowance: hours * 48)
    monitor.watch(leakSensor, since: start)

    #expect(monitor.silentDevices(at: start.advanced(by: hours * 48)).isEmpty)
    #expect(monitor.silentDevices(at: start.advanced(by: hours * 49)) == [leakSensor])

  }

  @Test func countsAnyMessageAsHearingFromTheDevice() {

    var monitor = HeartbeatMonitor<ContinuousClock.Instant>(allowance: hours * 48)
    monitor.watch(leakSensor, since: start)
    monitor.heard(from: leakSensor, at: start.advanced(by: hours * 24))

    #expect(monitor.silentDevices(at: start.advanced(by: hours * 49)).isEmpty)
    #expect(monitor.silentDevices(at: start.advanced(by: hours * 73)) == [leakSensor])

  }

  @Test func ignoresDevicesItIsntWatching() {

    var monitor = HeartbeatMonitor<ContinuousClock.Instant>(allowance: hours)
    monitor.heard(from: leakSensor, at: start)
    monitor.watch(motionSensor, since: start)
    monitor.stopWatching(motionSensor)

    #expect(monitor.watchedDevices.isEmpty)
    #expect(monitor.silentDevices(at: start.advanced(by: hours * 2)).isEmpty)

  }

  @Test func keepsTheLatestTimeADeviceWasHeardFrom() {

    var monitor = HeartbeatMonitor<ContinuousClock.Instant>(allowance: hours)
    monitor.watch(leakSensor, since: start.advanced(by: hours * 2))
    monitor.heard(from: leakSensor, at: start)

    #expect(monitor.silentDevices(at: start.advanced(by: hours * 2.5)).isEmpty)

  }

  @Test func listsSilentDevicesInAddressOrder() {

    var monitor = HeartbeatMonitor<ContinuousClock.Instant>()
    monitor.watch(leakSensor, since: start)
    monitor.watch(motionSensor, since: start)

    #expect(monitor.allowance == .seconds(171_360))
    #expect(monitor.silentDevices(at: start.advanced(by: hours * 48)) == [motionSensor, leakSensor])

  }

}
