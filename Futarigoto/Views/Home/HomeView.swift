import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppSession.self) private var session
    @Query private var agreements: [Agreement]

    @State private var showsInvite = false
    @State private var isRefreshing = false

    private var myAgreements: [Agreement] {
        let _ = agreements.count
        guard let userId = session.currentUserID else { return [] }
        return session.applicableAgreements(for: userId)
    }

    var body: some View {
        let _ = session.syncRevision
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    agreementsSection
                    if session.cloudPublishFailed {
                        Text("同期に失敗しました。画面を下に引っ張って、もう一度試してください。")
                            .font(.bodyRounded(14))
                            .foregroundStyle(AppTheme.terracotta)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .readableWidth()
            }
            .screenBackground()
            .refreshable {
                await reloadFromCloud()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsInvite) {
                NavigationStack {
                    InvitePartnerView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("閉じる") { showsInvite = false }
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("ふたりごと")
                    .font(.titleRounded(30))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                if session.canInvitePartner {
                    Button {
                        showsInvite = true
                    } label: {
                        Label("招待", systemImage: "person.badge.plus")
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(AppTheme.paper, in: Capsule())
                    }
                    .font(.bodyRounded(14, weight: .medium))
                    .foregroundStyle(AppTheme.terracotta)
                }
                Button {
                    Task { await reloadFromCloud() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .font(.bodyRounded(16, weight: .medium))
                .foregroundStyle(AppTheme.terracotta)
                .frame(width: 44, height: 44)
                .background(AppTheme.paper, in: Circle())
                .disabled(isRefreshing)
                .accessibilityLabel("更新")
            }

            if let names = householdNames {
                Text(names)
                    .font(.bodyRounded(15, weight: .medium))
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
        .padding(.top, 8)
    }

    private var householdNames: String? {
        guard let user = session.currentUser else { return nil }
        if let partner = session.partner {
            return "\(user.displayName)と\(partner.displayName)"
        }
        return user.displayName
    }

    private func reloadFromCloud() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await session.refreshFromCloud(markFailure: true)
    }

    private var agreementsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppCopy.agreements)
                    .font(.titleRounded(22))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("\(myAgreements.count)こ")
                    .font(.bodyRounded(13, weight: .medium))
                    .foregroundStyle(AppTheme.plum)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.lavender, in: Capsule())
            }

            if myAgreements.isEmpty {
                EmptyNote(text: "約束を、ひとつずつ。", symbol: "heart", detail: "「わが家の約束」から、\n大切にしたいことを残してみましょう。")
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(myAgreements.enumerated()), id: \.element.id) { index, agreement in
                        AgreementTile(
                            title: agreement.title,
                            subtitle: session.scopeDisplay(for: agreement),
                            index: index,
                            showsDisclosure: false
                        )
                    }
                }
            }
        }
    }
}
