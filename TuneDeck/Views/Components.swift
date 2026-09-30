import SwiftUI

/// Square artwork that fills whatever frame it is given.
struct ArtworkView: View {
    let track: Track?
    var size: Int = 240

    var body: some View {
        Color.clear
            .overlay {
                AsyncImage(url: track?.artworkURL(size: size)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Rectangle().fill(.quaternary)
                            Image(systemName: "music.note").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .clipped()
    }
}

struct TrackRow: View {
    let track: Track
    var highlighted = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track, size: 240)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                Text(track.artistLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let duration = track.duration {
                Text(Format.time(duration))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct PlayPauseIcon: View {
    let state: PlayerController.State

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
        case .playing:
            Image(systemName: "pause.fill")
        default:
            Image(systemName: "play.fill")
        }
    }
}

/// Long-press menu shared by every track row.
struct TrackMenu: ViewModifier {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    let track: Track

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { player.playNext(track) } label: {
                Label("Play next", systemImage: "text.insert")
            }
            Button { player.enqueue(track) } label: {
                Label("Add to queue", systemImage: "text.append")
            }
            Button { player.play(track) } label: {
                Label("Start radio", systemImage: "dot.radiowaves.left.and.right")
            }
            Button { library.toggleFavorite(track) } label: {
                if library.isFavorite(track) {
                    Label("Remove from favorites", systemImage: "heart.slash")
                } else {
                    Label("Add to favorites", systemImage: "heart")
                }
            }
        }
    }
}

extension View {
    func trackMenu(_ track: Track) -> some View {
        modifier(TrackMenu(track: track))
    }
}
