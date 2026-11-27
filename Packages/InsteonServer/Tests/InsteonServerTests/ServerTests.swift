import InsteonService
import Logging
import Testing
@testable import InsteonServerSupport

@Suite(.timeLimit(.minutes(1)))
struct ServerTests {
  @Test func configDefaultsToLoopbackAndCanBindToVPNAddress() throws {
    let defaults = try ServerOptions(arguments: [], environment: [:])
    #expect(defaults.listen == "127.0.0.1")
    #expect(defaults.port == 8080)
    let vpn = try ServerOptions(arguments: ["--listen", "100.100.20.30", "--port", "8888"], environment: [:])
    #expect(vpn.listen == "100.100.20.30")
    #expect(vpn.port == 8888)
  }

  @Test func missingOrWeakServerPasswordFailsBeforeConnectingToHardware() async {
    await #expect(throws: ServerRunError.missingPassword) {
      try await ServerRunner.run(arguments: ["--hub", "192.168.1.20"], environment: [:])
    }
    await #expect(throws: ServerRunError.invalidPassword) {
      try await ServerRunner.run(arguments: ["--hub", "192.168.1.20"], environment: ["INSTEON_GATEWAY_PASSWORD": "short"])
    }
  }

  @Test(arguments: [["--listen", "0.0.0.0"], ["--listen", "8.8.8.8"], ["--listen", "example.com"], ["--port", "0"], ["--port", "65536"], ["--hub"], ["--unknown", "value"], ["--port", "8080", "--port", "8081"]])
  func invalidConfigurationIsRefused(_ arguments: [String]) {
    #expect(throws: ServerOptionError.self) { try ServerOptions(arguments: arguments, environment: [:]) }
  }
}

extension ServerTests {
  @Test func theHubProPollIntervalDefaultsToFiveSecondsAndStartsAtTwo() throws {
    #expect(try ServerOptions(arguments: [], environment: [:]).pollIntervalSeconds == 5)
    #expect(try ServerOptions(arguments: ["--poll-interval", "2"], environment: [:]).pollIntervalSeconds == 2)
    #expect(try ServerOptions(arguments: ["--poll-interval", "3600"], environment: [:]).pollIntervalSeconds == 3600)
  }

  @Test(arguments: ["1", "0", "-5", "3601", "fast", "2.5"])
  func aPollIntervalBelowTheFloorOrNotANumberIsRefused(_ value: String) {
    #expect(throws: ServerOptionError.invalidPollInterval) { try ServerOptions(arguments: ["--poll-interval", value], environment: [:]) }
  }

  @Test func theAdvertisedAddressAndNetworkNameAreOptionsWithDefaults() throws {
    let defaults = try ServerOptions(arguments: [], environment: [:])
    #expect(defaults.advertiseURL == nil)
    #expect(defaults.networkName == "Network")
    let chosen = try ServerOptions(arguments: ["--advertise-url", "https://insteon.example.net:8443/", "--network-name", "Beach house"], environment: [:])
    #expect(chosen.advertiseURL == "https://insteon.example.net:8443")
    #expect(chosen.networkName == "Beach house")
  }

  @Test(arguments: [["--advertise-url", "insteon.local"], ["--advertise-url", "ftp://insteon.local"], ["--advertise-url", "http://u:p@insteon.local"], ["--advertise-url", "http://insteon.local/x"], ["--advertise-url", "http://insteon.local?x=1"], ["--advertise-url", "http://"], ["--network-name", String(repeating: "h", count: 65)], ["--network-name", "bad\u{7}name"]])
  func anUnusableAdvertisedAddressOrNetworkNameIsRefused(_ arguments: [String]) {
    #expect(throws: ServerOptionError.self) { try ServerOptions(arguments: arguments, environment: [:]) }
  }
}

extension ServerTests {
  @Test func theLocationAndTimeZoneAreOptionsWithoutDefaults() throws {
    let defaults = try ServerOptions(arguments: [], environment: [:])
    #expect(defaults.latitude == nil && defaults.longitude == nil && defaults.timeZone == nil)
    let chosen = try ServerOptions(arguments: ["--latitude", "-33.87", "--longitude", "151.21", "--time-zone", "Australia/Sydney"], environment: [:])
    #expect(chosen.latitude == -33.87 && chosen.longitude == 151.21 && chosen.timeZone == "Australia/Sydney")
  }

