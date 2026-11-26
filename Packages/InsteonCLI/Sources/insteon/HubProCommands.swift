import Foundation
import InsteonCLISupport
import InsteonCore
import InsteonModem

/// The commands that run on a Hub Pro: `info`, `observe`, and `device ADDRESS` with `id`,
/// `status`, `on`, `off` (each with `--fast`), `ping` and `beep`. The decisions are in
/// InsteonCLISupport's `HubProText` and `HubProObservationRun`; this asks the Hub Pro and prints.
enum HubProCommands {

  static func run(_ invocation: Invocation, network: HubProNetwork, host: String, names: ProductNames) async throws {

    do {

      switch invocation.subcommand {
      case let .observe(options):
        try await observe(options, network: network, names: names)
      case let .backup(options):
        try await BackupCommand.run(options, hubPro: network, printsJSON: invocation.printsJSON)
      case let .transferPlan(options):
        let backup = try TransferCommand.load(options)
        try await TransferCommand.plan(backup, options: options, hubPro: network, printsJSON: invocation.printsJSON)
      case let .transferVerify(path):
        let backup = try TransferCommand.load(TransferPlanOptions(path: path))
        try await TransferCommand.verify(backup, hubPro: network, printsJSON: invocation.printsJSON)
      case .info:
        try await network.open()
        try await info(network: network, names: names, printsJSON: invocation.printsJSON)
      case let .device(address, action):
        try await network.open()
        try await device(address, action: action, network: network, names: names, printsJSON: invocation.printsJSON)
      default:
        throw CommandFailure(description: HubProText.cannot(invocation.subcommand, host: host))
      }

    } catch {

      if let message = HubProText.failure(error, host: host) {

        throw CommandFailure(description: message)

      }

      throw error

    }

  }

  // MARK: - info

  private struct Unit: Encodable {

    struct Entry: Encodable {

      let address: String
      let name: String
      let type: String
      let product: String?

    }

    let configVersion: String?
    let serverVersion: String?
    let devices: [Entry]

  }

  private static func info(network: HubProNetwork, names: ProductNames, printsJSON: Bool) async throws {

    let versions = await network.softwareVersions
    var entries: [(device: HubProListedDevice, product: String?)] = []

    for device in await network.devices() {

      entries.append((device, await productName(of: device.address, network: network, names: names)))

    }

    if printsJSON {

      try Output.json(Unit(
        configVersion: versions?.config.version,
        serverVersion: versions?.server.version,
        devices: entries.map { Unit.Entry(address: "\($0.device.address)", name: $0.device.name, type: $0.device.deviceType, product: $0.product) }
      ))

      return

    }

    if let versions {

      Output.line(HubProText.versionLine(versions))

    }

    Output.table(HubProText.devices(entries))

  }

  private static func productName(of address: InsteonAddress, network: HubProNetwork, names: ProductNames) async -> String? {

    guard let identity = await network.registry.device(address)?.identity else {

      return nil

    }

    return names.name(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion)

  }

  // MARK: - observe

  private static func observe(_ options: ObserveOptions, network: HubProNetwork, names: ProductNames) async throws {

    if options.device != nil {

      throw CommandFailure(description: "A Hub Pro is observed as a whole: leave out the device's ADDRESS.")

    }

    if let note = options.note, ObservationRedaction.strip(note) != note {

      throw CommandFailure(description: ObservationError.noteHoldsAddress.description)

    }

    Output.note("Reading the Hub Pro and each device it lists, one request at a time...")

    let findings = try await HubProObservationRun.observe(network, productName: names.name(category:subcategory:firmwareVersion:))
    let observation: HubProObservation

    do {

      observation = try HubProObservation(
        findings,
        tool: ObservationTool(name: "insteon", version: ObserveCommand.version),
        catalogVersion: names.catalogVersion,
        note: options.note,
        observedOn: Date()
      )

    } catch {

      throw CommandFailure(description: "\(error)")

    }

    let delivery = try ObservationDelivery.deliver(observation.json(), to: options.outputPath, files: ObserveCommand.DiskFiles())

    Output.note("Read \(findings.devices.count) devices, of \(findings.deviceTypes.count) kinds, and the Hub Pro's software versions.")

    if case let .standardOutput(json) = delivery {

      Output.line(json)

    }

    for line in ObservationText.closing(delivery) {

      Output.note(line)

    }

  }

