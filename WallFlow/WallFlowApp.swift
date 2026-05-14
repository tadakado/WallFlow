import SwiftUI

@main
struct WallFlowApp: App {
    @StateObject private var viewModel = ImageSlideshowViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
