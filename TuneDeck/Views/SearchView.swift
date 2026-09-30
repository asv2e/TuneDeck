import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    private(set) var results: [Track] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    private let client: InnerTubeClient

    init(client: InnerTubeClient = .shared) {
        self.client = client
    }

    /// Called from `.task(id: query)`, so a new keystroke cancels the previous call.
    func refresh() async {
        let text = query.trimmed
        guard text.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        try? await Task.sleep(for: .milliseconds(350))   // debounce
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await client.searchSongs(text)
            guard !Task.isCancelled else { return }
            results = found
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

struct SearchView: View {
    @Environment(PlayerController.self) private var player
    @State private var model = SearchViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .searchable(
                    text: $model.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Songs, artists, albums"
                )
        }
        .task(id: model.query) { await model.refresh() }
        .miniPlayerInset()
    }

    @ViewBuilder
    private var content: some View {
        if model.query.trimmed.count < 2 {
            ContentUnavailableView(
                "Search YouTube Music",
                systemImage: "magnifyingglass",
                description: Text("Type a song or artist. Tap a result to play it and queue similar tracks.")
            )
        } else if let message = model.errorMessage, model.results.isEmpty {
            ContentUnavailableView(
                "Search failed",
                systemImage: "wifi.exclamationmark",
                description: Text(message)
            )
        } else if model.results.isEmpty && !model.isSearching {
            ContentUnavailableView.search(text: model.query)
        } else {
            List(model.results) { track in
                Button { player.play(track) } label: {
                    TrackRow(track: track, highlighted: player.current?.id == track.id)
                }
                .buttonStyle(.plain)
                .trackMenu(track)
            }
            .listStyle(.plain)
            .overlay {
                if model.isSearching && model.results.isEmpty { ProgressView() }
            }
        }
    }
}