  @Test(arguments: [
    ["--latitude", "34"], ["--longitude", "-118"], ["--latitude", "91", "--longitude", "0"], ["--latitude", "0", "--longitude", "181"],
    ["--latitude", "north", "--longitude", "0"], ["--latitude", "nan", "--longitude", "0"]
  ])
  func aLocationNeedsBothCoordinatesWithinRange(_ arguments: [String]) {
    #expect(throws: ServerOptionError.invalidLocation) { try ServerOptions(arguments: arguments, environment: [:]) }
  }

  @Test(arguments: ["Not a zone", "../etc/localtime", "bad\u{7}zone", String(repeating: "z", count: 65)])
  func aTimeZoneThatIsNotAZoneNameIsRefused(_ name: String) {
    #expect(throws: ServerOptionError.invalidTimeZone) { try ServerOptions(arguments: ["--time-zone", name], environment: [:]) }
  }

  @Test func aTimeZoneTheHostMightNotHaveIsStillAccepted() throws {
    #expect(try ServerOptions(arguments: ["--time-zone", "Not/AZone"], environment: [:]).timeZone == "Not/AZone")
  }
}

extension ServerTests {
  @Test func theLogLevelDefaultsToInfoAndTakesEachLevelByName() throws {
    #expect(try ServerOptions(arguments: [], environment: [:]).logLevel == .info)
    for level in Logger.Level.allCases {
      #expect(try ServerOptions(arguments: ["--log-level", level.rawValue], environment: [:]).logLevel == level)
    }
  }

  @Test func theEnvironmentVariableSetsTheLevelWhenTheOptionIsAbsentAndTheOptionWins() throws {
    #expect(try ServerOptions(arguments: [], environment: ["INSTEON_LOG_LEVEL": "debug"]).logLevel == .debug)
    #expect(try ServerOptions(arguments: ["--log-level", "warning"], environment: ["INSTEON_LOG_LEVEL": "debug"]).logLevel == .warning)
  }

  @Test(arguments: ["verbose", "", "debug ", "5", "--debug"])
  func anUnknownLevelInTheOptionIsRefused(_ value: String) {
    #expect(throws: ServerOptionError.self) { try ServerOptions(arguments: ["--log-level", value], environment: [:]) }
  }

  @Test(arguments: ["verbose", "", "loud"])
  func anUnknownLevelInTheEnvironmentIsRefusedNotIgnored(_ value: String) {
    #expect(throws: ServerOptionError.invalidLogLevel) { try ServerOptions(arguments: [], environment: ["INSTEON_LOG_LEVEL": value]) }
  }

  @Test func aBadEnvironmentLevelIsStillRefusedWhenTheOptionIsGood() {
    #expect(throws: ServerOptionError.invalidLogLevel) { try ServerOptions(arguments: ["--log-level", "debug"], environment: ["INSTEON_LOG_LEVEL": "loud"]) }
  }

  @Test func aBadLevelHasItsOwnCodeAndNamesTheOptionAndTheVariableButNotTheValue() {
    let failure = ServerFailure(ServerOptionError.invalidLogLevel)
    #expect(failure.code == .logLevelInvalid)
    #expect(failure.code.rawValue == "log_level_invalid")
    #expect(failure.exitStatus == ServerFailure.configurationStatus)
    #expect(failure.message.contains("--log-level") && failure.message.contains("INSTEON_LOG_LEVEL"))
    for level in Logger.Level.allCases { #expect(failure.message.contains(level.rawValue)) }
  }

  @Test func theHandlerTheServerLogsThroughUsesTheChosenLevel() throws {
    let handler = ServerLogging.handler(label: "test", level: try ServerOptions(arguments: ["--log-level", "debug"], environment: [:]).logLevel)
    #expect(handler.logLevel == .debug)
    #expect(ServerLogging.handler(label: "test", level: .info).logLevel == .info)
  }

  @Test func theHelpNamesTheOptionTheVariableAndThePrecedence() {
    #expect(ServerRunner.help.contains("--log-level LEVEL"))
    #expect(ServerRunner.help.contains("INSTEON_LOG_LEVEL"))
    #expect(ServerRunner.help.contains("trace, debug, info, notice, warning, error, critical"))
  }
}

extension ServerTests {
  @Test func theSceneWaitsDefaultToTheStandardTuningAndSayTheyAreDefaults() throws {
    let options = try ServerOptions(arguments: [], environment: [:])
    #expect(options.tuning == .standard)
    #expect(options.tuningSources.isEmpty)
  }

