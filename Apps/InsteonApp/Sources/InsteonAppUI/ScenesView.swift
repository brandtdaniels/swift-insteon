import InsteonClient
import SwiftUI

/// The scenes screen's view: a list of scenes with their members, a run button for each scene the
/// modem starts, and a refresh that reads the network.
public struct ScenesView<Network: SceneManaging>: View {
  @State private var screen: ScenesScreen<Network>

  /// Creates the view over a screen that already exists.
  public init(screen: ScenesScreen<Network>) {
    _screen = State(initialValue: screen)
  }

  public var body: some View {
    List {
      if !screen.rows.isEmpty, !screen.isWhole {
        Section {
          ForEach(screen.gaps, id: \.self) { Text($0).font(.footnote) }
        } header: {
          Text("Not everything was read")
        }
      }
      ForEach(screen.rows) { row in
        Section {
          ForEach(row.members) { member in
            VStack(alignment: .leading) {
              Text(member.title)
              Text(member.detail).font(.caption).foregroundStyle(.secondary)
            }
          }
          if let note = row.note {
            Text(note).font(.footnote).foregroundStyle(.secondary)
          }
        } header: {
          header(for: row)
        }
      }
    }
    .overlay {
      if screen.isLoading && screen.rows.isEmpty {
        ProgressView()
      } else if let message = screen.emptyMessage {
        VStack(spacing: 12) {
          Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
          Button("Read the scenes") { Task { await screen.refresh() } }.disabled(screen.isBusy)
        }
        .padding()
      } else if screen.rows.isEmpty, let failure = screen.failure {
        VStack(spacing: 12) {
          Text(failure).foregroundStyle(.secondary).multilineTextAlignment(.center)
          Button("Try again") { Task { await screen.load() } }
        }
        .padding()
      }
    }
    .safeAreaInset(edge: .top) {
      if !screen.rows.isEmpty, let failure = screen.failure {
        HStack {
          Text(failure).font(.footnote)
          Spacer()
          Button("Try again") { Task { await screen.load() } }
        }
        .padding(.horizontal)
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if screen.isRefreshing {
          ProgressView()
        } else {
          Button("Refresh") { Task { await screen.refresh() } }.disabled(screen.isBusy)
        }
      }
    }
    .alert(
      screen.outcome?.title ?? "", isPresented: Binding(get: { screen.outcome != nil }, set: { if !$0 { screen.dismissOutcome() } })
    ) {
      Button("OK") { screen.dismissOutcome() }
    } message: {
      Text(screen.outcome?.message ?? "")
    }
    .navigationTitle("Scenes")
    .task { await screen.load() }
  }

  private func header(for row: SceneRow) -> some View {
    HStack {
      VStack(alignment: .leading) {
        Text(row.title).font(.headline)
        Text(row.source).font(.caption)
      }
      Spacer()
      if row.canRun {
        if screen.isRunning(row) { ProgressView() }
        // Two plain buttons in one row both fire on a tap anywhere in the row on iOS, so each is borderless.
        Button("On") { Task { await screen.run(row, .on) } }.buttonStyle(.borderless).disabled(screen.isBusy)
        Button("Off") { Task { await screen.run(row, .off) } }.buttonStyle(.borderless).disabled(screen.isBusy)
      }
    }
    .textCase(nil)
  }
}
