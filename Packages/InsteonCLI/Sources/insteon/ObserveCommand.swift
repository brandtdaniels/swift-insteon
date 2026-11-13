import Foundation
import InsteonCLISupport
import InsteonCore

/// `insteon observe ADDRESS`: asks a device read-only questions and writes what it did as a
/// JSON file. The decisions are in InsteonCLISupport's `ObservationRun` and `Observation`;
/// this asks the device and prints.
enum ObserveCommand {

  /// The version recorded in the file as the tool's.
  static let version: String = "0.1.0"

  static func run(_ options: ObserveOptions, modem: ModemSession, hub: HubLocation?, names: ProductNames) async throws {

    // Refused before the device is asked, so nothing is lost to a note that can't be recorded.
    if let note = options.note, ObservationRedaction.strip(note) != note {

      throw CommandFailure(description: ObservationError.noteHoldsAddress.description)

    }

    try await IdentityStore.withNetwork(modem: modem, hub: hub, names: names) { (cached: CachedNetwork) async throws -> Void in

      let source = DeviceSource(device: cached.network.device(options.device), network: cached.network, names: names)

      Output.note("Asking \(options.device) read-only questions...")

      let findings: ObservationFindings

      do {

        findings = try await ObservationRun.observe(source)

      } catch let error as DeviceControlError {

        throw CommandFailure(description: DeviceText.failure(error, device: options.device))

      }

      let observation: Observation

      do {

        observation = try Observation(
          findings,
          tool: ObservationTool(name: "insteon", version: version),
          catalogVersion: names.catalogVersion,
          note: options.note,
          observedOn: Date()
        )

      } catch {

        throw CommandFailure(description: "\(error)")

      }

      let delivery = try ObservationDelivery.deliver(observation.json(), to: options.outputPath, files: DiskFiles())

      for line in ObservationText.summary(observation) {

        Output.note(line)

      }

      if case let .standardOutput(json) = delivery {

        Output.line(json)

      }

      for line in ObservationText.closing(delivery) {

        Output.note(line)

      }

    }

  }

  /// Creates files on disk, never over one that is there.
  private struct DiskFiles: ObservationFiles {

    func createFile(_ data: Data, at path: String) throws -> Bool {

      do {

        try data.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)

        return true

      } catch let error as CocoaError where error.code == .fileWriteFileExists {

        return false

      }

    }

  }

  /// A device and the catalog, as the observation asks them.
  private struct DeviceSource: ObservationSource {

    let device: Device
    let network: DeviceNetwork
    let names: ProductNames

    func identify() async throws -> ObservationReply<ObservedIdentity> {

      do {

        let identification = try await network.identify(device.address)

        return .answered(ObservedIdentity(
          engine: identification.engine,
          acceptsModem: identification.acceptsModem,
          category: identification.identity?.category,
          subcategory: identification.identity?.subcategory,
          firmwareVersion: identification.identity?.firmwareVersion
        ))

      } catch {

        return try .classify(error)

      }

    }

    func productData() async throws -> ObservationReply<DeviceProductData> {

      do {

        guard let data = try await network.productData(of: device.address) else {

          return .silent

        }

        return .answered(data)

      } catch {

        return try .classify(error)

      }

    }

    func productName(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String? {

      names.name(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)

    }

    func readStatus() async throws -> ObservationReply<Void>? {

      do {

        _ = try await device.status()

        return .answered(())

      } catch is DeviceControlError {

        return nil

      } catch {

        return try .classify(error)

      }

    }

    func readOperatingFlags() async throws -> ObservationReply<[UInt8]>? {

      do {

        let reading = try await device.readSettings(includingAdvanced: true)
        let entries = reading.entries

        guard !entries.isEmpty else {

          return nil

        }

        let flags = reading.operatingFlags.sorted { (left, right) -> Bool in left.key.rawValue < right.key.rawValue }

        if flags.isEmpty, entries.allSatisfy({ $0.raw == nil }) {

          return .silent

        }

        return .answered(flags.map(\.value))

      } catch is DeviceSettingError {

        return nil
      } catch is DeviceControlError {

        return nil

      } catch {

        return try .classify(error)

      }

    }

  }

}