  @Test func eachSceneWaitFlagSetsItsValueInMillisecondsAndIsReportedAsAFlag() throws {
    let options = try ServerOptions(arguments: ["--scene-echo-wait-ms", "8000", "--scene-cleanup-quiet-ms", "20000", "--scene-cleanup-cap-ms", "90000"], environment: [:])
    #expect(options.tuning.scenes == .init(echoWait: .seconds(8), cleanupQuietPeriod: .seconds(20), cleanupCap: .seconds(90)))
    #expect(options.tuningSources == ["scenes.echoWaitMs": .flag, "scenes.cleanupQuietMs": .flag, "scenes.cleanupCapMs": .flag])
  }

  @Test func eachSceneWaitEnvironmentVariableSetsItsValueAndIsReportedAsTheEnvironment() throws {
    let environment = ["INSTEON_SCENE_ECHO_WAIT_MS": "9000", "INSTEON_SCENE_CLEANUP_QUIET_MS": "30000", "INSTEON_SCENE_CLEANUP_CAP_MS": "120000"]
    let options = try ServerOptions(arguments: [], environment: environment)
    #expect(options.tuning.scenes == .init(echoWait: .seconds(9), cleanupQuietPeriod: .seconds(30), cleanupCap: .seconds(120)))
    #expect(options.tuningSources == ["scenes.echoWaitMs": .environment, "scenes.cleanupQuietMs": .environment, "scenes.cleanupCapMs": .environment])
  }

  @Test func aFlagBeatsTheEnvironmentWhichBeatsTheDefaultForEachValueSeparately() throws {
    let options = try ServerOptions(arguments: ["--scene-echo-wait-ms", "8000"], environment: ["INSTEON_SCENE_ECHO_WAIT_MS": "9000", "INSTEON_SCENE_CLEANUP_CAP_MS": "100000"])
    #expect(options.tuning.scenes.echoWait == .seconds(8))
    #expect(options.tuning.scenes.cleanupCap == .seconds(100))
    #expect(options.tuning.scenes.cleanupQuietPeriod == .seconds(15))
    #expect(options.tuningSources == ["scenes.echoWaitMs": .flag, "scenes.cleanupCapMs": .environment])
  }

  @Test(arguments: ["0", "-5", "60001", "fast", "1.5", " "])
  func anEchoWaitOutOfRangeIsRefused(_ value: String) {
    #expect(throws: ServerOptionError.invalidSceneEchoWait) { try ServerOptions(arguments: ["--scene-echo-wait-ms", value], environment: [:]) }
    #expect(throws: ServerOptionError.invalidSceneEchoWait) { try ServerOptions(arguments: [], environment: ["INSTEON_SCENE_ECHO_WAIT_MS": value]) }
  }

  // The Insteon Developer's Guide gives 2.150 seconds to the first cleanup, so a shorter quiet period is refused.
  @Test(arguments: ["0", "2149", "300001", "slow"])
  func aQuietPeriodShorterThanTheGuidesFirstCleanupOrTooLongIsRefused(_ value: String) {
    #expect(throws: ServerOptionError.invalidSceneCleanupQuiet) { try ServerOptions(arguments: ["--scene-cleanup-quiet-ms", value], environment: [:]) }
    #expect(throws: ServerOptionError.invalidSceneCleanupQuiet) { try ServerOptions(arguments: [], environment: ["INSTEON_SCENE_CLEANUP_QUIET_MS": value]) }
  }

  @Test(arguments: ["0", "300001", "-1", "long"])
  func aCapOutOfRangeIsRefused(_ value: String) {
    #expect(throws: ServerOptionError.invalidSceneCleanupCap) { try ServerOptions(arguments: ["--scene-cleanup-cap-ms", value], environment: [:]) }
    #expect(throws: ServerOptionError.invalidSceneCleanupCap) { try ServerOptions(arguments: [], environment: ["INSTEON_SCENE_CLEANUP_CAP_MS": value]) }
  }

