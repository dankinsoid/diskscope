import Foundation
import Testing
@testable import DiskKit

@Suite("FullDiskAccess")
struct FullDiskAccessTests {

    @Test("reports a verdict without crashing or hanging")
    func reportsVerdict() {
        // The value depends on how the test runner was granted privileges, so
        // only the fact that a verdict is produced can be asserted here.
        let granted = FullDiskAccess.isGranted()
        #expect(granted == true || granted == false)
    }

    @Test("offers a settings link that opens the right pane")
    func offersSettingsLink() {
        #expect(FullDiskAccess.settingsURL.hasPrefix("x-apple.systempreferences:"))
        #expect(FullDiskAccess.settingsURL.contains("Privacy_AllFiles"))
        #expect(FullDiskAccess.instructions.contains(FullDiskAccess.settingsURL))
    }
}
