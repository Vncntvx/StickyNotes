import Testing
import Foundation
import Domain
import Persistence

// MARK: - Bounded busy timeout binding tests (T192, FR-140a clarified 2026-08-07)
//
// Per tasks.md T192: DatabaseStore default busyTimeout == 5.0 — concurrent
// WAL access waits a bounded time instead of blocking indefinitely.

@Suite struct BusyTimeoutBindingTests {

    @Test
    func databaseStoreDefaultBusyTimeoutIs5Seconds() throws {
        #expect(DatabaseStore.defaultBusyTimeout == 5.0)
    }

    @Test
    func databaseStoreInMemoryUsesShorterTimeoutForTests() throws {
        // The inMemory() factory uses a 1.0s timeout to keep tests fast,
        // but it's still a bounded timeout (never infinite).
        let store = try DatabaseStore.inMemory()
        #expect(store.busyTimeout == 1.0)
    }

    @Test
    func busyTimeoutIsFiniteAndBounded() throws {
        // The production default is exactly 5.0s (FR-140a).
        #expect(DatabaseStore.defaultBusyTimeout == 5.0)
        // It's finite (never infinite/indefinite).
        #expect(DatabaseStore.defaultBusyTimeout > 0)
        #expect(DatabaseStore.defaultBusyTimeout.isFinite)
    }
}
