import Foundation

/// Mutants aimed at `check-cli-thin`: the code its rules look for, and the lines of its allow-list.
public enum CLIThinMutations {
  static let snippets = [
    "known?.category == .dimmableLightingControl", "category != nil", "x.category.rawValue == 1", "subcategory?.rawValue != 2",
    "firmwareVersion >= 65", "identity.firmwareVersion.rawValue >= 0x41", "firmware ?? 0 >= 1", "nil == known?.firmwareVersion",
    "rows.contains(where: { $0.category == nil })", "kind == .relay", "group.kind.rawValue == \"relay\"", "x == .dimmer",
    "[.dimmer, .relay].contains(kind)", "onOffKinds.contains(group.kind)", "engine == .i2cs", "engine != .i1", "case .i3",
    "case .fan", "0x41", "0XFF", "0x", "let b = 0xZ", "command1: 17", "command2: 0.5", "command1: x", "command1 : 3 ",
    "StandardDirectCommand.on", "ExtendedDirectCommand", "mainGroupType", "GroupType.Kind", "switch device.category",
    "case .dimmableLightingControl", "case .switchedLightingControl", "a < b", "a<b", "x -> y", "Array<Int>", "a <= b",
    "a ~= b", "category ?? x == y", "category\u{301} == 1", "xcategory == 1", "categoryx == 1", "1 == category",
    "== .kind", "kind\u{200B} == .x", "x.contains( kind)", "nil == nil", "kind == nil", "[ .sensor", "== .button"
  ]

  public static let sourceOperators: [TextOperator] = [
    CodeMutations.insertSnippet(from: snippets),
    CodeMutations.appendSnippet(from: snippets)
  ] + CommonOperators.all

  public static let allowListOperators = CodeMutations.allowListOperators(
    columns: 3,
    samples: [
      ["insteon/DeviceCommands.swift", "group-kind", "if kind == .relay { }"],
      ["insteon/ExploreCommands.swift", "hex-literal", "let level = 0xFF"],
      ["InsteonCLISupport/X.swift", "engine", "engine == .i2cs"],
      ["insteon/Nope.swift", "category", "category == 1"]
    ]
  ) + CommonOperators.all
}
