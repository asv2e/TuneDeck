import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(height: 2)

                HStack(spacing: 12) {
                    ArtworkView(track: track, size: 240)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        subtitle(for: track)
                    }

                    Spacer(minLength: 0)

                    Button { player.togglePlayPause() } label: {
                        PlayPauseIcon(state: player.state)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .frame(width: 40, height: 40)
                    }
                    .disabled(!player.hasNext)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { player.isNowPlayingPresented = true }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private var fraction: Double {
        guard player.duration > 0 else { return 0 }
        return min(max(player.position / player.duration, 0), 1)
    }

    @ViewBuilder
    private func subtitle(for track: Track) -> some View {
        if case .failed(let message) = player.state {
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else {
            Text(track.artistLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
