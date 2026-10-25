public struct CommandResult {

  public var identifier: Int

  public var command: OriginalCommand

  public var status: ResultStatus

  public var response: DeviceResponse?

}

// MARK: - Decodable

extension CommandResult: Decodable {

  private enum CodingKeys: String, CodingKey {

    case identifier = "id"

    case command

    case status

    case response

  }

}

// MARK: - Decodable

public struct OriginalCommand: Decodable {

  public var deviceIdentifier: Int

  public var command: DeviceCommand

  private enum CodingKeys: String, CodingKey {

    case deviceIdentifier = "device_id"

    case command

  }

}

public enum ResultStatus: String, Decodable {

  case pending
  
  case succeeded

  case failed

}

public struct DeviceResponse: Decodable {

  public var level: Int

}
