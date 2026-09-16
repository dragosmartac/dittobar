import Foundation

/// Remembers the values last entered for each command's variables, so a
/// command reopens with what you used last rather than the Markdown defaults.
enum CommandVariableStorage {
    private static let key = "commandVariableValues"

    static func values(for storageKey: String, defaults: UserDefaults = .standard) -> [String: String] {
        stored(in: defaults)[storageKey] ?? [:]
    }

    static func save(
        _ values: [String: String],
        for storageKey: String,
        defaults: UserDefaults = .standard
    ) {
        var all = stored(in: defaults)
        all[storageKey] = values
        defaults.set(all, forKey: key)
    }

    static func clear(for storageKey: String, defaults: UserDefaults = .standard) {
        var all = stored(in: defaults)
        all.removeValue(forKey: storageKey)
        defaults.set(all, forKey: key)
    }

    private static func stored(in defaults: UserDefaults) -> [String: [String: String]] {
        defaults.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
    }
}