  @Test func aQuietPeriodLongerThanTheCapIsRefusedAsTheQuietPeriod() {
    #expect(throws: ServerOptionError.invalidSceneCleanupQuiet) { try ServerOptions(arguments: ["--scene-cleanup-quiet-ms", "70000"], environment: [:]) }
    #expect(throws: ServerOptionError.invalidSceneCleanupQuiet) { try ServerOptions(arguments: ["--scene-cleanup-quiet-ms", "20000", "--scene-cleanup-cap-ms", "10000"], environment: [:]) }
  }

  // Setting only the cap leaves the quiet period unset, so it is the shorter of its standard value and the cap.
  @Test(arguments: [("10000", 10_000), ("15000", 15_000), ("120000", 15_000), ("2150", 2_150)])
  func aCapBelowTheStandardQuietPeriodShortensTheQuietPeriodThatWasNotSet(_ cap: String, _ quietMilliseconds: Int) throws {
    for options in [
      try ServerOptions(arguments: ["--scene-cleanup-cap-ms", cap], environment: [:]),
      try ServerOptions(arguments: [], environment: ["INSTEON_SCENE_CLEANUP_CAP_MS": cap])
    ] {
      #expect(options.tuning.scenes.cleanupQuietPeriod == .milliseconds(quietMilliseconds))
      #expect(options.tuningSources[ServiceTuningError.Field.scenesCleanupQuiet.name] == nil)
    }
  }

  @Test func aCapShorterThanTheFirstCleanupIsRefusedAsTheCapNotTheQuietPeriod() {
    #expect(throws: ServerOptionError.invalidSceneCleanupCap) { try ServerOptions(arguments: ["--scene-cleanup-cap-ms", "2149"], environment: [:]) }
    #expect(throws: ServerOptionError.invalidSceneCleanupCap) { try ServerOptions(arguments: ["--scene-cleanup-cap-ms", "1000"], environment: [:]) }
  }

  @Test func aQuietPeriodTheOperatorSetThatPassesTheCapIsRefusedAsTheQuietPeriodEvenWhenTheCapIsShort() {
    #expect(throws: ServerOptionError.invalidSceneCleanupQuiet) { try ServerOptions(arguments: ["--scene-cleanup-quiet-ms", "20000", "--scene-cleanup-cap-ms", "10000"], environment: [:]) }
    #expect(throws: ServerOptionError.invalidSceneCleanupQuiet) { try ServerOptions(arguments: ["--scene-cleanup-cap-ms", "10000"], environment: ["INSTEON_SCENE_CLEANUP_QUIET_MS": "20000"]) }
  }

  @Test func theHelpSaysAnUnsetQuietPeriodFollowsAShortCap() {
    #expect(ServerRunner.help.contains("shorter cap"))
  }

  @Test func eachBadSceneValueHasItsOwnCodeAndNamesTheFlagAndTheVariableButNotTheValue() {
    let cases: [(ServerOptionError, ServerFailure.Code, String, String)] = [
      (.invalidSceneEchoWait, .sceneEchoWaitInvalid, "--scene-echo-wait-ms", "INSTEON_SCENE_ECHO_WAIT_MS"),
      (.invalidSceneCleanupQuiet, .sceneCleanupQuietInvalid, "--scene-cleanup-quiet-ms", "INSTEON_SCENE_CLEANUP_QUIET_MS"),
      (.invalidSceneCleanupCap, .sceneCleanupCapInvalid, "--scene-cleanup-cap-ms", "INSTEON_SCENE_CLEANUP_CAP_MS")
    ]
    for (error, code, flag, variable) in cases {
      let failure = ServerFailure(error)
      #expect(failure.code == code)
      #expect(failure.exitStatus == ServerFailure.configurationStatus)
      #expect(failure.message.contains(flag) && failure.message.contains(variable))
    }
  }

  @Test func theHelpHasAnAdvancedSettingsPartNamingEachSceneFlagAndVariable() {
    #expect(ServerRunner.help.contains("Advanced settings"))
    for name in ["--scene-echo-wait-ms", "--scene-cleanup-quiet-ms", "--scene-cleanup-cap-ms", "INSTEON_SCENE_ECHO_WAIT_MS", "INSTEON_SCENE_CLEANUP_QUIET_MS", "INSTEON_SCENE_CLEANUP_CAP_MS"] {
      #expect(ServerRunner.help.contains(name), "\(name)")
    }
  }
}
