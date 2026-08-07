import Foundation
import Domain

// MARK: - AppDevice (device-local identity)
//
// A stable device UUID persisted in App Group UserDefaults (device-local,
// never synchronized). Used for note version lineage
// (`Note.lastModifiedDeviceId`) per data-model.md §DeviceIdentity.

public enum AppDevice {
    private static let key = "local.stickynotes.deviceId"

    /// The stable local device identity (created on first access).
    public static func current(defaults: UserDefaults = UserDefaults(suiteName: "group.local.stickynotes.placeholder") ?? .standard) -> DeviceIdentity {
        if let saved = defaults.string(forKey: key), let id = UUID(uuidString: saved) {
            return DeviceIdentity(id: id, displayName: Host.current().localizedName ?? "This Mac")
        }
        let identity = DeviceIdentity(displayName: Host.current().localizedName ?? "This Mac")
        defaults.set(identity.id.uuidString, forKey: key)
        return identity
    }
}

extension DeviceIdentity {
    /// The stable local device identity (App-layer convenience).
    public static var current: DeviceIdentity { AppDevice.current() }
}
