import SwiftUI
import SwiftData
import UserNotifications

@main
struct WagayanoYakusokuApp: App {
    @State private var session = AppSession()
    private let notificationDelegate = NotificationDelegate()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            Household.self,
            HouseholdMember.self,
            Agreement.self,
            DailyObservation.self,
            WeeklyReflection.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("ModelContainer を作成できませんでした: \(error)")
        }
    }()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(AppTheme.terracotta)
                .preferredColorScheme(.light)
                .onAppear {
                    session.attach(modelContext: sharedModelContainer.mainContext)
                    NotificationService.shared.scheduleWeeklyReviewReminder()
                }
                .onOpenURL { url in
                    session.handleIncomingURL(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
