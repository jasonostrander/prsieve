import AppKit
import Foundation
import UserNotifications

private let userInfoURLKey = "pr_url"

/// Public-facing authorization state for UI flows.
enum NotificationAuthState: Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private var notifiedPRIDs: Set<String> = []
    private(set) var authorized = false
    private let persistence: PersistenceService

    init(persistence: PersistenceService) {
        self.persistence = persistence
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        notifiedPRIDs = await persistence.loadNotifiedPRIDs()
        do {
            authorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            authorized = false
        }
    }

    // MARK: - Static helpers (usable from setup flows without an instance)

    /// Returns the current system authorization status without prompting the user.
    static func systemAuthorizationState() async -> NotificationAuthState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .notDetermined
        }
    }

    /// Triggers the system permission prompt the first time, and returns the resulting status.
    /// On subsequent calls (after the user already chose), this just returns the stored status
    /// — macOS will not show the dialog again.
    @discardableResult
    static func requestSystemAuthorization() async -> NotificationAuthState {
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // fall through and report the current state
        }
        return await systemAuthorizationState()
    }

    /// Opens System Settings → Notifications, scoped to this app when possible.
    static func openSystemSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let scoped = "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleID)"
        let fallback = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        if !bundleID.isEmpty, let url = URL(string: scoped) {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = URL(string: fallback) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Send notifications for new priority PRs with passing CI that haven't been reviewed yet.
    func notifyIfNeeded(prs: [PullRequest], username: String = "") async {
        guard authorized else { return }

        let actionable = prs.filter {
            guard $0.category == .priority && $0.buildStatus == .passed else { return false }
            guard !notifiedPRIDs.contains($0.id) else { return false }
            // Don't re-notify for PRs the user has already reviewed
            if !username.isEmpty && $0.reviewers.contains(where: {
                $0.login.caseInsensitiveCompare(username) == .orderedSame && $0.state != .pending
            }) { return false }
            return true
        }

        for pr in actionable {
            sendNotification(for: pr)
            notifiedPRIDs.insert(pr.id)
        }
        if !actionable.isEmpty {
            await persistence.saveNotifiedPRIDs(notifiedPRIDs)
        }
    }

    /// Clear tracked IDs for PRs that are no longer open, to keep the set bounded.
    func pruneNotified(currentPRIDs: Set<String>) async {
        let pruned = notifiedPRIDs.intersection(currentPRIDs)
        if pruned.count != notifiedPRIDs.count {
            notifiedPRIDs = pruned
            await persistence.saveNotifiedPRIDs(notifiedPRIDs)
        }
    }

    private func sendNotification(for pr: PullRequest) {
        let content = UNMutableNotificationContent()
        content.title = "PR Ready for Review"
        content.body = "\(pr.repoShortName)#\(pr.number): \(pr.title)"
        content.sound = .default
        content.userInfo = [userInfoURLKey: pr.htmlURL.absoluteString]

        let request = UNNotificationRequest(
            identifier: pr.id,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo[userInfoURLKey] as? String, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
