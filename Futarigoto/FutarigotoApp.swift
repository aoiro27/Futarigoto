import SwiftUI
import SwiftData
import UserNotifications

@main
struct FutarigotoApp: App {
    @State private var session = AppSession()
    private let notificationDelegate = NotificationDelegate()

    var sharedModelContainer: ModelContainer = {
        makeModelContainer()
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

private func makeModelContainer() -> ModelContainer {
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
        isStoredInMemoryOnly: false,
        groupContainer: .none,
        cloudKitDatabase: .none
    )

    do {
        return try ModelContainer(for: schema, configurations: [configuration])
    } catch {
        removeStore(at: configuration.url)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("ModelContainer を作成できませんでした: \(error)")
        }
    }
}

private func removeStore(at url: URL) {
    let fileManager = FileManager.default
    let candidates = [
        url,
        URL(fileURLWithPath: url.path + "-shm"),
        URL(fileURLWithPath: url.path + "-wal")
    ]
    for file in candidates where fileManager.fileExists(atPath: file.path) {
        try? fileManager.removeItem(at: file)
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
