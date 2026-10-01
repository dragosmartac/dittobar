import Foundation
import Testing
@testable import DittoBar

struct EntryVariableStorageTests {
    @Test func readsValuesWrittenUnderTheExistingPersistenceKey() throws {
        let suiteName = "EntryVariableStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            ["tools.md#Deploy": ["environment": "production"]],
            forKey: "commandVariableValues"
        )

        #expect(
            EntryVariableStorage.values(for: "tools.md#Deploy", defaults: defaults)
                == ["environment": "production"]
        )
    }
}
