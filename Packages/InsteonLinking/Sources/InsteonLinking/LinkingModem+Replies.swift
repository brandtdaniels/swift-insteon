import InsteonModem
import InsteonProtocol

extension LinkingModem {

  /// Starts listening to the modem, runs `start`, then waits for the first reply `match`
  /// reads a value from, or for `timeout` to pass.
  ///
  /// Listening starts before `start` runs, so a reply to what it sends can't be missed. This
  /// is how to wait for what a device or the modem sends after a request: a SET Button
  /// Pressed broadcast after ID Request, a Product Data Response after Product Data Request,
  /// or the modem's report of a link after Start ALL-Linking.
  ///
  /// ```swift
  /// let data = try await modem.firstReply(
  ///   within: .seconds(3),
  ///   after: { _ = try await modem.request(StandardMessage(to: lamp, command: StandardDirectCommand.productDataRequest), timeout: .seconds(2)) },
  ///   matching: { reply in
  ///     guard case let .messageReceived(message) = reply, message.sender == lamp else { return nil }
  ///     return ProductData(message)
  ///   }
  /// )
  /// ```
  ///
  /// - Parameters:
  ///   - timeout: How long to wait for a reply once `start` has returned.
  ///   - clock: The clock that times the wait. Defaults to a `ContinuousClock`; tests can pass
  ///     a clock they control.
  ///   - start: Sends what the reply answers. Its errors are thrown before any waiting.
  ///   - match: Reads a value from a reply, or returns `nil` to keep waiting. An error it
  ///     throws ends the wait and is thrown.
  /// - Returns: The value read from the first matching reply, or `nil` if none arrived in
  ///   time.
  /// - Throws: The errors of `start` and `match`, `ModemError.connectionClosed` if the modem
  ///   closes first, or `CancellationError` if the task is canceled.
  public func firstReply<Value: Sendable>(
    within timeout: Duration,
    clock: any Clock<Duration> = ContinuousClock(),
    after start: () async throws -> Void,
    matching match: @escaping @Sendable (ModemReply) throws -> Value?
  ) async throws -> Value? {

    let stream: AsyncStream<ModemReply> = await self.replies()

    try await start()

    return try await withThrowingTaskGroup(of: Value?.self) { group in

      group.addTask {

        for await reply in stream {

          if let value = try match(reply) {

            return value

          }

        }

        // The stream ends early only when this task is canceled or the modem closes.
        try Task.checkCancellation()

        throw ModemError.connectionClosed

      }

      group.addTask {

        try await clock.sleep(for: timeout)

        return nil

      }

      defer { group.cancelAll() }

      let first: Value?? = try await group.next()

      return first ?? nil

    }

  }

}
