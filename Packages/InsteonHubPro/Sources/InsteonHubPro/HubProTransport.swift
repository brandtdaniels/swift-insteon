import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking
import InsteonProtocol

/// Reads a Hub Pro's devices and runs commands on them, one request at a time.
///
/// The transport asks for the Hub Pro's settings, its device list, every device's level and one
/// device's description, and runs the commands of ``HubProCommand``. It has no way to add or
/// remove a device, change a device's links or start an update.
///
/// ```swift
/// let unit = HubProTransport(host: "192.168.1.20")
///
/// for device in try await unit.devices() where !device.isModem {
///   print(device.name, try await unit.perform(.statusRequest, on: device.address).onLevel ?? 0)
/// }
/// ```
///
/// The Hub Pro can stop answering under load, so a request waits for the one before it to end.
/// Requests are asked for with a `GET`, and again with a `POST` when the Hub Pro answers
/// `404 Not Found` or `405 Method Not Allowed`; the transport then keeps using the method that
/// worked. Each request may take ``HubProTransport/defaultTimeout`` in all, unless another is
/// given.
public actor HubProTransport {

  /// How long to wait for an answer by default: 15 seconds.
  public static let defaultTimeout: Duration = .seconds(15)

  private let client: HubProClient
  private var method = "GET"
  private var isBusy = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  /// Creates a transport for a Hub Pro.
  ///
  /// - Parameters:
  ///   - host: The Hub Pro's host name or IP address.
  ///   - port: The port of its HTTP interface. Defaults to ``HubProClient/defaultPort``.
  ///   - httpClient: The client to send requests with. Defaults to
  ///     `URLSessionHTTPClient.localNetwork()`.
  ///   - timeout: How long to wait for each answer, in all. Defaults to ``defaultTimeout``.
  public init(
    host: String,
    port: Int = HubProClient.defaultPort,
    httpClient: any HTTPClient = URLSessionHTTPClient.localNetwork(),
    timeout: Duration = HubProTransport.defaultTimeout
  ) {

    self.client = HubProClient(host: host, port: port, httpClient: httpClient, timeout: timeout)

  }

  /// How many requests wait for the one in flight.
  var waitingRequests: Int {

    waiting.count

  }

  /// Reads the Hub Pro's network settings and software versions.
  ///
  /// - Throws: ``HubProError`` or the client's error.
  public func settings() async throws -> HubProSettings {

    try await exclusively { try await self.client.settings() }

  }

  /// Lists the devices the Hub Pro knows, with its own modem.
  ///
  /// - Throws: ``HubProError/malformedResponse`` if the answer isn't a list, or another
  ///   ``HubProError`` or the client's error.
  public func devices() async throws -> [HubProListedDevice] {

    let objects = try await array("/insteon/list")

    return try objects.map { object in

      guard let address = (object["device"] as? String).flatMap(InsteonAddress.init), let name = object["name"] as? String else {

        throw HubProError.malformedResponse

      }

      let type = object["deviceType"] as? String ?? ""

      return HubProListedDevice(address: address, name: name, deviceType: type, isModem: name == "(PLM)")

    }

  }

  /// Reads every device's level.
  ///
  /// - Returns: The level from 0 through 255, by device address.
  /// - Throws: ``HubProError/malformedResponse`` if the answer isn't a list of levels, or another
  ///   ``HubProError`` or the client's error.
  public func levels() async throws -> [InsteonAddress: UInt8] {

    var levels: [InsteonAddress: UInt8] = [:]

    for object in try await array("/insteon/status") {

      guard let address = (object["device"] as? String).flatMap(InsteonAddress.init), let level = Self.byte(object["OnLevel"]) else {

        throw HubProError.malformedResponse

      }

      levels[address] = level

    }

    return levels

  }

  /// Reads what the Hub Pro reports about a device.
  ///
  /// - Parameter address: The device's address.
  /// - Throws: ``HubProControlError/unknownDevice(_:)`` for a device the Hub Pro doesn't know,
  ///   ``HubProError/malformedResponse`` if the answer can't be read, or another ``HubProError``
  ///   or the client's error.
  public func describe(_ address: InsteonAddress) async throws -> HubProDescription {

    let object = try await dictionary("/insteon/describe", [URLQueryItem(name: "device", value: address.description)], device: address)

    let commands: [HubProDescription.Command] = (object["commands"] as? [[String: Any]] ?? []).compactMap { entry in

      guard let name = entry["name"] as? String else {

        return nil

      }

      return HubProDescription.Command(name: name, parameters: entry["parameters"] as? [String] ?? [])

    }

    return HubProDescription(
      address: address,
      name: object["name"] as? String ?? "",
      deviceType: object["deviceType"] as? String ?? "",
      category: Self.byte(object["devCat"]),
      subcategory: Self.byte(object["subCat"]),
      firmwareVersion: Self.byte(object["firmwareVersion"]),
      sku: object["sku"] as? String,
      commands: commands
    )

  }

  /// Runs a command on a device.
  ///
  /// A command is never sent again after an answer that doesn't confirm it.
  ///
  /// - Parameters:
  ///   - command: The command.
  ///   - address: The device's address.
  /// - Returns: What the Hub Pro answered.
  /// - Throws: ``HubProControlError`` if the Hub Pro doesn't know the device, the device doesn't
  ///   support the command, or the answer doesn't say `successful`; another ``HubProError`` or the
  ///   client's error, such as `URLError.timedOut` when no answer comes.
  public func perform(_ command: HubProCommand, on address: InsteonAddress) async throws -> HubProCommandResult {

    var items = [URLQueryItem(name: "device", value: address.description), URLQueryItem(name: "key", value: command.key)]

    if let level = command.level {

      items.append(URLQueryItem(name: HubProCommand.levelParameter, value: String(level)))

    }

    let object = try await dictionary("/insteon/command", items, device: address, command: command.key)

    guard object["result"] as? String == "successful" else {

      throw HubProControlError.notConfirmed

    }

    return HubProCommandResult(onLevel: Self.byte(object["OnLevel"]), linkDelta: Self.byte(object["LinkDelta"]))

  }

  // MARK: - Requests

  private func array(_ path: String) async throws -> [[String: Any]] {

    let body = try await get(path, [])

    guard let objects = (try? JSONSerialization.jsonObject(with: body)) as? [[String: Any]] else {

      try Self.reject(body)

      throw HubProError.malformedResponse

    }

    return objects

  }

  private func dictionary(_ path: String, _ items: [URLQueryItem], device: InsteonAddress, command: String? = nil) async throws -> [String: Any] {

    let body = try await get(path, items)

    guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {

      throw HubProError.malformedResponse

    }

    if let message = object["error"] as? String, !message.isEmpty {

      if message.hasPrefix("Key '"), message.hasSuffix("' not found.") {

        throw HubProControlError.unknownDevice(device)

      }

      if message.contains("does not support command"), let command {

        throw HubProControlError.notSupported(command: command, device: device)

      }

      throw HubProError.rejected(message)

    }

    return object

  }

  /// Throws the error an answer reports, if it is an object with one.
  private static func reject(_ body: Data) throws {

    if let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let message = object["error"] as? String, !message.isEmpty {

      throw HubProError.rejected(message)

    }

  }

  private func get(_ path: String, _ items: [URLQueryItem]) async throws -> Data {

    try await exclusively {

      var response = try await self.client.send(self.method, path, queryItems: items)

      if self.method == "GET", response.statusCode == 404 || response.statusCode == 405 {

        let retried = try await self.client.send("POST", path, queryItems: items)

        if retried.statusCode == 200 {

          self.method = "POST"

        }

        response = retried

      }

      guard response.statusCode == 200 else {

        throw HubProError.unexpectedStatus(response.statusCode)

      }

      return response.body

    }

  }

  /// A byte from a JSON number, or `nil` for anything else or a number out of range.
  private static func byte(_ value: Any?) -> UInt8? {

    (value as? Int).flatMap { UInt8(exactly: $0) }

  }

  /// Runs `work` when no other request is running, and in the order requests were made.
  private func exclusively<Value>(_ work: () async throws -> Value) async throws -> Value {

    if isBusy {

      await withCheckedContinuation { waiting.append($0) }

    } else {

      isBusy = true

    }

    defer {

      if waiting.isEmpty {

        isBusy = false

      } else {

        waiting.removeFirst().resume()

      }

    }

    try Task.checkCancellation()

    return try await work()

  }

}
