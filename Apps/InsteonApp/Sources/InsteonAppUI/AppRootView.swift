import SwiftUI

/// The app's first view: the choice of network, then the devices screen.
public struct AppRootView: View {
  @State private var model: AppModel

  /// Creates the view from the process's launch arguments.
  public init(arguments: [String]) {
    _model = State(initialValue: AppModel(arguments: arguments))
  }

  public var body: some View {
    NavigationStack {
      if let screen = model.devices {
        DevicesView(screen: screen)
      } else {
        VStack(spacing: 16) {
          Text("Run the app on a network")
          Button("Try the demo") { model.choose(.demo) }
        }
        .navigationTitle("Insteon")
      }
    }
  }
}
