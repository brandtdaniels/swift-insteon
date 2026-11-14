import Foundation
import Hummingbird
import InsteonService

/// JSON and event-stream presentation of a service's three roles.
struct DeviceAPI<Service: InsteonServiceAPI>: Sendable {
  let service: Service

  func devices() async throws -> Response {
    try json(DeviceListDTO(try await service.devices()))
  }

  func command(_ request: Request, address: String?) async throws -> Response {
    let input = try await HTTPCommand.json(request)
    let receipt = try await service.execute(input.serviceCommand(address: address))
    return try json(ReceiptDTO(receipt))
  }

  func events() async -> Response {
    let events = await service.events()
    let body = ResponseBody { writer in
      do {
        try await writer.write(ByteBuffer(string: ": connected\n\n"))
        let encoder = JSONEncoder()
        for try await event in events {
          try Task.checkCancellation()
          let data = try encoder.encode(EventDTO(event))
          try await writer.write(ByteBuffer(string: "data: " + String(decoding: data, as: UTF8.self) + "\n\n"))
        }
        try await writer.finish(nil)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // A streaming response has started. End it without exposing provider diagnostics.
        throw EventStreamFailure()
      }
    }
    return Response(status: .ok, headers: [.contentType: "text/event-stream"], body: body)
  }

  private func json(_ value: some Encodable) throws -> Response {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try encoder.encode(value))))
  }
}

private struct EventStreamFailure: Error {}
