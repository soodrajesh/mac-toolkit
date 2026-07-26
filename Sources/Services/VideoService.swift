import AVFoundation
import Foundation

/// Video processing: AVFoundation first (no dependency), falling back to
/// ffmpeg (if installed — see YtDlp.ffmpegPath) when the source uses a codec
/// AVFoundation can't re-encode, e.g. VP9/AV1 from a high-res YouTube download.
enum VideoService {

    enum Preset: String, CaseIterable, Identifiable {
        case highest = "Highest Quality"
        case hd1080 = "1080p"
        case hd720 = "720p"
        case sd480 = "480p"
        case low = "Low (smallest)"
        var id: String { rawValue }
        var avPreset: String {
            switch self {
            case .highest: return AVAssetExportPresetHighestQuality
            case .hd1080:  return AVAssetExportPreset1920x1080
            case .hd720:   return AVAssetExportPreset1280x720
            case .sd480:   return AVAssetExportPreset640x480
            case .low:     return AVAssetExportPresetLowQuality
            }
        }
        /// Target height for the ffmpeg fallback's scale filter; nil = source size.
        var ffmpegHeight: Int? {
            switch self {
            case .highest: return nil
            case .hd1080:  return 1080
            case .hd720:   return 720
            case .sd480, .low: return 480
            }
        }
        var ffmpegCRF: String {
            switch self {
            case .highest: return "18"
            case .hd1080, .hd720: return "23"
            case .sd480: return "26"
            case .low: return "30"
            }
        }
    }

    enum AudioFormat: String, CaseIterable, Identifiable {
        case m4a = "M4A (AAC)"
        case mp3 = "MP3"
        var id: String { rawValue }
        var ext: String { self == .mp3 ? "mp3" : "m4a" }
    }

    /// Converts/compresses a video to MP4. Tries AVFoundation first; if that
    /// fails (commonly "operation not supported for this media" — a VP9/AV1
    /// source AVFoundation can't decode for re-encode) and ffmpeg is installed,
    /// retries via ffmpeg. Returns the actual output URL used (may differ from
    /// `output` if the container had to fall back from .mp4 to .mov).
    @discardableResult
    static func convert(_ url: URL, preset: Preset, to output: URL,
                        onProgress: (@Sendable (Double) -> Void)? = nil) throws -> URL {
        do {
            return try convertNative(url, preset: preset, to: output, onProgress: onProgress)
        } catch {
            guard let ffmpeg = YtDlp.ffmpegPath else {
                let base = (error as? JobError)?.errorDescription ?? error.localizedDescription
                throw JobError.failed("\(base) — this source likely uses a codec (e.g. VP9/AV1) AVFoundation can't re-encode. Install ffmpeg (`brew install ffmpeg`) for broader codec support.")
            }
            return try convertWithFfmpeg(url, ffmpeg: ffmpeg, preset: preset, to: output, onProgress: onProgress)
        }
    }

    private static func convertNative(_ url: URL, preset: Preset, to output: URL,
                                      onProgress: (@Sendable (Double) -> Void)?) throws -> URL {
        let asset = AVURLAsset(url: url)
        guard asset.tracks(withMediaType: .video).first != nil else {
            throw JobError.badInput("\(url.lastPathComponent) has no video track")
        }
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let chosen = compatible.contains(preset.avPreset) ? preset.avPreset : AVAssetExportPresetHighestQuality
        guard let export = AVAssetExportSession(asset: asset, presetName: chosen) else {
            throw JobError.failed("Could not create export session")
        }
        // Some presets (e.g. HEVC/10-bit sources) don't support .mp4 as an
        // output container — fall back to .mov, which every preset supports.
        export.outputFileType = export.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let finalOutput = OutputPath.retype(output, ext: export.outputFileType == .mp4 ? "mp4" : "mov")
        export.outputURL = finalOutput
        export.shouldOptimizeForNetworkUse = true
        try runExport(export, sourceName: url.lastPathComponent, onProgress: onProgress)
        return finalOutput
    }