  // MARK: - device

  private static func device(_ address: InsteonAddress, action: DeviceAction, network: HubProNetwork, names: ProductNames, printsJSON: Bool) async throws {

    let device = network.device(address)

    do {

      switch action {
      case .id:
        try await identify(address, network: network, names: names, printsJSON: printsJSON)
      case .status:
        try await status(device, printsJSON: printsJSON)
      case .ping:
        try await ping(device)
      case let .on(levelPercent):
        Output.line(DeviceText.turnedOn(address, result: try await device.turnOn(level: levelPercent)))
      case let .onFast(levelPercent):
        Output.line(DeviceText.turnedOn(address, result: try await device.turnOnFast(level: levelPercent)))
      case .off:
        try await device.turnOff()
        Output.line(DeviceText.turnedOff(address))
      case .offFast:
        _ = try await device.turnOffFast()
        Output.line(DeviceText.turnedOff(address))
      case .beep:
        _ = try await device.beep()
        Output.line(DeviceText.beeped(address))
      case .instant, .settings, .set, .send, .links, .selfTest:
        break
      }

    } catch let error as DeviceControlError {

      throw CommandFailure(description: DeviceText.failure(error, device: address))

    } catch ModemError.deviceTimedOut {

      throw CommandFailure(description: HubProText.unconfirmed(address))

    }

  }

  private struct Identity: Encodable {

    let address: String
    let name: String
    let type: String
    let product: String?
    let category: String?
    let subcategory: String?
    let firmware: String?
    let sku: String?
    let commands: [String]

  }

  private static func identify(_ address: InsteonAddress, network: HubProNetwork, names: ProductNames, printsJSON: Bool) async throws {

    // The Hub Pro reports what a device is when asked, so ask it again for the current answer.
    guard await network.description(of: address) != nil else {

      throw CommandFailure(description: DeviceText.failure(.notLinked, device: address))

    }

    try await network.identify(address)

    guard let description = await network.description(of: address) else {

      throw CommandFailure(description: DeviceText.failure(.notLinked, device: address))

    }

    let product = await productName(of: address, network: network, names: names)

    if printsJSON {

      try Output.json(Identity(
        address: "\(address)",
        name: description.name,
        type: description.deviceType,
        product: product,
        category: description.category.map(Hex.byte),
        subcategory: description.subcategory.map(Hex.byte),
        firmware: description.firmwareVersion.map(Hex.byte),
        sku: description.sku,
        commands: description.commandNames
      ))

      return

    }

    Output.table(HubProText.identityRows(description, product: product))

  }

  private struct Status: Encodable {

    let address: String
    let level: String
    let isOn: Bool
    let percent: Int?
    let allLinkDatabaseDelta: String

  }

  private static func status(_ device: HubProDevice, printsJSON: Bool) async throws {

    let status = try await device.status()

    if printsJSON {

      try Output.json(Status(
        address: "\(device.address)",
        level: Hex.byte(status.value),
        isOn: status.isOn,
        percent: status.percent,
        allLinkDatabaseDelta: Hex.byte(status.allLinkDatabaseDelta)
      ))

      return

    }

    Output.line(DeviceText.status(device.address, status: status))

  }

  private static func ping(_ device: HubProDevice) async throws {

    let clock = ContinuousClock()
    let start = clock.now

    try await device.ping()

    let elapsed = start.duration(to: clock.now).components
    let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000

    Output.line("\(device.address) answered in \(milliseconds) ms.")

  }

}
