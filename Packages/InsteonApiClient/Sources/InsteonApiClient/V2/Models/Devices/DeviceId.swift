public struct DeviceId {

  public var identifier: Int

  public init(_ identifier: Int) {

    self.identifier = identifier
    
  }

}

// MARK: - Equatable

extension DeviceId: Equatable {}

// MARK: - Codable

extension DeviceId: Codable {

  private enum CodingKeys: String, CodingKey {

    case identifier = "DeviceID"

  }

}
