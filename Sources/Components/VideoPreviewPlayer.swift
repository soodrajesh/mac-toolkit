import SwiftUI
import AVFoundation
import QuartzCore

/// Play/pause/seek transport for an AVPlayer, driving a plain AVPlayerLayer
/// surface (not AVKit's SwiftUI VideoPlayer — its private companion framework
/// crashes at runtime in this project's non-Xcode swiftc build).
@MainActor
final class VideoPlayerController: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var failed = false

    let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObs: NSKeyValueObservation?
    private var durationObs: NSKeyValueObservation?
    private var endObs: NSObjectProtocol?

    func load(url: URL) {
        stop()
        failed = false
        let item = AVPlayerItem(url: url)
        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.failed = true }
        }
        durationObs = item.observe(\.duration, options: [.new]) { [weak self] item, _ in
            let d = CMTimeGetSeconds(item.duration)
            guard d.isFinite, d > 0 else { return }
            Task { @MainActor [weak self] in self?.duration = d }
        }
        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.failed = true }
        }
        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
        }
    }

    func togglePlayPause() { isPlaying ? pause() : play() }
    func play() { player.play(); isPlaying = true }
    func pause() { player.pause(); isPlaying = false }
    func seek(to time: Double) {
        player.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600))
        currentTime = max(0, time)
    }

    func stop() {
        player.pause(); isPlaying = false
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        endObs = nil
        statusObs = nil; durationObs = nil
        duration = 0; currentTime = 0
    }

    deinit {
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
    }
}

/// AppKit surface for AVPlayerLayer — plain AVFoundation, no AVKit.
private final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        return view
    }
    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.playerLayer.player = player
    }
}

/// A play/pause/scrub video preview. Falls back to a static thumbnail with an
/// explanation if the source can't actually be decoded for playback — the
/// same codec wall VideoService.convert works around for export.
struct VideoPreviewPlayer: View {
    let url: URL
    var fallbackThumbnail: NSImage?
    @StateObject private var controller = VideoPlayerController()

    var body: some View {
        VStack(spacing: 8) {
            if controller.failed {
                VStack(spacing: 6) {
                    ImagePreview(image: fallbackThumbnail)
                    Text("Live preview isn't available for this codec — showing a static frame instead.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                PlayerLayerView(player: controller.player)
                    .frame(minHeight: 240)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
                controls
            }
        }
        .onAppear { controller.load(url: url) }
        .onChange(of: url) { controller.load(url: $0) }
        .onDisappear { controller.stop() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: controller.togglePlayPause) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(controller.duration <= 0)

            Slider(
                value: Binding(get: { controller.currentTime }, set: { controller.seek(to: $0) }),
                in: 0...max(controller.duration, 0.01)
            )
            .disabled(controller.duration <= 0)

            Text("\(format(controller.currentTime)) / \(format(controller.duration))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
