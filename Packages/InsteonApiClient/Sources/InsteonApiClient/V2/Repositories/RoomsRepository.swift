//
//  RoomsRepository.swift
//  
//
//  Created by Brandt Daniels on 6/27/20.
//

import Foundation

public struct RoomsRepository {

  private let apiClient: ApiClientProtocol

  public init(_ apiClient: ApiClientProtocol) {

    self.apiClient = apiClient

  }

}

// MARK: - RoomsRepositoryProtocol

extension RoomsRepository: RoomsRepositoryProtocol {

  public func create(_ room: Room, completion: @escaping (Result<RoomId, ApiClientError>) -> Void) {

    var data: Data

    do {

      data = try JSONEncoder().encode(room)

    } catch {

      completion(.failure(.encoding(message: error.localizedDescription)))

      return
      
    }

    apiClient.request(CreateRoom(data), completion: completion)

  }

}
