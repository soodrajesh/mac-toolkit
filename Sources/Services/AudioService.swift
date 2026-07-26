import AVFoundation

/// Native AVFoundation audio processing: multi-region cut (extract/delete),
/// merge, loop, and waveform peak extraction. No external binary — output is
/// always M4A/AAC since AVAssetExportSession has no MP3 encoder and no WAV preset.
enum AudioService {

    static func duration(of url: URL) throws -> Double {
        let asset = AVURLAsset(url: url)
        let d = asset.duration
        guard d.isValid, !d.isIndefinite else { throw JobError.badInput("Could not read audio duration") }
        return CMTimeGetSeconds(d)
    }

    /// One peak (max abs sample across channels) per bucket, evenly spanning the file.
    static func peaks(of url: URL, bucketCount: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { throw JobError.badInput("Empty audio file") }

        let framesPerBucket = max(1, totalFrames / bucketCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesPerBucket)) else {
            throw JobError.failed("Could not allocate audio buffer")
        }

        var peaks: [Float] = []
        while peaks.count < bucketCount, file.framePosition < file.length {
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: AVAudioFrameCount(framesPerBucket))
            guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { break }
            var peak: Float = 0
            for ch in 0..<Int(format.channelCount) {
                let ptr = data[ch]
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(ptr[i])) }
            }
            peaks.append(peak)
        }
        while peaks.count < bucketCount { peaks.append(0) }
        return peaks
    }

    enum ExtractMode: Hashable { case extract, delete }

    /// Builds one output from a set of user-drawn cut regions:
    /// - `.extract`: keep only the selected regions (in time order), each
    ///   with its own optional fade in/out.
    /// - `.delete`: keep everything *except* the selected regions (i.e. the
    ///   gaps between/around them, computed after merging any overlapping
    ///   regions). Fades aren't meaningful for the kept remainder here, so
    ///   fade flags are ignored in this mode.
    /// Multiple resulting segments are concatenated into one file — this is
    /// the "in the end it should be merged" behavior.
    static func exportRegions(_ url: URL, regions: [CutRegion], mode: ExtractMode, duration: Double, to output: URL) throws {
        guard !regions.isEmpty else { throw JobError.badInput("No regions selected") }
        let asset = AVURLAsset(url: url)
        guard let source = asset.tracks(withMediaType: .audio).first else {
            throw JobError.badInput("No audio track found")
        }

        struct Segment { var range: ClosedRange<Double>; var fadeIn: Bool; var fadeOut: Bool }
        var segments: [Segment]

        switch mode {
        case .extract:
            segments = regions
                .sorted { $0.range.lowerBound < $1.range.lowerBound }
                .map { Segment(range: $0.range, fadeIn: $0.fadeIn, fadeOut: $0.fadeOut) }
        case .delete:
            let merged = mergeRanges(regions.map { $0.range })
            var gaps: [ClosedRange<Double>] = []
            var cursor = 0.0
            for r in merged {
                if r.lowerBound > cursor { gaps.append(cursor...r.lowerBound) }
                cursor = max(cursor, r.upperBound)
            }
            if cursor < duration { gaps.append(cursor...duration) }
            segments = gaps
                .filter { $0.upperBound - $0.lowerBound > 0.01 }
                .map { Segment(range: $0, fadeIn: false, fadeOut: false) }
        }
        guard !segments.isEmpty else { throw JobError.badInput("Nothing left to export") }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw JobError.failed("Could not create composition track")
        }
        let mixParams = AVMutableAudioMixInputParameters(track: track)
        let fadeDuration = 0.4
        var anyFade = false

        var cursor = CMTime.zero
        for seg in segments {
            let start = CMTime(seconds: seg.range.lowerBound, preferredTimescale: 600)
            let dur = CMTime(seconds: seg.range.upperBound - seg.range.lowerBound, preferredTimescale: 600)
            try track.insertTimeRange(CMTimeRange(start: start, duration: dur), of: source, at: cursor)

            let fd = min(fadeDuration, CMTimeGetSeconds(dur) / 2)
            if seg.fadeIn, fd > 0 {
                mixParams.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1,
                    timeRange: CMTimeRange(start: cursor, duration: CMTime(seconds: fd, preferredTimescale: 600)))
                anyFade = true
            }
            if seg.fadeOut, fd > 0 {
                let fadeStart = cursor + dur - CMTime(seconds: fd, preferredTimescale: 600)
                mixParams.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0,
                    timeRange: CMTimeRange(start: fadeStart, duration: CMTime(seconds: fd, preferredTimescale: 600)))
                anyFade = true
            }
            cursor = cursor + dur
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw JobError.failed("Could not create export session")
        }
        export.outputURL = output
        export.outputFileType = .m4a
        if anyFade {
            let mix = AVMutableAudioMix()
            mix.inputParameters = [mixParams]
            export.audioMix = mix
        }
        try runExport(export)
    }

    /// Merges overlapping/adjacent ranges into a minimal non-overlapping set.
    private static func mergeRanges(_ ranges: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var result: [ClosedRange<Double>] = []
        for r in sorted {
            if let last = result.last, r.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
            } else {
                result.append(r)
            }
        }
        return result
    }

    static func merge(_ urls: [URL], to output: URL) throws {
        guard !urls.isEmpty else { throw JobError.emptyInput }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw JobError.failed("Could not create composition track")
        }
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let source = asset.tracks(withMediaType: .audio).first else {
                throw JobError.badInput("\(url.lastPathComponent) has no audio track")
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: source, at: cursor)
            cursor = cursor + asset.duration
        }
        try exportComposition(composition, to: output)
    }

    /// Repeats the clip back-to-back until `targetDuration`, truncating the
    /// final repeat to land exactly on time. No crossfade at loop seams —
    /// an audible click at each repeat boundary is expected v1 behavior,
    /// not a bug to be "fixed" later.
    static func loop(_ url: URL, targetDuration: Double, to output: URL) throws {
        guard targetDuration > 0 else { throw JobError.badInput("Target duration must be greater than 0") }
        let asset = AVURLAsset(url: url)
        guard let source = asset.tracks(withMediaType: .audio).first else {
            throw JobError.badInput("No audio track found")
        }
        let clip = CMTimeGetSeconds(asset.duration)
        guard clip > 0 else { throw JobError.badInput("Clip has zero duration") }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw JobError.failed("Could not create composition track")
        }

        var elapsed = 0.0
        var cursor = CMTime.zero
        while elapsed < targetDuration {
            let chunk = min(clip, targetDuration - elapsed)
            let range = CMTimeRange(start: .zero, duration: CMTime(seconds: chunk, preferredTimescale: 600))
            try track.insertTimeRange(range, of: source, at: cursor)
            cursor = cursor + range.duration
            elapsed += chunk
        }
        try exportComposition(composition, to: output)
    }

    private static func exportComposition(_ composition: AVComposition, to output: URL) throws {
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw JobError.failed("Could not create export session")
        }
        export.outputURL = output
        export.outputFileType = .m4a
        try runExport(export)
    }

    /// Bridges the completion-handler export API to a blocking call. Safe
    /// here because callers always run inside JobModel.run()'s detached
    /// background Task, never on the main thread.
    private static func runExport(_ export: AVAssetExportSession) throws {
        let sema = DispatchSemaphore(value: 0)
        var exportError: Error?
        export.exportAsynchronously {
            exportError = export.error
            sema.signal()
        }
        sema.wait()
        guard export.status == .completed else {
            throw exportError.map { JobError.failed($0.localizedDescription) } ?? JobError.failed("Export failed")
        }
    }
}
