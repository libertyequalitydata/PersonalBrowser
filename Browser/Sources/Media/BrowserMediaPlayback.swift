import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

enum BrowserMediaKind: String, Codable, Equatable, Hashable {
    case audio
    case video
}

struct BrowserMediaItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let title: String
    let kind: BrowserMediaKind
    let libraryArtifactID: UUID?
}

enum BrowserDownloadedMediaPresentation {
    static let usesBrowserOwnedMediaSurface = true
    static let nativePlayerControllerIsExcluded = true
    static let minimizeStopsPlayback = false
}

@MainActor
final class BrowserMediaPlaybackController: ObservableObject {
    @Published private(set) var currentItem: BrowserMediaItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackError: String?
    @Published private(set) var playbackRate: Double = 1
    @Published var presentedItem: BrowserMediaItem?
    var onPlaybackTime: ((BrowserMediaItem, TimeInterval, Date) -> Void)?

    let player = AVPlayer()

    private var periodicTimeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var playbackFailureObserver: NSObjectProtocol?
    private var itemStatusObservation: AnyCancellable?
    private var remoteCommandsConfigured = false
    private var lastUsageTickAt: Date?

    init() {
        configureRemoteCommands()
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.updatePlaybackTime(time.seconds)
            }
        }
    }

    deinit {
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
        }
    }

    func play(
        url: URL,
        title: String,
        kind: BrowserMediaKind,
        libraryArtifactID: UUID? = nil
    ) {
        recordUsageThroughNow()
        playbackError = nil
        configureAudioSession(for: kind)
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
        }
        itemStatusObservation = nil

        let item = BrowserMediaItem(
            url: url,
            title: title,
            kind: kind,
            libraryArtifactID: libraryArtifactID
        )
        let playerItem = AVPlayerItem(url: url)
        playerItem.audioTimePitchAlgorithm = .timeDomain
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playbackDidFinish()
            }
        }
        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                self?.setPlaybackFailure(error)
            }
        }
        itemStatusObservation = playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak playerItem] status in
                guard status == .failed else { return }
                Task { @MainActor in
                    self?.setPlaybackFailure(playerItem?.error)
                }
            }

        currentItem = item
        presentedItem = item
        elapsedTime = 0
        duration = 0
        player.isMuted = false
        player.volume = 1
        player.replaceCurrentItem(with: playerItem)
        player.playImmediately(atRate: Float(playbackRate))
        isPlaying = true
        lastUsageTickAt = .now
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        guard currentItem != nil else { return }
        if isPlaying {
            recordUsageThroughNow()
            player.pause()
            isPlaying = false
            lastUsageTickAt = nil
        } else {
            configureAudioSession(for: currentItem?.kind ?? .audio)
            if duration > 0, elapsedTime >= duration - 0.25 {
                player.seek(to: .zero)
            }
            player.playImmediately(atRate: Float(playbackRate))
            isPlaying = true
            lastUsageTickAt = .now
        }
        updateNowPlayingInfo()
    }

    func seek(by seconds: TimeInterval) {
        guard currentItem != nil else { return }
        let upperBound = duration > 0 ? duration : .greatestFiniteMagnitude
        let target = min(max(0, elapsedTime + seconds), upperBound)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsedTime = target
        updateNowPlayingInfo()
    }

    func seek(to seconds: TimeInterval) {
        guard currentItem != nil else { return }
        let target = min(max(0, seconds), duration > 0 ? duration : seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsedTime = target
        updateNowPlayingInfo()
    }

    func setPlaybackRate(_ rate: Double) {
        guard BrowserMediaPlaybackController.supportedRates.contains(rate) else { return }
        playbackRate = rate
        player.defaultRate = Float(rate)
        if isPlaying {
            player.rate = Float(rate)
        }
        updateNowPlayingInfo()
    }

    func stop() {
        recordUsageThroughNow()
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentItem = nil
        presentedItem = nil
        isPlaying = false
        elapsedTime = 0
        duration = 0
        playbackError = nil
        playbackRate = 1
        itemStatusObservation = nil
        lastUsageTickAt = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func dismissPlayerSurface() {
        stop()
    }

    func minimizePlayerSurface() {
        guard currentItem != nil else { return }
        presentedItem = nil
    }

    func restorePlayerSurface() {
        guard let currentItem else { return }
        presentedItem = currentItem
    }

    private func updatePlaybackTime(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        recordUsageThroughNow()
        elapsedTime = max(0, seconds)
        if let durationSeconds = player.currentItem?.duration.seconds,
           durationSeconds.isFinite,
           durationSeconds > 0 {
            duration = durationSeconds
        }
        updateNowPlayingInfo()
    }

    private func playbackDidFinish() {
        recordUsageThroughNow()
        isPlaying = false
        lastUsageTickAt = nil
        if duration > 0 { elapsedTime = duration }
        updateNowPlayingInfo()
    }

    private func configureAudioSession(for kind: BrowserMediaKind) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: kind == .video ? .moviePlayback : .spokenAudio,
                options: [.allowAirPlay]
            )
            try session.setActive(true)
        } catch { /* Playback may still use an already-active compatible session. */ }
    }

    private func setPlaybackFailure(_ error: Error?) {
        recordUsageThroughNow()
        isPlaying = false
        lastUsageTickAt = nil
        playbackError = error?.localizedDescription ?? "This media file could not be played."
        updateNowPlayingInfo()
    }

    private func configureRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true
        commands.skipForwardCommand.isEnabled = true
        commands.skipBackwardCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.preferredIntervals = [15]

        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == false { self?.togglePlayback() }
            }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == true { self?.togglePlayback() }
            }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        commands.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: 15) }
            return .success
        }
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.seek(by: -15) }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentItem.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0,
            MPNowPlayingInfoPropertyMediaType: currentItem.kind == .video
                ? MPNowPlayingInfoMediaType.video.rawValue
                : MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func recordUsageThroughNow() {
        guard isPlaying, let currentItem, let lastUsageTickAt else { return }
        let now = Date()
        let seconds = min(2, max(0, now.timeIntervalSince(lastUsageTickAt)))
        self.lastUsageTickAt = now
        guard seconds > 0 else { return }
        onPlaybackTime?(currentItem, seconds, now)
    }

    static let supportedRates: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]
}

