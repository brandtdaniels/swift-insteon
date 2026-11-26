import InsteonService
import SwiftUI

/// The devices screen's view: a list with an on and off switch per device.
public struct DevicesView<Network: DeviceQuerying & DeviceCommanding>: View {
  @State private var screen: DevicesScreen<Network>

  /// Creates the view over a network.
  public init(network: Network) {
    _screen = State(initialValue: DevicesScreen(network: network))
  }

  public var body: some View {
    List(screen.rows) { row in
      HStack {
        VStack(alignment: .leading) {
          Text(row.title)
          Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Text(Self.text(for: row.level)).foregroundStyle(.secondary)
        if row.canSwitch {
          // Two plain buttons in one list row both fire on a tap anywhere in the row on iOS, so each is borderless.
          Button("On") { Task { await screen.turn(row, on: true) } }
            .buttonStyle(.borderless).disabled(screen.isBusy(row))
          Button("Off") { Task { await screen.turn(row, on: false) } }
            .buttonStyle(.borderless).disabled(screen.isBusy(row))
        }
      }
    }
    .overlay {
      if case let .failed(message) = screen.state { Text(message).foregroundStyle(.secondary) }
    }
    .alert("Couldn't send", isPresented: Binding(get: { screen.notice != nil }, set: { if !$0 { screen.notice = nil } })) {
      Button("OK") { screen.notice = nil }
    } message: {
      Text(screen.notice ?? "")
    }
    .navigationTitle("Devices")
    .task { await screen.load() }
  }

  private static func text(for level: DeviceRow.Level) -> String {
    switch level {
    case .unknown: "Unknown"
    case .off: "Off"
    case let .percent(value): "\(value)%"
    }
  }
}
