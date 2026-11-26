import InsteonService

/// One connection to a home, over whichever of its paths answers first.
///
/// It tries its paths in order, keeps the one that opens, and gives the same calls whichever it
/// is, so a person at home and a person away use it the same way. A read that loses the path is
/// asked again after the paths are tried afresh, once. A command that may have been sent is never
/// asked again: it throws ``HomeError/interrupted(path:)``, the path is dropped, and the next call
/// opens one afresh. A command that was never sent, because its path couldn't be reached, moves on
/// to the next path.
public actor HomeConnection: DeviceQuerying, DeviceCommanding {

  private let paths: [any HomePath]
  private var open: (name: String, calls: any HomeCalls)?

  /// The name of the path in use, or `nil` before the first call and after a path is lost.
  public var currentPath: String? { open?.name }

  /// Creates a connection over paths, the most preferred first.
  public init(paths: [any HomePath]) {
    self.paths = paths
  }

  public func devices() async throws -> [ServiceDevice] {
    var lastLost: HomeError?
    for _ in 0..<2 {
      let (name, calls) = try await reach()
      do {
        return try await calls.devices()
      } catch HomePathError.interrupted {
        open = nil
        lastLost = .interrupted(path: name)
      } catch HomePathError.notReached {
        open = nil
        lastLost = .interrupted(path: name)
      }
    }
    throw lastLost ?? HomeError.noPathReached([])
  }

  public func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    for _ in 0..<2 {
      let (name, calls) = try await reach()
      do {
        return try await calls.execute(command)
      } catch HomePathError.interrupted {
        open = nil
        throw HomeError.interrupted(path: name)
      } catch HomePathError.notReached {
        // Nothing was sent: the next path can take it.
        open = nil
      }
    }
    throw HomeError.noPathReached([])
  }

  /// The path in use, or the first that opens.
  private func reach() async throws -> (name: String, calls: any HomeCalls) {
    if let open { return open }
    var failures: [PathFailure] = []
    for path in paths {
      do {
        let calls = try await path.open()
        // A call that was waiting on another opening may have set it already.
        if let open { return open }
        open = (path.name, calls)
        return (path.name, calls)
      } catch HomePathError.notReached(let reason) {
        failures.append(PathFailure(path: path.name, reason: reason))
      } catch HomePathError.unauthorized {
        throw HomeError.unauthorized(path: path.name)
      } catch HomePathError.interrupted {
        failures.append(PathFailure(path: path.name, reason: "the connection was lost"))
      }
    }
    throw HomeError.noPathReached(failures)
  }

}
