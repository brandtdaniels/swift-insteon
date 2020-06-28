public struct CameraId {

  public var identifier: Int

  public init(_ identifier: Int) {

    self.identifier = identifier

  }

}

// MARK: - Equatable

extension CameraId: Equatable {}

// MARK: - Codable

extension CameraId: Codable {

  private enum CodingKeys: String, CodingKey {

    case identifier = "CameraID"

  }

}
