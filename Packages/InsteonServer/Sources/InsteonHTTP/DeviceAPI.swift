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

  private let idempotency: IdempotencyStore

  init(service: Service, policy: EventStreamPolicy = .standard, clock: any Clock<Duration> = ContinuousClock(), idempotency: IdempotencyStore = IdempotencyStore(), registry: EventStreamRegistry? = nil) {
    self.service = service
    self.idempotency = idempotency
    self.policy = policy
    self.clock = clock
    self.registry = registry ?? EventStreamRegistry(limit: policy.maximumStreams)
  }

  func devices() async throws -> Response {
    // Read the list before the state: a modem that goes away in between marks it stale.
    let devices = try await service.devices()
    return try json(DeviceListDTO(devices, modem: await service.health().modem))
  }

  func health() async throws -> Response {
    try json(HealthDTO(await service.health()))
  }

  /// Runs a command. With an `Idempotency-Key`, a repeat of the same command returns the recorded
  /// outcome and sends nothing.
  func command(_ request: Request, address: String?) async throws -> Response {
    let input = try await HTTPCommand.json(request)
    let command = try input.serviceCommand(address: address)
    let key = try IdempotencyKey(header: request.headers[values: .idempotencyKey])
    guard let key else {
      return try Self.response(await run(command))
    }
    let (outcome, replayed) = try await idempotency.perform(scope: .gateway, key: key.value, fingerprint: Self.fingerprint(command)) { await run(command) }
    var response = try Self.response(outcome, replayed: replayed)
    if replayed { response.headers[.idempotentReplay] = "true" }
    return response
  }

  private func run(_ command: ServiceCommand) async -> IdempotentOutcome {
    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      return .response(.ok, try encoder.encode(ReceiptDTO(try await service.execute(command))))
    } catch {
      return .failure(HTTPFailure(CommandFailure(action: command.action, underlying: error)))
    }
  }

  /// Names a command by what it asks for, not by how the request spelled it: the same action and
  /// level on the same device are the same command whatever the JSON's key order or spacing.
  private static func fingerprint(_ command: ServiceCommand) -> String {
    let canonical = "POST\n/api/v1/devices/\(command.address)/commands\n\(command.action)\n\(command.levelPercent.map(String.init) ?? "")"
    return SecureDigest.of(canonical).map { String(format: "%02x", $0) }.joined()
  }

  private static func response(_ outcome: IdempotentOutcome, replayed: Bool = false) throws -> Response {
    switch outcome {
    case let .response(status, body):
      return Response(status: status, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: body)))
    case let .failure(failure):
      throw OutcomeFailure(failure: failure, replayed: replayed)
    }
  }

  private enum StreamItem: Sendable {
    case event(SequencedItem)
    case keepalive
  }

  /// - Parameter cursor: Where the client left off, from `Last-Event-ID` or the `lastEventId` query
  ///   parameter. The stream starts with the events it missed, or with a `gap` frame.
  func events(resumingAfter cursor: EventCursor? = nil) async -> Response {
    // The principal is read here, while the request is being handled; the body runs later.
    let clientID = RequestPrincipal.current?.clientID
    let body = ResponseBody { writer in
      do {
        // A response can be discarded without its body being written.
        // Subscribe only while a structured producer can own and cancel the reader.
        let events = await service.sequencedEvents(after: cursor)
        let lease = await registry.admit(clientID: clientID)
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
              case let .event(sequenced):
                let frame: (id: String, data: Data)
                switch sequenced {
                case let .event(event, position): frame = (position.token, try encoder.encode(EventDTO(event, at: position)))
                case let .gap(reason, current): frame = (current.token, try encoder.encode(GapDTO(reason: reason, current: current)))
                case let .position(current):
                  // An id with no data sets the browser's place without dispatching an event.
                  try await writer.write(ByteBuffer(string: "id: " + current.token + "\n\n"))
                  continue
                }
                try await writer.write(ByteBuffer(string: "id: " + frame.id + "\ndata: " + String(decoding: frame.data, as: UTF8.self) + "\n\n"))
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
