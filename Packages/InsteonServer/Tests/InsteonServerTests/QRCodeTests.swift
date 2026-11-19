import Foundation
import Testing
@testable import InsteonServerSupport

@Suite(.timeLimit(.minutes(1)))
struct QRCodeTests {
  /// Data codewords of each version at error correction level L, from ISO/IEC 18004.
  static let dataCodewords = [19, 34, 55, 80, 108, 136, 156, 194, 232, 274, 324, 370, 428, 461, 523, 589, 647, 721, 795, 861, 932, 1006, 1094, 1174, 1276, 1370, 1468, 1531, 1631, 1735, 1843, 1955, 2071, 2191, 2306, 2434, 2566, 2702, 2812, 2956]

  @Test func eachVersionsTablesGiveTheSpecifiedNumberOfDataCodewords() {
    for version in 1...40 {
      #expect(QRCode.dataCodewordCount(version: version) == Self.dataCodewords[version - 1], "version \(version)")
    }
  }

  @Test func reedSolomonMatchesTheWorkedExampleInTheSpecification() {
    // "HELLO WORLD" at version 1, level M, with 10 error correction codewords.
    let data: [UInt8] = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17]
    #expect(ReedSolomon.remainder(of: data, degree: 10) == [196, 35, 39, 119, 235, 215, 231, 226, 93, 23])
  }

  @Test func theSmallestVersionThatHoldsTheTextIsChosen() throws {
    #expect(try QRCode(text: String(repeating: "a", count: 17)).version == 1)
    #expect(try QRCode(text: String(repeating: "a", count: 18)).version == 2)
    #expect(try QRCode(text: String(repeating: "a", count: 2953)).version == 40)
    #expect(throws: QRCodeError.tooLong) { try QRCode(text: String(repeating: "a", count: 2954)) }
  }

  @Test func theSymbolHasTheFixedPatternsAFinderNeeds() throws {
    let code = try QRCode(text: String(repeating: "x", count: 300))
    let size = code.size
    #expect(size == 17 + 4 * code.version)
    for (cornerX, cornerY) in [(0, 0), (size - 7, 0), (0, size - 7)] {
      for offset in 0..<7 {
        for edge in [(offset, 0), (offset, 6), (0, offset), (6, offset)] { #expect(code[cornerX + edge.0, cornerY + edge.1]) }
      }
      #expect(code[cornerX + 3, cornerY + 3])
      #expect(!code[cornerX + 1, cornerY + 1] && !code[cornerX + 5, cornerY + 5])
    }
    for index in 8..<(size - 8) { #expect(code[index, 6] == (index % 2 == 0)); #expect(code[6, index] == (index % 2 == 0)) }
    #expect(code[8, size - 8])
  }

  @Test func bothCopiesOfTheFormatInformationAgreeAndNameLevelL() throws {
    let code = try QRCode(text: "format")
    func firstCopy() -> Int {
      var bits = 0
      let cells: [(Int, Int)] = [(8, 0), (8, 1), (8, 2), (8, 3), (8, 4), (8, 5), (8, 7), (8, 8), (7, 8), (5, 8), (4, 8), (3, 8), (2, 8), (1, 8), (0, 8)]
      for (index, cell) in cells.enumerated() where code[cell.0, cell.1] { bits |= 1 << index }
      return bits
    }
    func secondCopy() -> Int {
      var bits = 0
      for index in 0..<8 where code[code.size - 1 - index, 8] { bits |= 1 << index }
      for index in 8..<15 where code[8, code.size - 15 + index] { bits |= 1 << index }
      return bits
    }
    #expect(firstCopy() == secondCopy())
    // The level is the top two bits of the unmasked word: 01 for L.
    #expect(((firstCopy() ^ 0x5412) >> 13) == 0b01)
  }

  @Test func theRenderingIsTwoModulesPerLineWithAQuietZone() throws {
    let code = try QRCode(text: "render")
    let lines = code.rendered().split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }
    #expect(lines.count == (code.size + 8 + 1) / 2)
  }
}

#if canImport(CoreImage) && canImport(CoreGraphics)
import CoreGraphics
import CoreImage

extension QRCodeTests {
  /// The symbol as a bitmap with a quiet zone, the way a camera sees a printed code.
  private func image(of code: QRCode) throws -> CIImage {
    let scale = 6, margin = 4
    let side = (code.size + 2 * margin) * scale
    var pixels = [UInt8](repeating: 255, count: side * side)
    for row in 0..<code.size {
      for column in 0..<code.size where code[column, row] {
        for y in 0..<scale { for x in 0..<scale { pixels[((row + margin) * scale + y) * side + (column + margin) * scale + x] = 0 } }
      }
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let picture = try #require(CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    return CIImage(cgImage: picture)
  }

  private func decoded(_ text: String) throws -> String? {
    let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
    let features = detector.features(in: try image(of: QRCode(text: text)))
    return (features.first as? CIQRCodeFeature)?.messageString
  }

  @Test(arguments: [8, 40, 150, 400, 800, 1500])
  func aSystemReaderDecodesWhatTheGeneratorDraws(_ length: Int) throws {
    let text = String((0..<length).map { index in Array("abcdefghijklmnopqrstuvwxyz0123456789{}\":,/.-_ ")[index * 7 % 44] })
    #expect(try decoded(text) == text)
  }

  @Test func aSystemReaderDecodesAPairingDocument() throws {
    let document = #"{"api":"/api/v1","credential":"0123456789abcdef.AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE","name":"Home","routes":[{"kind":"lan","url":"http://192.168.1.50:8080"}],"scope":"control","serviceId":"00112233445566778899aabbccddeeff","version":1}"#
    #expect(try decoded(document) == document)
  }
}
#endif
