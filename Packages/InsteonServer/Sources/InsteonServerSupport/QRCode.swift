import Foundation

/// A QR Code symbol in byte mode at error correction level L, drawn for a terminal.
///
/// The symbol follows ISO/IEC 18004: versions 1 through 40, the smallest version that holds the
/// text, and the mask with the lowest penalty. It has no dependencies.
struct QRCode {

  /// The symbol's version, 1 through 40.
  let version: Int
  /// Modules on a side.
  let size: Int
  private let modules: [[Bool]]

  /// Whether the module at a column and row is dark.
  subscript(column: Int, row: Int) -> Bool { modules[row][column] }

  /// Encodes `text` as UTF-8.
  init(text: String) throws {
    let bytes = Array(text.utf8)
    guard let version = (1...40).first(where: { Self.capacity(version: $0) >= bytes.count }) else { throw QRCodeError.tooLong }
    self.version = version
    size = 17 + 4 * version
    let codewords = Self.interleaved(Self.dataCodewords(bytes, version: version), version: version)
    var grid = Grid(version: version)
    grid.drawFunctionPatterns()
    grid.place(codewords)
    var best: (mask: Int, penalty: Int)?
    for mask in 0..<8 {
      var candidate = grid
      candidate.apply(mask: mask)
      candidate.drawFormat(mask: mask)
      let penalty = candidate.penalty()
      if best == nil || penalty < best!.penalty { best = (mask, penalty) }
    }
    let chosen = best?.mask ?? 0
    grid.apply(mask: chosen)
    grid.drawFormat(mask: chosen)
    modules = grid.modules
  }

  // MARK: Capacity

  /// Codewords that hold data, as opposed to error correction, at level L.
  static func dataCodewordCount(version: Int) -> Int {
    rawCodewordCount(version: version) - eccPerBlock[version - 1] * blockCount[version - 1]
  }

  /// Bytes of text a version holds in byte mode.
  private static func capacity(version: Int) -> Int {
    let headerBits = 4 + (version <= 9 ? 8 : 16)
    return (dataCodewordCount(version: version) * 8 - headerBits) / 8
  }

  private static func rawCodewordCount(version: Int) -> Int {
    var modules = (16 * version + 128) * version + 64
    if version >= 2 {
      let alignments = version / 7 + 2
      modules -= (25 * alignments - 10) * alignments - 55
      if version >= 7 { modules -= 36 }
    }
    return modules / 8
  }

  /// Error correction codewords in each block, by version, at level L.
  private static let eccPerBlock = [7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]
  /// Blocks, by version, at level L.
  private static let blockCount = [1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25]

  // MARK: Codewords

  private static func dataCodewords(_ bytes: [UInt8], version: Int) -> [UInt8] {
    var bits: [Bool] = []
    func append(_ value: Int, count: Int) { for shift in stride(from: count - 1, through: 0, by: -1) { bits.append((value >> shift) & 1 == 1) } }
    append(0b0100, count: 4)
    append(bytes.count, count: version <= 9 ? 8 : 16)
    for byte in bytes { append(Int(byte), count: 8) }
    let capacityBits = dataCodewordCount(version: version) * 8
    append(0, count: min(4, capacityBits - bits.count))
    append(0, count: (8 - bits.count % 8) % 8)
    var codewords = stride(from: 0, to: bits.count, by: 8).map { start in bits[start..<start + 8].reduce(UInt8(0)) { $0 << 1 | ($1 ? 1 : 0) } }
    var pad: UInt8 = 0xEC
    while codewords.count < dataCodewordCount(version: version) {
      codewords.append(pad)
      pad = pad == 0xEC ? 0x11 : 0xEC
    }
    return codewords
  }

  /// Splits the data into blocks, adds each block's error correction, and interleaves them.
  private static func interleaved(_ data: [UInt8], version: Int) -> [UInt8] {
    let blocks = blockCount[version - 1], eccLength = eccPerBlock[version - 1]
    let raw = rawCodewordCount(version: version)
    let shortBlocks = blocks - raw % blocks
    let shortLength = raw / blocks
    var split: [[UInt8]] = []
    var offset = 0
    for index in 0..<blocks {
      let length = shortLength - eccLength + (index < shortBlocks ? 0 : 1)
      let block = Array(data[offset..<offset + length])
      offset += length
      // A short block gets a placeholder where the longer blocks' last data codeword sits, so positions line up; the loop below skips it.
      split.append(block + (index < shortBlocks ? [0] : []) + ReedSolomon.remainder(of: block, degree: eccLength))
    }
    var result: [UInt8] = []
    for position in 0..<split[0].count {
      for (index, block) in split.enumerated() where position != shortLength - eccLength || index >= shortBlocks {
        result.append(block[position])
      }
    }
    return result
  }

