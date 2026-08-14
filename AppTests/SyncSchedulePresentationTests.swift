import Testing
@testable import StickyNotes

// MARK: - 003 T185 (FR-053 Rev 3, 2026-08-14)

/// The periodic-sync schedule presentation: display names and the
/// enablement policy. Rev 3: the schedule is a device-local preference
/// (001 FR-152) — a locked vault no longer disables configuring it; only
/// the automatic-sync master switch does.
struct SyncSchedulePresentationTests {

    // MARK: AutoSyncPolicy display names

    @Test func changeOnlyDisplaysAsOff() {
        #expect(AutoSyncPolicy.changeOnly.displayName == "Off",
                "the periodic-sync picker shows Off for change-only (Rev 3)")
    }

    @Test func displayNamesAreDistinct() {
        let names = Set(AutoSyncPolicy.allCases.map(\.displayName))
        #expect(names.count == AutoSyncPolicy.allCases.count)
    }

    @Test func periodicIntervalsUnchanged() {
        // 001 FR-152 semantics unchanged — only copy changed.
        #expect(AutoSyncPolicy.changeOnly.interval == nil)
        #expect(AutoSyncPolicy.every5.interval == 300)
        #expect(AutoSyncPolicy.every15.interval == 900)
        #expect(AutoSyncPolicy.every30.interval == 1800)
        #expect(AutoSyncPolicy.every60.interval == 3600)
    }

    // MARK: SyncSchedulePresentation.periodicPickerEnabled (Rev 3)

    @Test func lockedVaultNoLongerDisablesTheSchedule() {
        #expect(SyncSchedulePresentation.periodicPickerEnabled(autoSyncEnabled: true, isVaultUnlocked: false) == true,
                "device-local schedule stays configurable while locked (FR-053 Rev 3)")
    }

    @Test func masterSwitchOffDisablesTheSchedule() {
        #expect(SyncSchedulePresentation.periodicPickerEnabled(autoSyncEnabled: false, isVaultUnlocked: true) == false)
        #expect(SyncSchedulePresentation.periodicPickerEnabled(autoSyncEnabled: false, isVaultUnlocked: false) == false)
    }

    @Test func enabledOnlyWhenMasterSwitchOn() {
        #expect(SyncSchedulePresentation.periodicPickerEnabled(autoSyncEnabled: true, isVaultUnlocked: true) == true)
    }
}
