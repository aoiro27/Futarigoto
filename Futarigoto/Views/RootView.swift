import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let _ = session.syncRevision
        Group {
            if session.showsPostCreateInvite {
                NavigationStack {
                    InvitePartnerView()
                }
            } else if session.isOnboarded {
                MainTabView()
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isOnboarded)
        .animation(.easeInOut(duration: 0.25), value: session.showsPostCreateInvite)
        .onAppear {
            session.attach(modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await session.refreshFromCloud() }
            }
        }
    }
}

enum MainTab: Hashable {
    case home
    case today
    case agreements
}

struct MainTabView: View {
    @State private var tab: MainTab = .home

    var body: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab)
                .tabItem {
                    Label("ホーム", systemImage: "house")
                }
                .tag(MainTab.home)

            ObservationListView()
                .tabItem {
                    Label("今日のこと", systemImage: "text.quote")
                }
                .tag(MainTab.today)

            AgreementListView()
                .tabItem {
                    Label("わが家の約束", systemImage: "heart")
                }
                .tag(MainTab.agreements)
        }
        .toolbarBackground(AppTheme.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
