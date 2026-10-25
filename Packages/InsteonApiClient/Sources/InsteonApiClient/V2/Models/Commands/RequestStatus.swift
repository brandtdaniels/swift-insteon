public struct StatusResponse {

  public var identifier: Int

  public var status: RequestStatus

  public var link: String

}

// MARK: - Decodable

extension StatusResponse: Decodable {

  private enum CodingKeys: String, CodingKey {

    case identifier = "id"

    case status

    case link

  }

}

public enum RequestStatus: String, Decodable {

  case pending

  case succeeded

  case failed

}
