import Foundation
import Speech
import AVFoundation

/// On-device speech-to-text via the Speech framework. Always forces
/// `requiresOnDeviceRecognition = true` — this app promises "nothing leaves
/// your Mac" (aside from the Video Downloader's explicit network use), so we
/// never fall back to Apple's server-based recognizer; if on-device support
/// isn't available for a locale, transcription fails loudly instead of
/// silently phoning home.
enum TranscriptionService {
    struct Segment { let text: String; let start: Double; let duration: Double }
    struct Result { let text: String; let segments: [Segment] }

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
    }

    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }

    /// Locales this Mac can transcribe fully on-device (no network round trip).
    static func onDeviceLocales() -> [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition ?? false }
            .sorted { $0.identifier < $1.identifier }
    }

    /// Transcribes a local audio file. Blocking — call off the main actor.
    /// Cooperatively cancellable via `Task.isCancelled`.
    static func transcribe(_ audioURL: URL, locale: Locale,
                            onProgress: (@Sendable (Double) -> Void)? = nil) throws -> Result {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw JobError.badInput("Speech recognizer unavailable for \(locale.identifier)")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw JobError.badInput("On-device transcription isn't available for \(locale.identifier) on this Mac.")
        }
        let totalDuration = CMTimeGetSeconds(AVURLAsset(url: audioURL).duration)
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        let sema = DispatchSemaphore(value: 0)
        var finalResult: SFSpeechRecognitionResult?
        var finalError: Error?
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                finalResult = result
                if totalDuration > 0, let last = result.bestTranscription.segments.last {
                    onProgress?(min(1, (last.timestamp + last.duration) / totalDuration))
                }
                if result.isFinal { sema.signal() }
            }
            if let error { finalError = error; sema.signal() }
        }
        while sema.wait(timeout: .now() + 0.3) == .timedOut {
            if Task.isCancelled { task.cancel(); throw JobError.failed("Cancelled") }
        }
        if let finalError { throw JobError.failed(finalError.localizedDescription) }
        guard let finalResult else { throw JobError.failed("No transcription result") }
        let segments = finalResult.bestTranscription.segments.map {
            Segment(text: $0.substring, start: $0.timestamp, duration: $0.duration)
        }
        return Result(text: finalResult.bestTranscription.formattedString, segments: segments)
    }

    /// Groups word segments into subtitle cues (~8 words or ~6s, whichever
    /// comes first) and renders as SRT.
    static func srt(from segments: [Segment]) -> String {
        guard !segments.isEmpty else { return "" }
        var cues: [[Segment]] = []
        var current: [Segment] = []
        for seg in segments {
            current.append(seg)
            let span = (current.first?.start).map { seg.start + seg.duration - $0 } ?? 0
            if current.count >= 8 || span >= 6 {
                cues.append(current); current = []
            }
        }
        if !current.isEmpty { cues.append(current) }

        var out = ""
        for (i, cue) in cues.enumerated() {
            guard let first = cue.first, let last = cue.last else { continue }
            let text = cue.map(\.text).joined(separator: " ")
            out += "\(i + 1)\n\(timecode(first.start)) --> \(timecode(last.start + last.duration))\n\(text)\n\n"
        }
        return out
    }

    private static func timecode(_ seconds: Double) -> String {
        let ms = Int((seconds * 1000).rounded())
        let h = ms / 3_600_000, m = (ms / 60_000) % 60, s = (ms / 1000) % 60, milli = ms % 1000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, milli)
    }
}