  // MARK: The grid

  private struct Grid {
    let version: Int
    let size: Int
    var modules: [[Bool]]
    private var isFunction: [[Bool]]

    init(version: Int) {
      self.version = version
      size = 17 + 4 * version
      modules = Array(repeating: Array(repeating: false, count: size), count: size)
      isFunction = modules
    }

    private mutating func set(_ column: Int, _ row: Int, _ dark: Bool) {
      modules[row][column] = dark
      isFunction[row][column] = true
    }

    mutating func drawFunctionPatterns() {
      for index in 0..<size {
        set(6, index, index % 2 == 0)
        set(index, 6, index % 2 == 0)
      }
      for (column, row) in [(3, 3), (size - 4, 3), (3, size - 4)] { drawFinder(column, row) }
      let positions = alignmentPositions
      for (i, column) in positions.enumerated() {
        for (j, row) in positions.enumerated() {
          if (i == 0 && j == 0) || (i == 0 && j == positions.count - 1) || (i == positions.count - 1 && j == 0) { continue }
          for dy in -2...2 { for dx in -2...2 { set(column + dx, row + dy, max(abs(dx), abs(dy)) != 1) } }
        }
      }
      drawFormat(mask: 0)
      drawVersion()
    }

    private mutating func drawFinder(_ column: Int, _ row: Int) {
      for dy in -4...4 {
        for dx in -4...4 {
          let (x, y) = (column + dx, row + dy)
          guard (0..<size).contains(x), (0..<size).contains(y) else { continue }
          let distance = max(abs(dx), abs(dy))
          set(x, y, distance != 2 && distance != 4)
        }
      }
    }

    private var alignmentPositions: [Int] {
      guard version > 1 else { return [] }
      let count = version / 7 + 2
      let step = version == 32 ? 26 : (version * 4 + count * 2 + 1) / (count * 2 - 2) * 2
      var positions = [6]
      var position = size - 7
      while positions.count < count {
        positions.insert(position, at: 1)
        position -= step
      }
      return positions
    }

    /// Writes the format information for level L and `mask`, both copies, and the always-dark module.
    mutating func drawFormat(mask: Int) {
      let data = (0b01 << 3) | mask
      var remainder = data
      for _ in 0..<10 { remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537) }
      let bits = ((data << 10) | remainder) ^ 0x5412
      func bit(_ index: Int) -> Bool { (bits >> index) & 1 == 1 }
      for index in 0...5 { set(8, index, bit(index)) }
      set(8, 7, bit(6))
      set(8, 8, bit(7))
      set(7, 8, bit(8))
      for index in 9..<15 { set(14 - index, 8, bit(index)) }
      for index in 0..<8 { set(size - 1 - index, 8, bit(index)) }
      for index in 8..<15 { set(8, size - 15 + index, bit(index)) }
      set(8, size - 8, true)
    }

