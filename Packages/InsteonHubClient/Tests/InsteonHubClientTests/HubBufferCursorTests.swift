import Testing
import InsteonHubClient

struct HubBufferCursorTests {

  @Test func returnsBytesWrittenSinceLastRead() {

    var cursor = HubBufferCursor()

    #expect(cursor.advance(to: HubBuffer(bytes: [1, 2, 3, 0, 0, 0], endIndex: 2)) == [1, 2])
    #expect(cursor.advance(to: HubBuffer(bytes: [1, 2, 3, 4, 0, 0], endIndex: 4)) == [3, 4])

  }

  @Test func returnsNothingWhenNothingWasWritten() {

    var cursor = HubBufferCursor()

    _ = cursor.advance(to: HubBuffer(bytes: [1, 2, 0, 0], endIndex: 2))

    #expect(cursor.advance(to: HubBuffer(bytes: [1, 2, 0, 0], endIndex: 2)).isEmpty)

  }

  @Test func followsWritesAroundTheEndOfTheRing() {

    var cursor = HubBufferCursor()

    _ = cursor.advance(to: HubBuffer(bytes: [1, 2, 3, 4, 0, 0], endIndex: 4))

    #expect(cursor.advance(to: HubBuffer(bytes: [7, 2, 3, 4, 5, 6], endIndex: 1)) == [5, 6, 7])

  }

  @Test func keepsZeroBytesThatWrapAroundTheRing() {

    var cursor = HubBufferCursor()

    _ = cursor.advance(to: HubBuffer(bytes: [1, 2, 3, 4, 0, 0], endIndex: 4))

    // A reply ending in two zero bytes filled the end of the ring, then the next began at 0.
    #expect(cursor.advance(to: HubBuffer(bytes: [7, 2, 3, 4, 0, 0], endIndex: 1)) == [0, 0, 7])

  }

  @Test func skipsZeroedTailAfterBufferWasCleared() {

    var cursor = HubBufferCursor()

    _ = cursor.advance(to: HubBuffer(bytes: [1, 2, 3, 4, 0, 0], endIndex: 4))

    #expect(cursor.advance(to: HubBuffer(bytes: [9, 8, 0, 0, 0, 0], endIndex: 2)) == [9, 8])

  }

  @Test func resetsOnAnAllZeroBuffer() {

    var cursor = HubBufferCursor()

    _ = cursor.advance(to: HubBuffer(bytes: [1, 2, 3, 0], endIndex: 3))

    #expect(cursor.advance(to: HubBuffer(bytes: [0, 0, 0, 0], endIndex: 0)).isEmpty)
    #expect(cursor.advance(to: HubBuffer(bytes: [5, 0, 0, 0], endIndex: 1)) == [5])

  }

}
