import Combine
import Foundation

/// The running app's configuration. The menu, Settings, and dictation read it here instead of from disk.
@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var config: Config
    private var observers: [(_ old: Config, _ new: Config) -> Void] = []

    init(config: Config = Config.load()) {
        self.config = config
    }

    /// Saves an edit, then notifies observers. Nothing changes if saving fails.
    func update(_ edit: (inout Config) -> Void) throws {
        var updated = config
        edit(&updated)
        try updated.save()
        replace(with: updated)
    }

    /// Reads the file again to apply edits made outside the app.
    func reload() {
        replace(with: Config.load())
    }

    func observe(_ observer: @escaping (_ old: Config, _ new: Config) -> Void) {
        observers.append(observer)
    }

    private func replace(with new: Config) {
        let old = config
        config = new
        for observer in observers { observer(old, new) }
    }
}
