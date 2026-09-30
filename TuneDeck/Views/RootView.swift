import SwiftUI

struct RootView: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        @Bindable var player = player

        TabView {
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "music.note.list") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: $player.isNowPlayingPresented) {
            NowPlayingView()
        }
    }
}

extension View {
    /// Docks the mini player above the tab bar. Applied per tab so it sits in that tab's safe area.
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerView() }
    }
}
