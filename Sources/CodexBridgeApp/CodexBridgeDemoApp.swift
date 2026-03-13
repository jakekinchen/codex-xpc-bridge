import SwiftUI

@main
struct CodexXPCBridgeDemoApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup("CodexXPCBridgeDemo") {
            ContentView(model: model)
                .frame(minWidth: 1180, minHeight: 820)
                .task {
                    await model.bootstrapIfNeeded()
                }
        }
        .windowResizability(.contentSize)
    }
}
