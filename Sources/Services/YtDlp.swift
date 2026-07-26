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
            case .best: return "best"
            case .p1080: return "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
            case .p720: return "bestvideo[height<=720]+bestaudio/best[height<=720]"
            case .p480: return "bestvideo[height<=480]+bestaudio/best[height<=480]"
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
        guard ffmpegPath != nil else { throw JobError.failed("ffmpeg not found") }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: yt)

        let outputPattern = "\(outputDir.path)/%(title).150s.%(ext)s"
        var args: [String] = []

        switch format {
        case .mp4(let quality):
            args = [
                "-f", quality.formatSelector,
                "--merge-output-format", "mp4",
                "--no-playlist",
                "--newline",
                "-o", outputPattern,
                "--print", "after_move:filepath",
                url
            ]
        case .mp3(let bitrate):
            args = [
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", String(bitrate.rawValue),
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

        let outputQueue = DispatchQueue(label: "yt-dlp.output", qos: .userInitiated)
        let outputGroup = DispatchGroup()
        outputGroup.enter()

        outputQueue.async {
            let handle = outPipe.fileHandleForReading
            while p.isRunning {
                if let data = try? handle.availableData, !data.isEmpty {
                    let line = String(decoding: data, as: UTF8.self)
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
            outputGroup.leave()
        }

        p.waitUntilExit()
        outputGroup.wait()

        guard p.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(decoding: errData, as: UTF8.self)
            throw JobError.failed("Download failed: \(errMsg)")
        }

        // Find the downloaded file by searching for recently modified files in outputDir
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            throw JobError.failed("Cannot read output directory")
        }

        let now = Date()
        let recentFiles = files.filter { url in
            do {
                let attrs = try url.resourceValues(forKeys: [.contentModificationDateKey])
                if let modDate = attrs.contentModificationDate {
                    return now.timeIntervalSince(modDate) < 10 && url.hasDirectoryPath == false
                }
            } catch { }
            return false
        }.sorted { a, b in
            do {
                let aAttrs = try a.resourceValues(forKeys: [.contentModificationDateKey])
                let bAttrs = try b.resourceValues(forKeys: [.contentModificationDateKey])
                if let aDate = aAttrs.contentModificationDate, let bDate = bAttrs.contentModificationDate {
                    return aDate > bDate
                }
            } catch { }
            return false
        }

        guard let outputFile = recentFiles.first else {
            throw JobError.failed("No downloaded file found in output directory")
        }

        return outputFile
    }
}
