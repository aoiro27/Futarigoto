import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var tab: MainTab
    @Environment(AppSession.self) private var session
    @Query private var agreements: [Agreement]
    @Query private var members: [HouseholdMember]
    @Query private var reflections: [WeeklyReflection]

    @State private var showsObservation = false
    @State private var showsReview = false
    @State private var showsInvite = false

    private var householdAgreements: [Agreement] {
        guard let householdId = session.currentHouseholdID else { return [] }
        return agreements
            .filter { $0.householdId == householdId && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var reviewWeek: Date? {
        let _ = (agreements.count, members.count, reflections.count)
        return session.reviewWeekStart()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    weekCard
                    agreementsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
                .readableWidth()
            }
            .screenBackground()
            .overlay(alignment: .bottom) {
                Button(AppCopy.addToday) {
                    showsObservation = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(
                    AppTheme.cream.opacity(0.96)
                        .ignoresSafeArea(edges: .bottom)
                )
                .readableWidth()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsObservation) {
                ObservationFlowView()
            }
            .fullScreenCover(isPresented: $showsReview) {
                if let reviewWeek {
                    WeeklyReviewFlowView(weekStart: reviewWeek)
                }
            }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(AppCopy.homeHeader)
                .font(.titleSerif(34))
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 12) {
                if let user = session.currentUser {
                    Menu {
                        ForEach(session.householdMembers, id: \.id) { member in
                            Button(member.displayName) {
                                session.switchToUser(member)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("いま：\(user.displayName)")
                            if session.householdMembers.count > 1 {
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                        }
                        .font(.bodyRounded(14, weight: .medium))
                        .foregroundStyle(AppTheme.inkMuted)
                    }
                }

                Spacer()

                if session.canInvitePartner {
                    Button("パートナーを招待") {
                        showsInvite = true
                    }
                    .font(.bodyRounded(14, weight: .medium))
                    .foregroundStyle(AppTheme.terracotta)
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var weekCard: some View {
        if reviewWeek != nil {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppCopy.weekReviewTitle)
                    .font(.titleSerif(24))
                    .foregroundStyle(AppTheme.ink)
                Text(AppCopy.weekReviewBody)
                    .font(.bodyRounded(16))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineSpacing(4)
                Button(reviewButtonTitle) {
                    showsReview = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.terracottaSoft)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppCopy.weekUsualTitle)
                    .font(.titleSerif(24))
                    .foregroundStyle(AppTheme.ink)
                Text(AppCopy.weekUsualBody)
                    .font(.bodyRounded(16))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineSpacing(4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        }
    }

    private var reviewButtonTitle: String {
        guard let week = reviewWeek else { return AppCopy.weekReviewAction }
        if session.hasCompletedOwnReview(weekStart: week),
           session.bothCompletedReview(weekStart: week) {
            return "相手が感じたことを見る"
        }
        if session.hasCompletedOwnReview(weekStart: week) {
            return "ふりかえりを続ける"
        }
        return AppCopy.weekReviewAction
    }

    private var agreementsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppCopy.agreements)
                    .font(.titleSerif(22))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Button("すべて見る") {
                    tab = .agreements
                }
                .font(.bodyRounded(14, weight: .medium))
                .foregroundStyle(AppTheme.terracotta)
            }

            if householdAgreements.isEmpty {
                EmptyNote(text: "ふたりで話して、最初の約束を残してみましょう。")
            } else {
                VStack(spacing: 10) {
                    ForEach(householdAgreements) { agreement in
                        NavigationLink {
                            AgreementDetailView(agreementID: agreement.id)
                        } label: {
                            HStack {
                                Text(agreement.title)
                                    .font(.bodyRounded(16))
                                    .foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            .padding(18)
                            .appCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
