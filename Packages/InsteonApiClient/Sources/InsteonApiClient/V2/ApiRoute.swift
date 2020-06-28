import Foundation

public enum ApiRoute {

  public enum Endpoint {

    public typealias alertId = Int

    public typealias commandId = Int

    public typealias contactId = Int

    public typealias deviceId = Int

    public typealias houseId = Int

    public typealias roomId = Int

    case alert(alertId)

    case commands

    case command(commandId)

    case contact(contactId)

    case contacts

    case device(deviceId)

    case houses

    case house(houseId)

    case houseAlerts(houseId)

    case houseCameras(houseId)

    case houseDevices(houseId)

    case houseRooms(houseId)

    case houseScenes(houseId)

    case houseStream(houseId)

    case room(roomId)

    case rooms

    public var urlComponents: URLComponents {

      var urlComponents = URLComponents()

      let propertiesQueryItem = URLQueryItem(name: "properties", value: "all")

      switch self {

      case let .alert(alertId):

        urlComponents.path = "/alerts/\(alertId)"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case .commands:

        urlComponents.path = "/commands"

        return urlComponents

      case let .command(commandId):

        urlComponents.path = "/commands/\(commandId)"

        return urlComponents

      case let .contact(contactId):

        urlComponents.path = "/contacts/\(contactId)"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case .contacts:

        urlComponents.path = "/contacts"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case let .device(deviceId):

        urlComponents.path = "/devices/\(deviceId)"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case .houses:

        urlComponents.path = "/houses"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case let .house(id):

        urlComponents.path = "/houses/\(id)"

        return urlComponents

      case let .houseAlerts(houseId):

        urlComponents.path = "/houses/\(houseId)/alerts"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case let .houseCameras(houseId):

        urlComponents.path = "/houses/\(houseId)/cameras"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case let .houseDevices(houseId):

        urlComponents.path = "/houses/\(houseId)/devices"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case let .houseRooms(houseId):

        urlComponents.path = "/houses/\(houseId)/rooms"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case let .houseScenes(houseId):

        urlComponents.path = "/houses/\(houseId)/scenes"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      case let .houseStream(houseId):

        urlComponents.path = "/houses/\(houseId)/stream"

        return urlComponents

      case let .room(id):

        urlComponents.path = "/rooms/\(id)"

        return urlComponents

      case .rooms:

        urlComponents.path = "/rooms"

        urlComponents.queryItems = [propertiesQueryItem]

        return urlComponents

      }

    }

  }

  case endpoint(Endpoint)

  private var baseUrlComponents: URLComponents {

    var urlComponents = URLComponents()

    urlComponents.scheme = "https"
    urlComponents.host = "connect.insteon.com"
    urlComponents.path = "/api/v2"

    return urlComponents

  }

  public var url: URL? {

    switch self {

    case .endpoint(let endpoint):

      var urlComponents = baseUrlComponents

      urlComponents.path += endpoint.urlComponents.path

      urlComponents.queryItems = endpoint.urlComponents.queryItems
      
      return urlComponents.url

    }

  }

}