struct BrowserMediaPlayerScreen: View {
    @ObservedObject var playback: BrowserMediaPlaybackController
    var onTranscribe: ((BrowserMediaItem) -> Void)?
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let landscapeVideo = playback.currentItem?.kind == .video
                && geometry.size.width > geometry.size.height
            let showsControls = !landscapeVideo || controlsVisible

            ZStack {
                Color.black.ignoresSafeArea()

                if playback.currentItem?.kind == .video {
                    BrowserVideoPlayerLayer(player: playback.player)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            controlsVisible.toggle()
                            if controlsVisible { scheduleControlsHide(forLandscapeVideo: landscapeVideo) }
                        }
                } else {
                    audioArtwork
                }

                if showsControls {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Button {
                                playback.minimizePlayerSurface()
                            } label: {
                                Label("Minimize", systemImage: "chevron.down")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .background(Color.black.opacity(0.64), in: Capsule())
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                playback.dismissPlayerSurface()
                            } label: {
                                Label("Stop", systemImage: "xmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .background(Color.black.opacity(0.64), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        Spacer()

                        mediaControls
                            .padding(.horizontal, landscapeVideo ? 40 : 20)
                            .padding(.bottom, landscapeVideo ? 8 : 20)
                    }
                    .transition(.opacity)
                }
            }
            .statusBarHidden(landscapeVideo && !showsControls)
            .onAppear {
                controlsVisible = !landscapeVideo
                scheduleControlsHide(forLandscapeVideo: landscapeVideo)
            }
            .onChange(of: landscapeVideo) { _, isLandscape in
                controlsVisible = !isLandscape
                scheduleControlsHide(forLandscapeVideo: isLandscape)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityAddTraits(.isModal)
        .animation(.easeOut(duration: 0.16), value: controlsVisible)
        .onDisappear { hideControlsTask?.cancel() }
    }

