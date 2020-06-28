//
//  RoomsRepository.swift
//  
//
//  Created by Brandt Daniels on 6/27/20.
//

import Foundation

public struct RoomsRepository {

  private let apiClient: ApiClientProtocol

  init(_ apiClient: ApiClientProtocol) {

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

    let request = CreateRoom(data)

    apiClient.request(request) { result in

      switch result {

      case let .failure(apiClientError):

        completion(.failure(apiClientError))

      case let .success(response):

        completion(.success(response!))

      }

    }

  }

}
