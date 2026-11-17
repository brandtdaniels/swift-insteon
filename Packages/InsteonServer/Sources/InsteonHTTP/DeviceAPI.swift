import Foundation
import Hummingbird
import InsteonService
import ServiceLifecycle

/// JSON and event-stream presentation of a service's three roles.
struct DeviceAPI<Service: InsteonServiceAPI>: Sendable {
  let service: Service
  private let policy: EventStreamPolicy
  private let clock: any Clock<Duration>
  private let registry: EventStreamRegistry

  init(service: Service, policy: EventStreamPolicy = .standard, clock: any Clock<Duration> = ContinuousClock()) {
    self.service = service
    self.policy = policy
    self.clock = clock
    self.registry = EventStreamRegistry(limit: policy.maximumStreams)
  }

  func devices() async throws -> Response {
    try json(DeviceListDTO(try await service.devices()))
  }

  func command(_ request: Request, address: String?) async throws -> Response {
    let input = try await HTTPCommand.json(request)
    let receipt = try await service.execute(input.serviceCommand(address: address))
    return try json(ReceiptDTO(receipt))
  }

  private enum StreamItem: Sendable {
    case event(ServiceEvent)
    case keepalive
  }

  func events() async -> Response {
    let body = ResponseBody { writer in
      do {
        // A response can be discarded without its body being written.
        // Subscribe only while a structured producer can own and cancel the reader.
        let events = await service.events()
        let lease = await registry.admit()
        let policy = self.policy, clock = self.clock
        do {
          try await withThrowingTaskGroup(of: Void.self) { group in
            let (buffered, continuation) = AsyncThrowingStream<StreamItem, any Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
            group.addTask {
              do {
                // Long-lived sources must stop during graceful HTTP shutdown, even when
                // no device event arrives. Keep the non-Sendable HTTP writer in its task.
                try await cancelWhenGracefulShutdown {
                  for try await event in events {
                    try Task.checkCancellation()
                    switch continuation.yield(.event(event)) {
                    case .enqueued: break
                    case .dropped: throw EventStreamFailure()
                    case .terminated: return
                    @unknown default: throw EventStreamFailure()
                    }
                  }
                }
                continuation.finish()
              } catch {
                continuation.finish(throwing: error)
              }
            }
            // The keepalive also ends the stream at its maximum lifetime, which releases the
            // connection of a client that vanished without closing it.
            group.addTask {
              let beats = max(Int(policy.maximumLifetime / policy.heartbeatInterval), 1)
              for beat in 1...beats {
                do { try await clock.sleep(for: policy.heartbeatInterval) } catch { return }
                if beat == beats { continuation.finish(); return }
                // A full buffer drops a keepalive, which the pending events already replace.
                _ = continuation.yield(.keepalive)
              }
            }
            group.addTask {
              var evictions = lease.evictions.makeAsyncIterator()
              if await evictions.next() != nil { continuation.finish() }
            }
            defer { group.cancelAll() }
            try await writer.write(ByteBuffer(string: ": connected\n\n"))
            let encoder = JSONEncoder()
            for try await item in buffered {
              try Task.checkCancellation()
              switch item {
              case let .event(event):
                let data = try encoder.encode(EventDTO(event))
                try await writer.write(ByteBuffer(string: "data: " + String(decoding: data, as: UTF8.self) + "\n\n"))
              case .keepalive:
                try await writer.write(ByteBuffer(string: ": keepalive\n\n"))
              }
            }
            try await writer.finish(nil)
          }
        } catch {
          await registry.release(lease)
          throw error
        }
        await registry.release(lease)
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
