import Foundation

/// Sparkle-free interface so non-app-entry-point files don't need to import Sparkle
/// (keeps the test build, which excludes PRSieveApp.swift, compiling without Sparkle).
@MainActor
protocol UpdaterServicing: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}