    private var audioArtwork: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 112, weight: .light))
                .foregroundStyle(Color.browserAccent)
            Text(playback.currentItem?.title ?? "Audio")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 32)
        }
    }

    private var mediaControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(playback.currentItem?.title ?? "Media")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)

            if let playbackError = playback.playbackError {
                Label(playbackError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Slider(
                value: Binding(
                    get: { playback.elapsedTime },
                    set: { playback.seek(to: $0) }
                ),
                in: 0 ... max(playback.duration, 1)
            )
            .tint(.white)
            .disabled(playback.duration <= 0)

            HStack {
                Text(format(playback.elapsedTime))
                Spacer()
                Text(playback.duration > 0 ? format(playback.duration) : "–:––")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.72))

            HStack(spacing: 28) {
                Spacer()

                Button {
                    playback.seek(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back 15 seconds")

                Button(action: playback.togglePlayback) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 25, weight: .bold))
                        .frame(width: 58, height: 58)
                        .background(Color.white, in: Circle())
                        .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                Button {
                    playback.seek(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Forward 15 seconds")

                Spacer()
            }
            .foregroundStyle(.white)

            HStack(spacing: 12) {
                Menu {
                    ForEach(BrowserMediaPlaybackController.supportedRates, id: \.self) { rate in
                        Button {
                            playback.setPlaybackRate(rate)
                        } label: {
                            if playback.playbackRate == rate {
                                Label(Self.rateTitle(rate), systemImage: "checkmark")
                            } else {
                                Text(Self.rateTitle(rate))
                            }
                        }
                    }
                } label: {
                    Label(Self.rateTitle(playback.playbackRate), systemImage: "speedometer")
                        .frame(minWidth: 80, minHeight: 44)
                }

                if let item = playback.currentItem, let onTranscribe {
                    Button {
                        onTranscribe(item)
                    } label: {
                        Label("Transcribe", systemImage: "waveform.and.magnifyingglass")
                            .frame(minHeight: 44)
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
        }
        .padding(16)
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private static func rateTitle(_ rate: Double) -> String {
        rate == floor(rate) ? "\(Int(rate))×" : "\(rate.formatted(.number.precision(.fractionLength(2))))×"
    }

    private func scheduleControlsHide(forLandscapeVideo isLandscapeVideo: Bool) {
        hideControlsTask?.cancel()
        guard isLandscapeVideo, controlsVisible else { return }
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }
}

private struct BrowserVideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> BrowserPlayerLayerView {
        let view = BrowserPlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: BrowserPlayerLayerView, context: Context) {
        view.playerLayer.player = player
    }
}

private final class BrowserPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }
}

struct BrowserMediaMiniPlayer: View {
    @ObservedObject var playback: BrowserMediaPlaybackController

    var body: some View {
        if let item = playback.currentItem {
            HStack(spacing: 12) {
                if item.kind == .video {
                    Button {
                        playback.restorePlayerSurface()
                    } label: {
                        mediaIdentity(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open media player")
                } else {
                    Button {
                        playback.restorePlayerSurface()
                    } label: {
                        mediaIdentity(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open media player")
                }

                Spacer(minLength: 4)

                if item.kind == .audio {
                    Button {
                        playback.seek(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .frame(width: 36, height: 44)
                    }
                    .accessibilityLabel("Back 15 seconds")
                }

                Button(action: playback.togglePlayback) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                if item.kind == .video {
                    Button(action: playback.restorePlayerSurface) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 36, height: 44)
                    }
                    .accessibilityLabel("Open media player")
                }

                Button(action: playback.stop) {
                    Image(systemName: "xmark")
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel("Stop playback")
            }
            .foregroundStyle(Color.browserInk)
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(minHeight: 56)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.browserInk.opacity(0.08))
            }
            .shadow(color: Color.browserInk.opacity(0.14), radius: 14, y: 5)
        }
    }

    private var playbackTime: String {
        let elapsed = format(playback.elapsedTime)
        guard playback.duration > 0 else { return elapsed }
        return "\(elapsed) / \(format(playback.duration))"
    }

    private func mediaIdentity(_ item: BrowserMediaItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .audio ? "waveform" : "play.rectangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.browserAccent)
                .frame(width: 32, height: 32)
                .background(Color.browserAccent.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.browserInk)
                    .lineLimit(1)

                Text(playbackTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
