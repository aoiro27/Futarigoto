import SwiftUI
import SwiftData

struct ReviewTabView: View {
    @Environment(AppSession.self) private var session
    @Query private var agreements: [Agreement]
    @Query private var members: [HouseholdMember]
    @Query private var reflections: [WeeklyReflection]

    @State private var presentedReview: PresentedReview?
    @State private var isRefreshing = false

    private var today: Date {
        let _ = (agreements.count, members.count, reflections.count)
        return session.todayReviewDate()
    }

    private var historyDays: [Date] {
        session.pastReviewDates()
    }

    var body: some View {
        let _ = session.syncRevision
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenHeader(eyebrow: "LOOK BACK TOGETHER", title: "ふりかえり")

                    IllustratedBanner(
                        title: "お互いの気持ちに、耳をすます時間。",
                        subtitle: "自分のことと相手のことを見て、\n見え方のちがいも残しましょう。",
                        scene: .home,
                        color: AppTheme.lavender
                    )

                    todayCard

                    historySection

                    if session.cloudPublishFailed {
                        Text("同期に失敗しました。画面を下に引っ張って、もう一度試してください。")
                            .font(.bodyRounded(14))
                            .foregroundStyle(AppTheme.terracotta)
                            .lineSpacing(3)
                    }
                }
                .padding(20)
                .readableWidth()
            }
            .screenBackground()
            .refreshable {
                await reloadFromCloud()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $presentedReview) { item in
                WeeklyReviewFlowView(reviewDate: item.date, readOnly: item.readOnly)
            }
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppWeek.dayLabel(for: today))
                .font(.bodyRounded(13, weight: .semibold))
                .foregroundStyle(AppTheme.terracotta)
            Text(reviewCardTitle)
                .font(.titleRounded(22))
                .foregroundStyle(AppTheme.ink)
            Text(reviewCardBody)
                .font(.bodyRounded(15))
                .foregroundStyle(AppTheme.inkMuted)
                .lineSpacing(4)

            Button {
                presentedReview = PresentedReview(
                    date: today,
                    readOnly: session.hasCompletedOwnReview(reviewDate: today)
                )
            } label: {
                HStack {
                    Text(reviewButtonTitle)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("これまでのふりかえり")
                .font(.titleRounded(22))
                .foregroundStyle(AppTheme.ink)

            if historyDays.isEmpty {
                EmptyNote(text: "まだありません", symbol: "text.bubble")
            } else {
                VStack(spacing: 10) {
                    ForEach(historyDays, id: \.self) { day in
                        Button {
                            presentedReview = PresentedReview(date: day, readOnly: true)
                        } label: {
                            HStack {
                                Text(AppWeek.dayLabel(for: day))
                                    .font(.bodyRounded(16, weight: .medium))
                                    .foregroundStyle(AppTheme.ink)
                                Spacer()
                                if let status = historyStatus(for: day) {
                                    Text(status)
                                        .font(.bodyRounded(13))
                                        .foregroundStyle(AppTheme.inkMuted)
                                }
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

    private var reviewCardTitle: String {
        if session.hasCompletedOwnReview(reviewDate: today),
           session.partner == nil || session.bothCompletedReview(reviewDate: today) {
            return "今日のふりかえり"
        }
        if session.hasCompletedOwnReview(reviewDate: today) {
            return "相手の入力待ち"
        }
        return AppCopy.weekReviewTitle
    }

    private var reviewCardBody: String {
        if session.hasCompletedOwnReview(reviewDate: today),
           session.partner == nil || session.bothCompletedReview(reviewDate: today) {
            return "今日はもう入力できません。結果はいつでも見返せます。"
        }
        if session.hasCompletedOwnReview(reviewDate: today) {
            return "相手の入力がそろうと、ふたりの答えと日々の記録を見られます。"
        }
        return "自分のことと相手のことを見て、見え方のちがいも残しましょう。"
    }

    private var reviewButtonTitle: String {
        if session.hasCompletedOwnReview(reviewDate: today),
           session.partner == nil || session.bothCompletedReview(reviewDate: today) {
            return "ふたりのふりかえりを見る"
        }
        if session.hasCompletedOwnReview(reviewDate: today) {
            return "自分のふりかえりを見る"
        }
        return "今日をふりかえる"
    }

    private func historyStatus(for day: Date) -> String? {
        if session.partner != nil,
           session.hasCompletedOwnReview(reviewDate: day),
           !session.bothCompletedReview(reviewDate: day) {
            return "相手待ち"
        }
        return nil
    }

    private func reloadFromCloud() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await session.refreshFromCloud(markFailure: true)
    }
}
