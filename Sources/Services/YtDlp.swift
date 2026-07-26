import Foundation

enum YtDlp {

    enum VideoQuality: String, CaseIterable, Identifiable {
        case best = "best"
        case p1080 = "1080p"
        case p720 = "720p"
        case p480 = "480p"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .best: return "Best available"
            case .p1080: return "1080p"
            case .p720: return "720p"
            case .p480: return "480p"
            }
        }

        var formatSelector: String {
            switch self {
            case .best: return "bestvideo+bestaudio/best"
            case .p1080: return "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080]"
            case .p720: return "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720]"
            case .p480: return "bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[height<=480]"
            }
        }
    }

    enum AudioBitrate: Int, CaseIterable, Identifiable {
        case kbps128 = 128
        case kbps192 = 192
        case kbps320 = 320

        var id: Int { rawValue }
        var label: String { "\(rawValue) kbps" }
    }

    enum Format {
        case mp4(VideoQuality)
        case mp3(AudioBitrate)
    }

    static let ytDlpPath: String? = {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["which", "yt-dlp"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) { return out }
        } catch { }
        return nil
    }()

    static let ffmpegPath: String? = {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["which", "ffmpeg"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) { return out }
        } catch { }
        return nil
    }()

    static var isAvailable: Bool { ytDlpPath != nil && ffmpegPath != nil }

    static func download(url: String, to outputDir: URL, format: Format, isCancelled: @escaping () -> Bool = { false }, onProgress: @escaping (Double, String) -> Void) throws -> URL {
        if isCancelled() { throw JobError.failed("Cancelled") }
        guard let yt = ytDlpPath else { throw JobError.failed("yt-dlp not found") }
        guard let ffmpeg = ffmpegPath else { throw JobError.failed("ffmpeg not found") }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: yt)

        let outputPattern = "\(outputDir.path)/%(title).150s.%(ext)s"
        var args: [String] = []

        let expectedExt: String
        switch format {
        case .mp4(let quality):
            expectedExt = "mp4"
            args = [
                "-f", quality.formatSelector,
                "--merge-output-format", "mp4",
                "--ffmpeg-location", ffmpeg,
                "--no-playlist",
                "--newline",
                "-o", outputPattern,
                "--no-keep-fragments",
                "--print", "after_move:filepath",
                url
            ]
        case .mp3(let bitrate):
            expectedExt = "mp3"
            args = [
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", String(bitrate.rawValue),
                "--ffmpeg-location", ffmpeg,
                "--no-playlist",
                "--newline",
                "-o", outputPattern,
                "--print", "after_move:filepath",
                url
            ]
        }

        p.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        try p.run()

        var capturedOutput = ""
        let outputQueue = DispatchQueue(label: "yt-dlp.output", qos: .userInitiated)
        let outputGroup = DispatchGroup()
        outputGroup.enter()

        outputQueue.async {
            let handle = outPipe.fileHandleForReading
            while p.isRunning {
                if let data = try? handle.availableData, !data.isEmpty {
                    let line = String(decoding: data, as: UTF8.self)
                    capturedOutput += line
                    for outputLine in line.split(separator: "\n", omittingEmptySubsequences: true) {
                        let lineStr = String(outputLine).trimmingCharacters(in: .whitespacesAndNewlines)
                        if lineStr.contains("[download]") && lineStr.contains("%") {
                            if let pctMatch = lineStr.range(of: #"([\d.]+)%"#, options: .regularExpression) {
                                let pctStr = String(lineStr[pctMatch]).replacingOccurrences(of: "%", with: "")
                                if let pct = Double(pctStr) {
                                    var sizeStr = ""
                                    if let sizeMatch = lineStr.range(of: #"of\s+~?([\d.]+[KMG]iB)"#, options: .regularExpression) {
                                        sizeStr = String(lineStr[sizeMatch]).replacingOccurrences(of: "of ", with: "")
                                    }
                                    DispatchQueue.main.async { onProgress(pct / 100, sizeStr) }
                                }
                            }
                        }
                    }
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            // Drain any remaining buffered output after the process has exited.
            let remaining = handle.readDataToEndOfFile()
            if !remaining.isEmpty {
                capturedOutput += String(decoding: remaining, as: UTF8.self)
            }
            outputGroup.leave()
        }

        p.waitUntilExit()
        outputGroup.wait()

        guard p.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(decoding: errData, as: UTF8.self)
            throw JobError.failed("Download failed: \(errMsg)")
        }

        // yt-dlp's `--print after_move:filepath` writes the final output path as the
        // last absolute-path line with the expected extension.
        let candidateLines = capturedOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("/") && $0.hasSuffix(".\(expectedExt)") }

        if let filePath = candidateLines.last, FileManager.default.fileExists(atPath: filePath) {
            return URL(fileURLWithPath: filePath)
        }

        // Fallback: search outputDir for a recently modified file with the expected extension.
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            throw JobError.failed("Cannot read output directory")
        }

        let now = Date()
        let recentFiles = files.filter { url in
            guard url.pathExtension == expectedExt else { return false }
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate else { return false }
            return now.timeIntervalSince(modDate) < 15
        }.sorted { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return aDate > bDate
        }

        guard let outputFile = recentFiles.first else {
            throw JobError.failed("Output file not found after download")
        }

        return outputFile
    }
}
