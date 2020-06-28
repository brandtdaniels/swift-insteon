public struct SceneId {

  public var identifier: Int

  public init(_ identifier: Int) {

    self.identifier = identifier

  }

}

// MARK: - Equatable

extension SceneId: Equatable {}

// MARK: - Codable

extension SceneId: Codable {

  private enum CodingKeys: String, CodingKey {

    case identifier = "SceneID"

  }

}
