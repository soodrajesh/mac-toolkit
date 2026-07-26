import AVFoundation

/// Simple play/pause/seek transport for previewing a local audio file while
/// picking cut points. Always plays the original source file, not a live
/// preview of pending edits — precise enough for finding in/out points.
@MainActor
final class AudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) {
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        currentTime = 0
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying { pause() } else { play() }
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func seek(to time: Double) {
        player?.currentTime = max(0, time)
        currentTime = max(0, time)
    }

    func stop() {
        player?.stop()
        isPlaying = false
        timer?.invalidate()
        currentTime = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.timer?.invalidate()
        }
    }
}
