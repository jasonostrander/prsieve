import AppKit
import Foundation
import UserNotifications

private let userInfoURLKey = "pr_url"

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
            authorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            authorized = false
        }
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
