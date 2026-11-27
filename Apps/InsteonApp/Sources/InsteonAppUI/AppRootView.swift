import SwiftUI

/// The app's first view: the choice of network, then the devices and scenes screens as tabs.
public struct AppRootView: View {
  @State private var model: AppModel

  /// Creates the view from the process's launch arguments.
  public init(arguments: [String]) {
    _model = State(initialValue: AppModel(arguments: arguments))
  }

  public var body: some View {
    if let devices = model.devices, let scenes = model.scenes {
      // One set of tabs on every platform: the tab bar on iPhone, and the same tabs on iPad and Mac.
      TabView {
        NavigationStack { DevicesView(screen: devices) }
          .tabItem { Label("Devices", systemImage: "lightbulb") }
        NavigationStack { ScenesView(screen: scenes) }
          .tabItem { Label("Scenes", systemImage: "square.grid.2x2") }
      }
      .id(model.identity)
    } else {
      NavigationStack {
        VStack(spacing: 16) {
          Text("Run the app on a network")
          Button("Try the demo") { model.choose(.demo) }
        }
        .navigationTitle("Insteon")
      }
    }
  }
}
