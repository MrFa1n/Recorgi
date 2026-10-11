import ScreenCaptureKit
import RecorgiCore

public struct RunningApplicationProvider: Sendable {
    public init() {}

    /// Apps with on-screen windows right now, usable as a system-audio
    /// scope. Requires screen-recording permission (already requested at
    /// launch) since it goes through the same ScreenCaptureKit content API.
    public func availableApplications() async throws -> [AudioApplication] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            Log.devices.error("availableApplications(): SCShareableContent fetch failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        var seen = Set<Int32>()
        var apps: [AudioApplication] = []
        for app in content.applications where !app.applicationName.isEmpty {
            guard seen.insert(app.processID).inserted else { continue }
            apps.append(AudioApplication(processID: app.processID, bundleIdentifier: app.bundleIdentifier, name: app.applicationName))
        }
        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        Log.devices.debug("availableApplications(): found \(sorted.count, privacy: .public)")
        return sorted
    }
}
