import SwiftUI

struct LibraryView: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    @State private var shelf: Shelf = .favorites

    enum Shelf: String, CaseIterable, Identifiable {
        case favorites = "Favorites"
        case recents = "Recent"
        var id: String { rawValue }
    }

    private var tracks: [Track] {
        shelf == .favorites ? library.favorites : library.recents
    }

    var body: some View {
        NavigationStack {
            Group {
                if tracks.isEmpty {
                    emptyState
                } else {
                    List(Array(tracks.enumerated()), id: \.element.id) { pair in
                        Button {
                            player.play(queue: tracks, startAt: pair.offset)
                        } label: {
                            TrackRow(track: pair.element, highlighted: player.current?.id == pair.element.id)
                        }
                        .buttonStyle(.plain)
                        .trackMenu(pair.element)
                        .swipeActions(edge: .trailing) {
                            if shelf == .favorites {
                                Button(role: .destructive) {
                                    library.toggleFavorite(pair.element)
                                } label: {
                                    Label("Remove", systemImage: "heart.slash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Shelf", selection: $shelf) {
                        ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                if shelf == .recents && !library.recents.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { library.clearRecents() }
                    }
                }
            }
        }
        .miniPlayerInset()
    }

    @ViewBuilder
    private var emptyState: some View {
        if shelf == .favorites {
            ContentUnavailableView(
                "No favorites yet",
                systemImage: "heart",
                description: Text("Touch and hold a song, or tap the heart in Now Playing.")
            )
        } else {
            ContentUnavailableView(
                "Nothing played yet",
                systemImage: "clock",
                description: Text("Songs you play will show up here.")
            )
        }
    }
}
