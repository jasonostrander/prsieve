import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private var notifiedPRIDs: Set<String> = []
    private(set) var authorized = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            authorized = granted
            if !granted {
                print("[Notifications] Authorization denied by user")
            }
        } catch {
            print("[Notifications] Authorization error: \(error)")
            authorized = false
        }

        // Also check current settings to see what macOS actually allows
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        print("[Notifications] Authorization status: \(settings.authorizationStatus.rawValue), alert: \(settings.alertSetting.rawValue)")
    }

    /// Send notifications for new priority PRs with passing CI.
    func notifyIfNeeded(prs: [PullRequest]) {
        guard authorized else { return }

        let actionable = prs.filter {
            $0.category == .priority && $0.buildStatus == .passed && !notifiedPRIDs.contains($0.id)
        }

        for pr in actionable {
            sendNotification(for: pr)
            notifiedPRIDs.insert(pr.id)
        }
    }

    /// Clear tracked IDs for PRs that are no longer open, to keep the set bounded.
    func pruneNotified(currentPRIDs: Set<String>) {
        notifiedPRIDs = notifiedPRIDs.intersection(currentPRIDs)
    }

    private func sendNotification(for pr: PullRequest) {
        let content = UNMutableNotificationContent()
        content.title = "PR Ready for Review"
        content.body = "\(pr.repoShortName)#\(pr.number): \(pr.title)"
        content.sound = .default
        content.userInfo = ["url": pr.htmlURL.absoluteString]

        let request = UNNotificationRequest(
            identifier: pr.id,
            content: content,
            trigger: nil  // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Notifications] Failed to deliver: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification click — open the PR URL in the browser.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }

    /// Show notifications even when app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
