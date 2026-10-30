import Foundation
import InsteonProtocol

/// Keeps a ``DeviceRegistry``'s devices in a JSON file, readable only by the current user.
///
/// The file names its format's version, and holds each device's identity by its address:
///
/// ```json
/// {
///   "devices" : {
///     "1A.2B.3C" : {
///       "identity" : { "category" : "0x02", "firmwareVersion" : "0x41", "subcategory" : "0x2A" }
///     }
///   },
///   "version" : 1
/// }
/// ```
///
/// The store also reads a file with no version whose devices are bare identities, as the
/// `insteon` command's identity cache is written:
///
/// ```json
/// {
///   "devices" : {
///     "1A.2B.3C" : { "category" : "0x02", "firmwareVersion" : "0x41", "subcategory" : "0x2A" }
///   }
/// }
/// ```
///
/// and writes it back in the versioned format the next time it saves. A device entry that
/// doesn't read as an address and an identity is left out, so one bad entry doesn't lose the
/// others.
///
/// Saving writes a temporary file of its own, readable only by the current user where the platform
/// has POSIX permissions, then moves it into place, so a reader never sees half a file. A
/// directory the store creates for the file is readable only by the current user. The store
/// never replaces a file it can't read, such as one written in a newer format, so nothing in it
/// is lost. Two processes that save at the same time each write the devices they hold, so the
/// last one to save wins.
///
/// ```swift
/// let store = JSONFileDeviceRegistryStore(fileURL: url)
/// let registry = DeviceRegistry(catalog: catalog, snapshot: try store.load())
/// ```
public struct JSONFileDeviceRegistryStore: DeviceRegistryStore {

  /// The version of the format the store writes, and the newest it reads.
  public static let formatVersion: Int = 1

  /// The file's location.
  public let fileURL: URL

  /// Creates a store that keeps devices in a file.
  ///
  /// - Parameter fileURL: The file's location. The file and its directory needn't exist yet.
  public init(fileURL: URL) {

    self.fileURL = fileURL

  }

  /// Reads the devices in the file.
  ///
  /// - Returns: The devices, or an empty snapshot if there's no file.
  /// - Throws: ``DeviceRegistryStoreError/unreadableFile`` if something other than a regular
  ///   file is there or it can't be read, ``DeviceRegistryStoreError/malformedContents`` if it
  ///   isn't a registry file, and ``DeviceRegistryStoreError/unsupportedVersion(_:)`` if it's
  ///   in a newer format.
  public func load() throws -> DeviceRegistrySnapshot {

    guard let data = try contents() else {

      return DeviceRegistrySnapshot()

    }

    return try Self.snapshot(json: data)

  }

  /// Replaces the file with the devices in a snapshot.
  ///
  /// A file that's already there is replaced only if it reads as a registry file, so a file
  /// that ``load()`` can't read is never lost.
  ///
  /// - Parameter snapshot: The devices to keep.
  /// - Throws: The error ``load()`` throws for a file already there that it can't read, or
  ///   ``DeviceRegistryStoreError/writeFailed(code:)`` if the file couldn't be written, which
  ///   leaves the file that was there as it was.
  public func save(_ snapshot: DeviceRegistrySnapshot) throws {

    _ = try load()

    let data: Data = try Self.json(snapshot)

    try PrivateFile.replace(path, with: data)

  }

  /// Reads devices from a registry file's contents, in the versioned format or as bare
  /// identities with no version.
  ///
  /// - Parameter json: The file's contents.
  /// - Returns: The devices. An entry that doesn't read as an address and an identity is left
  ///   out.
  /// - Throws: ``DeviceRegistryStoreError/malformedContents`` if the contents aren't a registry
  ///   file, and ``DeviceRegistryStoreError/unsupportedVersion(_:)`` if they're in a newer
  ///   format.
  public static func snapshot(json: Data) throws -> DeviceRegistrySnapshot {

    let decoder = JSONDecoder()
    let header: Header

    do {

      header = try decoder.decode(Header.self, from: json)

    } catch {

      throw DeviceRegistryStoreError.malformedContents

    }

    let identities: [String: ReportedIdentity]

    if let version = header.version {

      guard version <= formatVersion else {

        throw DeviceRegistryStoreError.unsupportedVersion(version)

      }

      guard version == formatVersion else {

        throw DeviceRegistryStoreError.malformedContents

      }

      let file: VersionedFile = try decode(VersionedFile.self, from: json, with: decoder)
      identities = file.devices.compactMapValues { (entry: Lenient<StoredDevice>) -> ReportedIdentity? in entry.value?.identity }

    } else {

      let file: UnversionedFile = try decode(UnversionedFile.self, from: json, with: decoder)
      identities = file.devices.compactMapValues { (entry: Lenient<ReportedIdentity>) -> ReportedIdentity? in entry.value }

    }

    var snapshot = DeviceRegistrySnapshot()

    // In key order, so two keys for one address, such as "1A.2B.3C" and "1a2b3c", always
    // read the same way.
    for key in identities.keys.sorted() {

      guard let address = InsteonAddress(key), let identity = identities[key] else {

        continue

      }

      snapshot.identities[address] = identity

    }

    return snapshot

  }

