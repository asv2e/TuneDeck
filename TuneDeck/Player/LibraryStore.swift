import Foundation
import Observation

/// Favorites and play history, persisted as JSON in UserDefaults.
@MainActor
@Observable
final class LibraryStore {
    private(set) var favorites: [Track] = []
    private(set) var recents: [Track] = []

    private let defaults: UserDefaults
    private static let favoritesKey = "library.favorites.v1"
    private static let recentsKey = "library.recents.v1"
    private static let recentsLimit = 50

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = Self.load(Self.favoritesKey, from: defaults)
        recents = Self.load(Self.recentsKey, from: defaults)
    }

    func isFavorite(_ track: Track) -> Bool {
        favorites.contains { $0.id == track.id }
    }

    func toggleFavorite(_ track: Track) {
        if let index = favorites.firstIndex(where: { $0.id == track.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(track, at: 0)
        }
        save(favorites, key: Self.favoritesKey)
    }

    func recordPlay(_ track: Track) {
        recents.removeAll { $0.id == track.id }
        recents.insert(track, at: 0)
        if recents.count > Self.recentsLimit {
            recents.removeLast(recents.count - Self.recentsLimit)
        }
        save(recents, key: Self.recentsKey)
    }

    func clearRecents() {
        recents = []
        save(recents, key: Self.recentsKey)
    }

    // MARK: Persistence

    private static func load(_ key: String, from defaults: UserDefaults) -> [Track] {
        guard let data = defaults.data(forKey: key),
              let tracks = try? JSONDecoder().decode([Track].self, from: data) else { return [] }
        return tracks
    }

    private func save(_ tracks: [Track], key: String) {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        defaults.set(data, forKey: key)
    }
}
