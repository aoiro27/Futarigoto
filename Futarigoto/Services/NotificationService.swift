import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    private let weeklyIdentifier = "weekly-review-reminder"

    private init() {}

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                self.scheduleWeeklyReviewReminder()
            }
        }
    }

    func scheduleWeeklyReviewReminder() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            self.center.removePendingNotificationRequests(withIdentifiers: [self.weeklyIdentifier])

            let content = UNMutableNotificationContent()
            content.title = AppCopy.weeklyNoticeTitle
            content.body = AppCopy.weeklyNoticeBody
            content.sound = .default

            var date = DateComponents()
            date.hour = 21
            date.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(
                identifier: self.weeklyIdentifier,
                content: content,
                trigger: trigger
            )
            self.center.add(request)
        }
    }

    func notifyBothReflectionsReady() {
        let content = UNMutableNotificationContent()
        content.title = AppCopy.bothReadyTitle
        content.body = AppCopy.bothReadyBody
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "both-reflections-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }
}
