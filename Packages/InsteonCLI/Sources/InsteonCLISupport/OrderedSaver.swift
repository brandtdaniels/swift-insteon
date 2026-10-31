/// Saves what a value learned since its last save, one save at a time, in the order they're
/// asked for.
///
/// Each save reads the value, then writes it with what was last saved, so the write holds
/// only what changed. Saves never overlap: two at once could each read before the other
/// wrote, so the later write would undo the earlier one's changes, or write older contents
/// over newer ones.
///
/// ```swift
/// let saver = OrderedSaver(saved: start)
/// await saver.save(reading: { await network.snapshot() }, writing: { learned, since in store.save(learned, since: since) })
/// ```
public actor OrderedSaver<Snapshot: Sendable> {

  /// What was last saved, or what the saver started from.
  public private(set) var lastSaved: Snapshot

  /// How many saves have been asked for.
  public private(set) var requested: Int = 0

  /// The save asked for last, which the next one waits for.
  private var last: Task<Void, Never>?

  /// Creates a saver.
  ///
  /// - Parameter saved: What's already saved.
  public init(saved: Snapshot) {

    self.lastSaved = saved

  }

  /// Reads the value and writes it, once every save asked for earlier has finished.
  ///
  /// - Parameters:
  ///   - read: Reads the value.
  ///   - write: Writes what was read, given what was last saved, and returns whether it was
  ///     written. What wasn't written is written with the next save.
  public func save(
    reading read: @escaping @Sendable () async -> Snapshot,
    writing write: @escaping @Sendable (_ learned: Snapshot, _ since: Snapshot) -> Bool
  ) async {

    requested += 1

    let previous: Task<Void, Never>? = last
    // Unstructured, so each save waits for the one before it whichever task asked for it.
    let saving = Task { () async -> Void in

      await previous?.value
      await self.saveNow(reading: read, writing: write)

    }

    last = saving

    await saving.value

  }

  private func saveNow(
    reading read: @Sendable () async -> Snapshot,
    writing write: @Sendable (_ learned: Snapshot, _ since: Snapshot) -> Bool
  ) async {

    let learned: Snapshot = await read()

    if write(learned, lastSaved) {

      lastSaved = learned

    }

  }

}