  /// A snapshot as a registry file's contents, in the versioned format, with the devices in
  /// address order.
  ///
  /// - Parameter snapshot: The devices.
  /// - Returns: The file's contents.
  /// - Throws: `EncodingError` if the snapshot can't be encoded.
  public static func json(_ snapshot: DeviceRegistrySnapshot) throws -> Data {

    var devices: [String: StoredDevice] = [:]

    for (address, identity) in snapshot.identities {

      devices["\(address)"] = StoredDevice(identity: identity)

    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    return try encoder.encode(VersionedFile(version: formatVersion, devices: devices))

  }

  // MARK: - The file

  private var path: String {

    fileURL.path(percentEncoded: false)

  }

  /// The file's contents, or `nil` if there's no file.
  private func contents() throws -> Data? {

    let attributes: [FileAttributeKey: Any]

    do {

      attributes = try FileManager.default.attributesOfItem(atPath: path)

    } catch {

      guard FileManager.default.fileExists(atPath: path) else {

        return nil

      }

      throw DeviceRegistryStoreError.unreadableFile

    }

    // Only a regular file is read, so a named pipe can't block the caller.
    guard (attributes[.type] as? FileAttributeType) == .typeRegular, let data = FileManager.default.contents(atPath: path) else {

      throw DeviceRegistryStoreError.unreadableFile

    }

    return data

  }

  private static func decode<File: Decodable>(_ type: File.Type, from json: Data, with decoder: JSONDecoder) throws -> File {

    do {

      return try decoder.decode(type, from: json)

    } catch {

      throw DeviceRegistryStoreError.malformedContents

    }

  }

  // MARK: - The format

  /// The part of every format that says which format it is.
  private struct Header: Decodable {

    var version: Int?

  }

  /// The versioned format.
  private struct VersionedFile: Codable {

    var version: Int

    var devices: [String: Lenient<StoredDevice>]

    init(version: Int, devices: [String: StoredDevice]) {

      self.version = version
      self.devices = devices.mapValues { (device: StoredDevice) -> Lenient<StoredDevice> in Lenient(device) }

    }

  }

  /// A device in the versioned format.
  private struct StoredDevice: Codable {

    var identity: ReportedIdentity

  }

  /// The format with no version, whose devices are bare identities.
  private struct UnversionedFile: Decodable {

    var devices: [String: Lenient<ReportedIdentity>]

  }

  /// A value that decodes as `nil` rather than failing the whole file when it doesn't read.
  private struct Lenient<Value: Codable>: Codable {

    var value: Value?

    init(_ value: Value) {

      self.value = value

    }

    init(from decoder: any Decoder) throws {

      value = try? Value(from: decoder)

    }

    func encode(to encoder: any Encoder) throws {

      try value.encode(to: encoder)

    }

  }

}

/// Why a ``JSONFileDeviceRegistryStore`` couldn't read or write its file.
///
/// The errors never include the file's contents.
public enum DeviceRegistryStoreError: Error, Hashable, Sendable, CustomStringConvertible {

  /// Something other than a regular file is at the file's path, or the file couldn't be read.
  case unreadableFile

  /// The file isn't a registry file, such as one that isn't JSON or has no devices.
  case malformedContents

  /// The file is in a newer format than the store reads, with this version.
  case unsupportedVersion(Int)

  /// The file couldn't be written, with the system's error code, such as `EACCES`.
  case writeFailed(code: Int32)

  /// The error as a sentence.
  public var description: String {

    switch self {
    case .unreadableFile:
      "The device registry file couldn't be read."
    case .malformedContents:
      "The device registry file isn't in a format the store reads, so it's left as it is."
    case let .unsupportedVersion(version):
      "The device registry file is in format \(version), newer than format \(JSONFileDeviceRegistryStore.formatVersion), which the store reads, so it's left as it is."
    case let .writeFailed(code):
      "The device registry file couldn't be written (error \(code))."
    }

  }

}
