import SwiftUI

struct QueueView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(player.queue.enumerated()), id: \.offset) { pair in
                Button { player.jump(to: pair.offset) } label: {
                    TrackRow(track: pair.element, highlighted: pair.offset == player.currentIndex)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Up next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
