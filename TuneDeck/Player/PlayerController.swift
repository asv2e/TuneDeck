import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Owns the AVPlayer, the queue, and the system integrations (lock screen, Control Center,
/// headphone buttons, interruptions). Views read its state and call its methods.
@MainActor
@Observable
final class PlayerController {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)
    }

    // MARK: Observable state

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var state: State = .idle
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var isNowPlayingPresented = false

    var current: Track? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    var hasNext: Bool {
        guard let index = currentIndex else { return false }
        return index + 1 < queue.count
    }

    // MARK: Internals

    private let library: LibraryStore
    private let player = AVPlayer()
    private let streams = StreamService()

    /// What the listener wants (as opposed to what AVPlayer is doing right now).
    /// Lets "pause while the stream is still resolving" work, and survives interruptions.
    @ObservationIgnored private var autoplay = true
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var radioTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []

    init(library: LibraryStore) {
        self.library = library
        configureAudioSession()
        installRemoteCommands()
        installObservers()
    }

    // MARK: - Playing things

    /// Plays a track and queues similar songs after it (YouTube Music "radio").
    func play(_ track: Track) {
        radioTask?.cancel()
        queue = [track]
        autoplay = true
        load(index: 0)
        appendRadio(after: track)
    }

    /// Plays an explicit list, e.g. Favorites, without adding radio tracks.
    func play(queue tracks: [Track], startAt index: Int) {
        guard tracks.indices.contains(index) else { return }
        radioTask?.cancel()
        queue = tracks
        autoplay = true
        load(index: index)
    }

    func playNext(_ track: Track) {
        guard let index = currentIndex else {
            play(queue: [track], startAt: 0)
            return
        }
        queue.insert(track, at: index + 1)
    }

    func enqueue(_ track: Track) {
        if currentIndex == nil {
            play(queue: [track], startAt: 0)
        } else {
            queue.append(track)
        }
    }

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        autoplay = true
        load(index: index)
    }

    // MARK: - Transport

    func togglePlayPause() {
        switch state {
        case .playing, .loading: pause()
        case .paused, .idle, .failed: resume()
        }
    }

    func pause() {
        autoplay = false
        player.pause()
        if state == .playing || state == .loading { state = .paused }
        publishNowPlaying()
    }

    func resume() {
        autoplay = true
        switch state {
        case .playing, .loading:
            return
        case .paused:
            if player.currentItem != nil {
                activateSession()
                player.play()
                state = .playing
                publishNowPlaying()
            } else if let index = currentIndex {
                load(index: index)      // paused while the stream was still resolving
            }
        case .idle, .failed:
            if let index = currentIndex { load(index: index) }
        }
    }

    func next() {
        guard let index = currentIndex, index + 1 < queue.count else { return }
        autoplay = true
        load(index: index + 1)
    }

    func previous() {
        guard let index = currentIndex else { return }
        if position > 3 || index == 0 {
            seek(to: 0)
        } else {
            autoplay = true
            load(index: index - 1)
        }
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, seconds)
        position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.publishNowPlaying() }
        }
    }

    // MARK: - Loading

    private func load(index: Int) {
        guard queue.indices.contains(index) else { return }
        loadTask?.cancel()

        currentIndex = index
        let track = queue[index]
        state = .loading
        position = 0
        duration = track.duration ?? 0

        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        removeEndObserver()

        library.recordPlay(track)
        fetchArtwork(for: track)
        publishNowPlaying()

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.streams.stream(for: track.id)
                guard !Task.isCancelled, self.current?.id == track.id else { return }
                self.startPlayback(stream)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
                self.publishNowPlaying()
            }
        }
    }

    private func startPlayback(_ stream: ResolvedStream) {
        let options: [String: Any] = stream.headers.isEmpty
            ? [:]
            : ["AVURLAssetHTTPHeaderFieldsKey": stream.headers]
        let asset = AVURLAsset(url: stream.url, options: options)
        let item = AVPlayerItem(asset: asset)
        observe(item)
        player.replaceCurrentItem(with: item)

        if autoplay {
            activateSession()
            player.play()           // state flips to .playing when AVPlayer reports it
        } else {
            state = .paused
        }

        Task { [weak self] in
            if let length = try? await asset.load(.duration), length.isNumeric, length.seconds > 0 {
                self?.duration = length.seconds
                self?.publishNowPlaying()
            }
        }
    }

    private func observe(_ item: AVPlayerItem) {
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let httpStatus = item.errorLog()?.events.last?.errorStatusCode ?? 0
            let message = httpStatus == 403
                ? "YouTube rejected the stream (403). Set up a stream resolver in Settings."
                : (item.error?.localizedDescription ?? "Playback failed.")
            Task { @MainActor in self?.playbackFailed(message) }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackDidFinish() }
        }
    }

    private func removeEndObserver() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func playbackFailed(_ message: String) {
        state = .failed(message)
        if let id = current?.id {
            Task { await streams.invalidate(id) }
        }
        publishNowPlaying()
    }

    private func trackDidFinish() {
        if hasNext {
            next()
        } else {
            autoplay = false
            player.pause()
            state = .paused
            seek(to: 0)
        }
    }

    private func appendRadio(after track: Track) {
        radioTask = Task { [weak self] in
            guard let related = try? await InnerTubeClient.shared.radio(for: track.id),
                  !Task.isCancelled,
                  let self else { return }
            let existing = Set(self.queue.map(\.id))
            self.queue.append(contentsOf: related.filter { !existing.contains($0.id) })
        }
    }

    // MARK: - AVPlayer observation

    private func timeControlChanged() {
        switch player.timeControlStatus {
        case .playing:
            state = .playing
        case .paused:
            if state == .playing { state = .paused }
        case .waitingToPlayAtSpecifiedRate:
            if state == .playing { state = .loading }   // rebuffering
        @unknown default:
            break
        }
        publishNowPlaying()
    }

    private func installObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.isNumeric else { return }
                self.position = time.seconds
            }
        }

        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.timeControlChanged() }
        }

        let center = NotificationCenter.default

        systemObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            MainActor.assumeIsolated { self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw) }
        })

        systemObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated { self?.handleRouteChange(reasonRaw: reasonRaw) }
        })
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            break   // the system pauses AVPlayer; `autoplay` still records that we wanted playback
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume), autoplay, player.currentItem != nil {
                activateSession()
                player.play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard let reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        if reason == .oldDeviceUnavailable { pause() }   // headphones unplugged
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Lock screen / Control Center

    /// `nonisolated` so the handlers below are not main-actor-isolated: MediaPlayer invokes them
    /// on its own queue, and a main-actor closure called off the main thread traps at runtime.
    nonisolated private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let target = event.positionTime
            Task { @MainActor in self?.seek(to: target) }
            return .success
        }
    }

    private func publishNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistLine,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let album = track.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func fetchArtwork(for track: Track) {
        artworkTask?.cancel()
        artwork = nil
        guard let url = track.artworkURL(size: 544) else { return }
        artworkTask = Task { [weak self] in
            guard let result = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: result.0),
                  !Task.isCancelled else { return }
            self?.artwork = Self.makeArtwork(image)
            self?.publishNowPlaying()
        }
    }

    /// Built outside the main actor for the same reason as the remote-command handlers:
    /// MediaPlayer calls `requestHandler` from a background queue.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
