import SwiftUI

@main
@MainActor
struct TuneDeckApp: App {
    @State private var library: LibraryStore
    @State private var player: PlayerController

    init() {
        let library = LibraryStore()
        _library = State(initialValue: library)
        _player = State(initialValue: PlayerController(library: library))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .environment(library)
        }
    }
}
