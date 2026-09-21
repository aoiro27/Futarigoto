import SwiftUI
import SwiftData

struct WeeklyReviewFlowView: View {
    let reviewDate: Date
    var readOnly: Bool = false
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Query private var agreements: [Agreement]
    @Query private var observations: [DailyObservation]
    @Query private var reflections: [WeeklyReflection]

    @State private var drafts: [ReviewAnswer] = []
    @State private var index = 0
    @State private var phase: Phase = .selfReview

    enum Phase {
        case selfReview
        case waiting
        case recap
    }

    private var targets: [Agreement] {
        guard let userId = session.currentUserID else { return [] }
        return householdAgreements.filter { $0.applies(to: userId) }
    }

    private var householdAgreements: [Agreement] {
        guard let householdId = session.currentHouseholdID else { return [] }
        return agreements
            .filter { $0.householdId == householdId && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var current: Agreement? {
        guard index < targets.count else { return nil }
        return targets[index]
    }

    var body: some View {
        let _ = session.syncRevision
        NavigationStack {
            Group {
                switch phase {
                case .selfReview:
                    selfReviewContent
                case .waiting:
                    waitingContent
                case .recap:
                    recapContent
                        .onAppear {
                            session.revealReviewNotesIfNeeded(reviewDate: reviewDate)
                        }
                }
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
            .task {
                await session.refreshFromCloud()
                prepare()
            }
            .onChange(of: reflections.count) { _, _ in
                considerAdvanceFromWaiting()
            }
            .onChange(of: observations.count) { _, _ in
                considerAdvanceFromWaiting()
            }
            .onChange(of: session.syncRevision) { _, _ in
                considerAdvanceFromWaiting()
            }
        }
    }

    @ViewBuilder
    private var selfReviewContent: some View {
        if targets.isEmpty {
            VStack(spacing: 20) {
                ScreenHeader(
                    title: "ふりかえり",
                    subtitle: "いま残っている約束がないので、自分への質問はありません。"
                )
                Button("次へ") { finishSelfReview() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
        } else if let current {
            let answer = binding(for: current.id)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("\(index + 1) / \(targets.count)")
                        .font(.bodyRounded(13, weight: .semibold))
                        .foregroundStyle(AppTheme.terracotta)

                    Text(current.title)
                        .font(.titleRounded(26))
                        .foregroundStyle(AppTheme.ink)

                    Text(AppCopy.applicableAsk)
                        .font(.bodyRounded(17))
                        .foregroundStyle(AppTheme.inkMuted)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(SelfReflection.allCases) { option in
                            ChoiceCard(selected: answer.wrappedValue.applicable == true && answer.wrappedValue.selfReflection == option) {
                                answer.wrappedValue.applicable = true
                                answer.wrappedValue.selfReflection = option
                                goNext()
                            } content: {
                                Text(option.label)
                                    .font(.bodyRounded(16))
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }

                    Button(AppCopy.notThisWeek) {
                        answer.wrappedValue.applicable = false
                        answer.wrappedValue.selfReflection = nil
                        goNext()
                    }
                    .buttonStyle(QuietButtonStyle())
                    .frame(maxWidth: .infinity)

                    if index > 0 {
                        Button("ひとつ前へ") { index -= 1 }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(24)
                .readableWidth()
            }
        } else {
            ProgressView()
                .onAppear { finishSelfReview() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var waitingContent: some View {
        VStack(spacing: 24) {
            Spacer()
            ScreenHeader(
                title: "相手のふりかえりを待ちましょう",
                subtitle: "自分の入力は残りました。相手も終わると、ふたりの答えと日々の想いを一緒に見られます。今日はもう一度入力できません。"
            )
            Spacer()
            Button("ホームにもどる") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(28)
        .readableWidth()
    }

    private var recapContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(
                    eyebrow: AppWeek.dayLabel(for: reviewDate),
                    title: session.partner == nil ? "ふりかえり" : "ふたりのふりかえり",
                    subtitle: session.partner == nil
                        ? "自分が残したことと、そのとき見えた想いです。"
                        : "自分と相手のふりかえりと、日々残していた想いです。"
                )

                if householdAgreements.isEmpty {
                    EmptyNote(text: "見られる約束はまだありません。")
                } else {
                    ForEach(householdAgreements) { agreement in
                        recapCard(for: agreement)
                    }
                }

                Button(AppCopy.finish) {
                    session.markPartnerRevealSeen(reviewDate: reviewDate)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
            .readableWidth()
        }
    }

    private func recapCard(for agreement: Agreement) -> some View {
        let people = recapPeople(for: agreement)
        let notes = reviewNotes(for: agreement.id)

        return VStack(alignment: .leading, spacing: 16) {
            Text(agreement.title)
                .font(.titleRounded(22))
                .foregroundStyle(AppTheme.ink)

            if !people.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ふりかえり")
                        .font(.bodyRounded(13, weight: .semibold))
                        .foregroundStyle(AppTheme.terracotta)
                    ForEach(people, id: \.userId) { person in
                        HStack(alignment: .top, spacing: 12) {
                            Text(person.name)
                                .font(.bodyRounded(15, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 88, alignment: .leading)
                            Text(person.label)
                                .font(.bodyRounded(15))
                                .foregroundStyle(AppTheme.inkMuted)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if notes.isEmpty {
                Text("このふりかえりで見えた日々の記録はありませんでした。")
                    .font(.bodyRounded(14))
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("日々の想い")
                        .font(.bodyRounded(13, weight: .semibold))
                        .foregroundStyle(AppTheme.terracotta)
                    ForEach(notes) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(authorName(item.authorId))
                                    .font(.bodyRounded(14, weight: .medium))
                                    .foregroundStyle(AppTheme.ink)
                                Text(item.type.display)
                                    .font(.bodyRounded(14, weight: .semibold))
                                    .foregroundStyle(tone(item.type))
                                Spacer()
                                Text(AppWeek.dayLabel(for: item.createdAt))
                                    .font(.bodyRounded(13))
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            if let note = item.note, !note.isEmpty {
                                Text(note)
                                    .font(.bodyRounded(15))
                                    .foregroundStyle(AppTheme.ink)
                                    .lineSpacing(3)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.creamDeep.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .padding(20)
        .appCard()
    }

    private func prepare() {
        if readOnly || session.hasCompletedOwnReview(reviewDate: reviewDate) {
            advanceAfterSelfReview()
            return
        }
        drafts = targets.map { agreement in
            if let existing = reflection(userId: session.currentUserID, agreementId: agreement.id) {
                return ReviewAnswer(
                    agreementId: agreement.id,
                    applicable: existing.applicable,
                    selfReflection: existing.selfReflection
                )
            }
            return ReviewAnswer(agreementId: agreement.id)
        }
        index = drafts.firstIndex(where: {
            $0.applicable == nil || ($0.applicable == true && $0.selfReflection == nil)
        }) ?? 0
        phase = .selfReview
    }

    private func considerAdvanceFromWaiting() {
        if phase == .waiting, session.bothCompletedReview(reviewDate: reviewDate) {
            session.revealReviewNotesIfNeeded(reviewDate: reviewDate)
            phase = .recap
        }
    }

    private func binding(for id: UUID) -> Binding<ReviewAnswer> {
        Binding(
            get: {
                drafts.first(where: { $0.agreementId == id }) ?? ReviewAnswer(agreementId: id)
            },
            set: { newValue in
                if let i = drafts.firstIndex(where: { $0.agreementId == id }) {
                    drafts[i] = newValue
                } else {
                    drafts.append(newValue)
                }
            }
        )
    }

    private func goNext() {
        persistCurrentIfPossible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if index + 1 < targets.count {
                index += 1
            } else {
                finishSelfReview()
            }
        }
    }

    private func persistCurrentIfPossible() {
        guard index < drafts.count else { return }
        let draft = drafts[index]
        guard let applicable = draft.applicable else { return }
        if applicable && draft.selfReflection == nil { return }
        try? session.saveReflections([
            ReflectionDraft(
                agreementId: draft.agreementId,
                applicable: applicable,
                selfReflection: applicable ? draft.selfReflection : nil
            )
        ], reviewDate: reviewDate)
    }

    private func finishSelfReview() {
        persistCurrentIfPossible()
        let payload = drafts.compactMap { draft -> ReflectionDraft? in
            guard let applicable = draft.applicable else { return nil }
            return ReflectionDraft(
                agreementId: draft.agreementId,
                applicable: applicable,
                selfReflection: applicable ? draft.selfReflection : nil
            )
        }
        try? session.saveReflections(payload, reviewDate: reviewDate)
        Task {
            await session.refreshFromCloud()
            session.revealReviewNotesIfNeeded(reviewDate: reviewDate)
            advanceAfterSelfReview()
        }
    }

    private func advanceAfterSelfReview() {
        if session.partner == nil || session.bothCompletedReview(reviewDate: reviewDate) {
            phase = .recap
        } else if session.hasCompletedOwnReview(reviewDate: reviewDate) {
            phase = .waiting
        } else {
            phase = .recap
        }
    }

    private func recapPeople(for agreement: Agreement) -> [(userId: UUID, name: String, label: String)] {
        session.householdMembers
            .sorted { lhs, rhs in
                if lhs.id == session.currentUserID { return true }
                if rhs.id == session.currentUserID { return false }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            .compactMap { member in
                guard agreement.applies(to: member.id) else { return nil }
                return (member.id, member.displayName, reflectionLabel(userId: member.id, agreementId: agreement.id))
            }
    }

    private func reflectionLabel(userId: UUID, agreementId: UUID) -> String {
        guard let item = reflection(userId: userId, agreementId: agreementId) else {
            return "まだ入力がありません"
        }
        if !item.applicable {
            return AppCopy.notThisWeek
        }
        return item.selfReflection?.label ?? "—"
    }

    private func reflection(userId: UUID?, agreementId: UUID) -> WeeklyReflection? {
        guard let userId else { return nil }
        return reflections.first {
            $0.userId == userId &&
            $0.agreementId == agreementId &&
            AppWeek.isSameDay($0.weekStartDate, reviewDate)
        }
    }

    private func reviewNotes(for agreementId: UUID) -> [DailyObservation] {
        let canSeePartner = session.partner == nil || session.bothCompletedReview(reviewDate: reviewDate)
        let isToday = AppWeek.isSameDay(reviewDate, .now)
        return observations
            .filter { item in
                guard item.agreementId == agreementId, !item.isDeleted else { return false }
                let visible = canSeePartner || item.isPublished || item.authorId == session.currentUserID
                guard visible else { return false }
                if let published = item.publishedAt {
                    return AppWeek.isSameDay(published, reviewDate)
                }
                return isToday
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func authorName(_ userId: UUID) -> String {
        session.householdMembers.first(where: { $0.id == userId })?.displayName ?? AppCopy.partner
    }

    private func tone(_ type: ObservationType) -> Color {
        switch type {
        case .positive: AppTheme.sage
        case .concern: AppTheme.ochre
        case .other: AppTheme.sky
        }
    }
}

struct ReviewHistoryView: View {
    @Environment(AppSession.self) private var session
    @Query private var reflections: [WeeklyReflection]
    @State private var presented: PresentedReview?

    var body: some View {
        let _ = (session.syncRevision, reflections.count)
        let days = session.pastReviewDates()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "これまでのふりかえり",
                    subtitle: "過去の入力と、そのとき見えた想いをいつでも開けます。"
                )

                if days.isEmpty {
                    EmptyNote(text: "まだふりかえりはありません。")
                } else {
                    VStack(spacing: 10) {
                        ForEach(days, id: \.self) { day in
                            Button {
                                presented = PresentedReview(date: day, readOnly: true)
                            } label: {
                                HStack {
                                    Text(AppWeek.dayLabel(for: day))
                                        .font(.bodyRounded(16, weight: .medium))
                                        .foregroundStyle(AppTheme.ink)
                                    Spacer()
                                    Text(historyStatus(for: day))
                                        .font(.bodyRounded(13))
                                        .foregroundStyle(AppTheme.inkMuted)
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
            .padding(20)
            .readableWidth()
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $presented) { item in
            WeeklyReviewFlowView(reviewDate: item.date, readOnly: item.readOnly)
        }
    }

    private func historyStatus(for day: Date) -> String {
        if session.partner == nil || session.bothCompletedReview(reviewDate: day) {
            return "見る"
        }
        if session.hasCompletedOwnReview(reviewDate: day) {
            return "自分のみ"
        }
        return "見る"
    }
}

struct ReviewAnswer {
    var agreementId: UUID
    var applicable: Bool?
    var selfReflection: SelfReflection?
}

struct PresentedReview: Identifiable {
    let date: Date
    var readOnly: Bool
    var id: TimeInterval { date.timeIntervalSince1970 }
}
