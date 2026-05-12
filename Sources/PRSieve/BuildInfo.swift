import Foundation

// Overwritten by scripts/generate_build_info.sh at build time.
enum BuildInfo {
    static let gitHash = "dev"
    static let buildDate = "unknown"

    // Read from Info.plist at runtime — release.sh stamps the bundled plist
    // via `plutil -replace CFBundleShortVersionString`, so this reflects the
    // shipped version. Dev builds via run.sh show "0.0.0" (the source plist).
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