    private static func convertWithFfmpeg(_ url: URL, ffmpeg: String, preset: Preset, to output: URL,
                                          onProgress: (@Sendable (Double) -> Void)?) throws -> URL {
        let out = OutputPath.retype(output, ext: "mp4")
        var args = ["-y", "-i", url.path]
        if let h = preset.ffmpegHeight { args += ["-vf", "scale=-2:\(h)"] }
        args += ["-c:v", "libx264", "-preset", "medium", "-crf", preset.ffmpegCRF,
                 "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out.path]
        let total = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        try runFfmpeg(ffmpeg, args: args, outputPath: out.path,
                     totalSeconds: total.isFinite && total > 0 ? total : nil, onProgress: onProgress)
        return out
    }

    /// Extracts the audio track. M4A tries AVFoundation first, falling back to
    /// ffmpeg on unsupported codecs; MP3 always uses ffmpeg (AVFoundation has
    /// no MP3 encoder). Returns the actual output URL used.
    @discardableResult
    static func extractAudio(_ url: URL, format: AudioFormat, to output: URL,
                             onProgress: (@Sendable (Double) -> Void)? = nil) throws -> URL {
        let retyped = OutputPath.retype(output, ext: format.ext)
        if format == .mp3 {
            guard let ffmpeg = YtDlp.ffmpegPath else {
                throw JobError.failed("MP3 export requires ffmpeg. Install with `brew install ffmpeg` — or choose M4A.")
            }
            let total = CMTimeGetSeconds(AVURLAsset(url: url).duration)
            try runFfmpeg(ffmpeg, args: ["-y", "-i", url.path, "-vn", "-c:a", "libmp3lame", "-b:a", "192k", retyped.path],
                         outputPath: retyped.path,
                         totalSeconds: total.isFinite && total > 0 ? total : nil, onProgress: onProgress)
            return retyped
        }
        do {
            try extractAudioNative(url, to: retyped, onProgress: onProgress)
            return retyped
        } catch {
            guard let ffmpeg = YtDlp.ffmpegPath else {
                let base = (error as? JobError)?.errorDescription ?? error.localizedDescription
                throw JobError.failed("\(base) — install ffmpeg (`brew install ffmpeg`) for broader codec support.")
            }
            let total = CMTimeGetSeconds(AVURLAsset(url: url).duration)
            try runFfmpeg(ffmpeg, args: ["-y", "-i", url.path, "-vn", "-c:a", "aac", "-b:a", "192k", retyped.path],
                         outputPath: retyped.path,
                         totalSeconds: total.isFinite && total > 0 ? total : nil, onProgress: onProgress)
            return retyped
        }
    }

    private static func extractAudioNative(_ url: URL, to output: URL,
                                           onProgress: (@Sendable (Double) -> Void)?) throws {
        let asset = AVURLAsset(url: url)
        guard asset.tracks(withMediaType: .audio).first != nil else {
            throw JobError.badInput("\(url.lastPathComponent) has no audio track")
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw JobError.failed("Could not create export session")
        }
        export.outputURL = output
        export.outputFileType = .m4a
        try runExport(export, sourceName: url.lastPathComponent, onProgress: onProgress)
    }

    /// Runs an ffmpeg subprocess, optionally parsing its stderr `time=` lines
    /// against a known total duration to report fractional progress.
    private static func runFfmpeg(_ ffmpeg: String, args: [String], outputPath: String,
                                  totalSeconds: Double?, onProgress: (@Sendable (Double) -> Void)?) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()

        var capturedErr = ""
        if let onProgress, let totalSeconds {
            let handle = err.fileHandleForReading
            let queue = DispatchQueue(label: "ffmpeg.progress", qos: .userInitiated)
            let group = DispatchGroup()
            group.enter()
            queue.async {
                while p.isRunning {
                    if let data = try? handle.availableData, !data.isEmpty {
                        let chunk = String(decoding: data, as: UTF8.self)
                        capturedErr += chunk
                        if let match = chunk.range(of: #"time=(\d+):(\d+):(\d+\.\d+)"#, options: .regularExpression) {
                            let ts = chunk[match].dropFirst(5)
                            let parts = ts.split(separator: ":").compactMap { Double($0) }
                            if parts.count == 3 {
                                let seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
                                onProgress(min(1, seconds / totalSeconds))
                            }
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }
                let remaining = handle.readDataToEndOfFile()
                if !remaining.isEmpty { capturedErr += String(decoding: remaining, as: UTF8.self) }
                group.leave()
            }
            p.waitUntilExit()
            group.wait()
        } else {
            p.waitUntilExit()
            capturedErr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: outputPath) else {
            throw JobError.failed("ffmpeg failed: \(String(capturedErr.suffix(400)))")
        }
    }

    /// Bridges the completion-handler export API to a blocking call, polling
    /// `export.progress` on a background queue if a progress callback is given.
    /// Safe here because callers always run inside JobModel.run()'s detached
    /// background Task, never on the main thread.
    private static func runExport(_ export: AVAssetExportSession, sourceName: String,
                                  onProgress: (@Sendable (Double) -> Void)?) throws {
        let sema = DispatchSemaphore(value: 0)
        var exportError: Error?
        let poller = ProgressPoller()
        if let onProgress {
            DispatchQueue(label: "video.export.progress", qos: .userInitiated).async {
                while !poller.isStopped {
                    onProgress(Double(export.progress))
                    Thread.sleep(forTimeInterval: 0.15)
                }
            }
        }
        export.exportAsynchronously {
            exportError = export.error
            poller.stop()
            sema.signal()
        }
        sema.wait()
        guard export.status == .completed else {
            if export.status == .cancelled {
                throw JobError.failed("Cancelled")
            }
            throw JobError.failed(describe(exportError, sourceName: sourceName))
        }
    }

    /// Builds a diagnostic message from an AVFoundation export error, including
    /// the nested failure reason/underlying error that `localizedDescription`
    /// alone (often just "Operation Stopped") drops.
    private static func describe(_ error: Error?, sourceName: String) -> String {
        guard let error else { return "Export failed for \(sourceName) (no error detail available)" }
        let ns = error as NSError
        var parts = [ns.localizedDescription]
        if let reason = ns.localizedFailureReason { parts.append(reason) }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("\(underlying.domain) \(underlying.code): \(underlying.localizedDescription)")
        }
        return parts.joined(separator: " — ")
    }
}

/// Thread-safe stop flag for the export-progress polling loop.
private final class ProgressPoller: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
