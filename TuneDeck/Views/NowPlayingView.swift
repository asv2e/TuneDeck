import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    @State private var showQueue = false

    var body: some View {
        ZStack {
            Backdrop(track: player.current)

            VStack(spacing: 0) {
                Spacer(minLength: 12)
                artwork
                Spacer(minLength: 24)
                titleBlock
                Spacer(minLength: 16)
                Scrubber()
                Spacer(minLength: 12)
                transport
                Spacer(minLength: 20)
                footer
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showQueue) {
            QueueView()
                .presentationDetents([.medium, .large])
        }
    }

    // The artwork settles back when paused and comes forward when playing.
    private var artwork: some View {
        let isPlaying = player.state == .playing
        return ArtworkView(track: player.current, size: 720)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: isPlaying ? 30 : 12, y: isPlaying ? 18 : 6)
            .scaleEffect(isPlaying ? 1 : 0.88)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isPlaying)
    }

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.current?.title ?? "Not playing")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .lineLimit(2)

                if case .failed(let message) = player.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .lineLimit(4)
                } else {
                    Text(player.current?.artistLine ?? "")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if let track = player.current {
                Button { library.toggleFavorite(track) } label: {
                    Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 44) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            Button { player.togglePlayPause() } label: {
                PlayPauseIcon(state: player.state)
                    .font(.system(size: 40))
                    .frame(width: 72, height: 72)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            .disabled(!player.hasNext)
        }
        .buttonStyle(.plain)
        .tint(.white)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button { showQueue = true } label: {
                Label("Up next", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Blurred, darkened copy of the artwork so each track tints the whole screen.
private struct Backdrop: View {
    let track: Track?

    var body: some View {
        ZStack {
            Color.black
            ArtworkView(track: track, size: 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: 60)
                .scaleEffect(1.6)
                .opacity(0.75)
            LinearGradient(
                colors: [.black.opacity(0.1), .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct Scrubber: View {
    @Environment(PlayerController.self) private var player
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        let shown = isDragging ? dragValue : player.position
        let total = max(player.duration, 1)

        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { min(shown, total) }, set: { dragValue = $0 }),
                in: 0...total,
                onEditingChanged: { editing in
                    if editing {
                        dragValue = player.position
                        isDragging = true
                    } else {
                        player.seek(to: dragValue)
                        isDragging = false
                    }
                }
            )
            .tint(.white)

            HStack {
                Text(Format.time(shown))
                Spacer()
                Text("-" + Format.time(max(total - shown, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.65))
        }
    }
}
