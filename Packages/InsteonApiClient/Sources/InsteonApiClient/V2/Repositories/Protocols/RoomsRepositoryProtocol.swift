//
//  RoomsRepositoryProtocol.swift
//  
//
//  Created by Brandt Daniels on 6/27/20.
//

import Foundation

public protocol RoomsRepositoryProtocol {

  func create(_ room: Room, completion: @escaping (Result<RoomId, ApiClientError>) -> Void)

}