    private mutating func drawVersion() {
      guard version >= 7 else { return }
      var remainder = version
      for _ in 0..<12 { remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25) }
      let bits = (version << 12) | remainder
      for index in 0..<18 {
        let dark = (bits >> index) & 1 == 1
        let a = size - 11 + index % 3, b = index / 3
        set(a, b, dark)
        set(b, a, dark)
      }
    }

    /// Writes the codewords into the modules that aren't function patterns, in the zigzag the standard defines.
    mutating func place(_ codewords: [UInt8]) {
      var bitIndex = 0
      var right = size - 1
      while right >= 1 {
        if right == 6 { right = 5 }
        for vertical in 0..<size {
          for j in 0..<2 {
            let column = right - j
            let upward = ((right + 1) & 2) == 0
            let row = upward ? size - 1 - vertical : vertical
            if !isFunction[row][column], bitIndex < codewords.count * 8 {
              modules[row][column] = (codewords[bitIndex >> 3] >> (7 - UInt8(bitIndex & 7))) & 1 == 1
              bitIndex += 1
            }
          }
        }
        right -= 2
      }
    }

    mutating func apply(mask: Int) {
      for row in 0..<size {
        for column in 0..<size where !isFunction[row][column] {
          let invert: Bool
          switch mask {
          case 0: invert = (column + row) % 2 == 0
          case 1: invert = row % 2 == 0
          case 2: invert = column % 3 == 0
          case 3: invert = (column + row) % 3 == 0
          case 4: invert = (column / 3 + row / 2) % 2 == 0
          case 5: invert = column * row % 2 + column * row % 3 == 0
          case 6: invert = (column * row % 2 + column * row % 3) % 2 == 0
          default: invert = ((column + row) % 2 + column * row % 3) % 2 == 0
          }
          if invert { modules[row][column].toggle() }
        }
      }
    }

    /// The standard's four penalty rules, summed.
    func penalty() -> Int {
      var total = 0
      let lines = modules + (0..<size).map { column in (0..<size).map { modules[$0][column] } }
      for line in lines {
        var run = 1
        for index in 1..<size {
          if line[index] == line[index - 1] { run += 1 } else { if run >= 5 { total += run - 2 }; run = 1 }
        }
        if run >= 5 { total += run - 2 }
        let pattern = [true, false, true, true, true, false, true]
        if size >= 11 {
          for start in 0...(size - 7) where Array(line[start..<start + 7]) == pattern {
            let before = start >= 4 && !line[(start - 4)..<start].contains(true)
            let after = start + 11 <= size && !line[(start + 7)..<(start + 11)].contains(true)
            if before { total += 40 }
            if after { total += 40 }
          }
        }
      }
      for row in 0..<(size - 1) {
        for column in 0..<(size - 1) {
          let value = modules[row][column]
          if value == modules[row][column + 1], value == modules[row + 1][column], value == modules[row + 1][column + 1] { total += 3 }
        }
      }
      let dark = modules.reduce(0) { $0 + $1.filter { $0 }.count }
      let percent = dark * 100 / (size * size)
      total += abs(percent - 50) / 5 * 10
      return total
    }
  }

  // MARK: Drawing

  /// The symbol for a terminal: black and white, two modules per line with half blocks, and a quiet zone of four modules.
  ///
  /// The colors are set explicitly, so the code reads the same on a light or a dark terminal.
  func rendered() -> String {
    let margin = 4
    func dark(_ column: Int, _ row: Int) -> Bool {
      (0..<size).contains(column) && (0..<size).contains(row) && modules[row][column]
    }
    func color(_ isDark: Bool) -> Int { isDark ? 0 : 15 }
    var lines: [String] = []
    for row in stride(from: -margin, to: size + margin, by: 2) {
      var line = ""
      for column in -margin..<(size + margin) {
        line += "\u{1B}[38;5;" + String(color(dark(column, row))) + ";48;5;" + String(color(dark(column, row + 1))) + "m\u{2580}"
      }
      lines.append(line + "\u{1B}[0m")
    }
    return lines.joined(separator: "\n") + "\n"
  }
}

/// Why a QR Code couldn't be made.
enum QRCodeError: Error, Equatable {
  /// The text is longer than the largest symbol holds.
  case tooLong
}

/// Reed-Solomon error correction over GF(256) with the QR Code polynomial 0x11D.
enum ReedSolomon {
  /// The remainder of `data` divided by the generator of `degree`: the error correction codewords.
  static func remainder(of data: [UInt8], degree: Int) -> [UInt8] {
    var generator = [UInt8](repeating: 0, count: degree - 1) + [1]
    var root: UInt8 = 1
    for _ in 0..<degree {
      for index in generator.indices {
        generator[index] = multiply(generator[index], root)
        if index + 1 < generator.count { generator[index] ^= generator[index + 1] }
      }
      root = multiply(root, 2)
    }
    var result = [UInt8](repeating: 0, count: degree)
    for byte in data {
      let factor = byte ^ result.removeFirst()
      result.append(0)
      for index in result.indices { result[index] ^= multiply(generator[index], factor) }
    }
    return result
  }

  private static func multiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
    var product = 0
    for shift in stride(from: 7, through: 0, by: -1) {
      product = (product << 1) ^ ((product >> 7) * 0x11D)
      product ^= ((Int(y) >> shift) & 1) * Int(x)
    }
    return UInt8(product)
  }
}
