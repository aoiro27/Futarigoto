import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var tab: MainTab
    @Environment(AppSession.self) private var session
    @Query private var agreements: [Agreement]
    @Query private var members: [HouseholdMember]
    @Query private var reflections: [WeeklyReflection]

    @State private var showsObservation = false
    @State private var presentedReview: PresentedReview?
    @State private var showsInvite = false

    private var householdAgreements: [Agreement] {
        guard let householdId = session.currentHouseholdID else { return [] }
        return agreements
            .filter { $0.householdId == householdId && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var today: Date {
        let _ = (agreements.count, members.count, reflections.count)
        return session.todayReviewDate()
    }

    var body: some View {
        let _ = session.syncRevision
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
                Button {
                    showsObservation = true
                } label: {
                    Label(AppCopy.addToday, systemImage: "square.and.pencil")
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
            .fullScreenCover(item: $presentedReview) { item in
                WeeklyReviewFlowView(reviewDate: item.date, readOnly: item.readOnly)
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ふたりの毎日に、よりそって")
                        .font(.bodyRounded(13))
                        .foregroundStyle(AppTheme.terracotta)
                    Text(AppCopy.homeHeader)
                        .font(.titleRounded(30))
                        .foregroundStyle(AppTheme.ink)
                }
                Spacer(minLength: 0)
                WarmMotif(symbol: "house.fill")
            }
            .padding(.bottom, 12)

            HStack(spacing: 12) {
                if let user = session.currentUser {
                    Text(user.displayName)
                        .font(.bodyRounded(14, weight: .medium))
                        .foregroundStyle(AppTheme.inkMuted)
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
        VStack(alignment: .leading, spacing: 16) {
            WarmMotif(symbol: "heart.text.square")
            Text(reviewCardTitle)
                .font(.titleRounded(24))
                .foregroundStyle(AppTheme.ink)
            Text(reviewCardBody)
                .font(.bodyRounded(16))
                .foregroundStyle(AppTheme.inkMuted)
                .lineSpacing(4)
            Button(reviewButtonTitle) {
                presentedReview = PresentedReview(
                    date: today,
                    readOnly: session.hasCompletedOwnReview(reviewDate: today)
                )
            }
            .buttonStyle(PrimaryButtonStyle())

            NavigationLink {
                ReviewHistoryView()
            } label: {
                Text("これまでのふりかえり")
                    .font(.bodyRounded(14, weight: .medium))
                    .foregroundStyle(AppTheme.terracotta)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.terracottaSoft)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var reviewCardTitle: String {
        if session.hasCompletedOwnReview(reviewDate: today),
           session.partner == nil || session.bothCompletedReview(reviewDate: today) {
            return "今日のふりかえり"
        }
        if session.hasCompletedOwnReview(reviewDate: today) {
            return "相手のふりかえりを待っています"
        }
        return AppCopy.weekReviewTitle
    }

    private var reviewCardBody: String {
        if session.hasCompletedOwnReview(reviewDate: today),
           session.partner == nil || session.bothCompletedReview(reviewDate: today) {
            return "今日はもう入力できません。結果はいつでも見返せます。"
        }
        if session.hasCompletedOwnReview(reviewDate: today) {
            return "相手の入力がそろうと、ふたりの答えと日々の想いを見られます。"
        }
        return AppCopy.weekReviewBody
    }

    private var reviewButtonTitle: String {
        if session.hasCompletedOwnReview(reviewDate: today),
           session.partner == nil || session.bothCompletedReview(reviewDate: today) {
            return "今日の結果を見る"
        }
        if session.hasCompletedOwnReview(reviewDate: today) {
            return "ふりかえりを開く"
        }
        return AppCopy.weekReviewAction
    }

    private var agreementsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppCopy.agreements)
                    .font(.titleRounded(22))
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
