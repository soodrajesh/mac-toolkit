import SwiftUI
import Foundation

struct QueueItem: Identifiable {
    let id = UUID()
    var sourceURL: String
    enum Status: Equatable {
        case queued
        case downloading(progress: Double, size: String)
        case done(URL)
        case failed(String)
    }
    var status: Status = .queued
}

@MainActor
final class DownloadQueueModel: ObservableObject {
    private static let outputKey = "lastVideoDownloadOutputDir"

    @Published var items: [QueueItem] = []
    @Published var outputDir: URL? {
        didSet {
            if let p = outputDir?.path { UserDefaults.standard.set(p, forKey: Self.outputKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.outputKey) }
        }
    }
    @Published var isRunning = false
    @Published var isCancelled = false
    private var currentTask: Task<Void, Never>?

    init() {
        if let p = UserDefaults.standard.string(forKey: Self.outputKey) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                outputDir = URL(fileURLWithPath: p, isDirectory: true)
            }
        }
    }

    func addURLs(from text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidVideoURL(trimmed), !items.contains(where: { $0.sourceURL == trimmed }) {
                items.append(QueueItem(sourceURL: trimmed))
            }
        }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items = []
    }

    func cancel() {
        isCancelled = true
        currentTask?.cancel()
    }

    func run(format: YtDlp.Format) {
        guard !items.isEmpty else { return }
        isRunning = true
        isCancelled = false
        let outDir = outputDir ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let urlsToDownload = items.map { $0.sourceURL }
        let cancelCheckClosure: () -> Bool = { [weak self] in self?.isCancelled ?? false }
        currentTask = Task.detached(priority: .userInitiated) {
            for i in urlsToDownload.indices {
                if cancelCheckClosure() {
                    break
                }
                let sourceURL = urlsToDownload[i]
                await MainActor.run {
                    if i < self.items.count {
                        self.items[i].status = .downloading(progress: 0, size: "")
                    }
                }
                do {
                    let result = try YtDlp.download(url: sourceURL, to: outDir, format: format, isCancelled: cancelCheckClosure) { progress, size in
                        DispatchQueue.main.async {
                            if i < self.items.count {
                                self.items[i].status = .downloading(progress: progress, size: size)
                            }
                        }
                    }
                    await MainActor.run {
                        if i < self.items.count {
                            self.items[i].status = .done(result)
                        }
                    }
                } catch {
                    await MainActor.run {
                        if i < self.items.count {
                            let wasCancelled = cancelCheckClosure()
                            let errMsg = wasCancelled ? "Cancelled" : error.localizedDescription
                            self.items[i].status = .failed(errMsg)
                        }
                    }
                }
            }
            await MainActor.run {
                self.isRunning = false
                self.isCancelled = false
                self.currentTask = nil
            }
        }
    }

    private func isValidVideoURL(_ str: String) -> Bool {
        return str.hasPrefix("http://") || str.hasPrefix("https://")
    }
}
