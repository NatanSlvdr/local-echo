import Foundation

public struct Recording {
    public let url: URL
    public let date: Date
}

public class RecordingStore {
    private final class DirectoryStorage: @unchecked Sendable {
        let lock = NSLock()
        var url = Config.configDir.appendingPathComponent("recordings")
    }

    private static let directoryStorage = DirectoryStorage()

    public static var recordingsDir: URL {
        get {
            directoryStorage.lock.lock()
            defer { directoryStorage.lock.unlock() }
            return directoryStorage.url
        }
        set {
            directoryStorage.lock.lock()
            directoryStorage.url = newValue
            directoryStorage.lock.unlock()
        }
    }

    // Show recordings saved before the app was renamed alongside new ones.
    private static var readableDirectories: [URL] {
        guard recordingsDir == Config.configDir.appendingPathComponent("recordings") else {
            return [recordingsDir]
        }
        return [recordingsDir, Config.legacyConfigDir.appendingPathComponent("recordings")]
    }

    static let filePrefix = "recording-"
    static let fileExtension = "wav"
    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    public static func ensureDirectory() {
        do {
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        } catch {
            fputs("Warning: could not create recordings directory: \(error.localizedDescription)\n", stderr)
        }
    }

    public static func tempRecordingURL() -> URL {
        let unique = String(UUID().uuidString.prefix(8))
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("local-echo-recording-\(unique).wav")
    }

    public static func newRecordingURL() -> URL {
        ensureDirectory()
        let timestamp = dateFormatter.string(from: Date())
        let unique = String(UUID().uuidString.prefix(8))
        let filename = "\(filePrefix)\(timestamp)-\(unique).\(fileExtension)"
        return recordingsDir.appendingPathComponent(filename)
    }

    public static func listRecordings() -> [Recording] {
        ensureDirectory()
        let fm = FileManager.default
        let files = readableDirectories.flatMap {
            (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.creationDateKey])) ?? []
        }

        return files
            .filter { $0.pathExtension.lowercased() == fileExtension && $0.lastPathComponent.hasPrefix(filePrefix) }
            .compactMap { url -> Recording? in
                let name = url.deletingPathExtension().lastPathComponent
                let dateString = String(name.dropFirst(filePrefix.count))
                let datePart = String(dateString.prefix(17))
                guard let date = dateFormatter.date(from: datePart) else { return nil }
                return Recording(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    public static func prune(maxCount: Int) {
        let recordings = listRecordings()
        guard recordings.count > maxCount else { return }

        let toRemove = recordings.suffix(from: maxCount)
        for recording in toRemove {
            do {
                try FileManager.default.removeItem(at: recording.url)
            } catch {
                fputs("Warning: could not remove old recording \(recording.url.path): \(error.localizedDescription)\n", stderr)
            }
        }
    }

    public static func deleteAllRecordings() {
        for recording in listRecordings() {
            do {
                try FileManager.default.removeItem(at: recording.url)
            } catch {
                fputs("Warning: could not remove recording \(recording.url.path): \(error.localizedDescription)\n", stderr)
            }
        }
    }
}
