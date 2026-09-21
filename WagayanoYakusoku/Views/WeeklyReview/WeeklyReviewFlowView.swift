import SwiftUI
import SwiftData

struct WeeklyReviewFlowView: View {
    let weekStart: Date
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
        case partner
        case done
    }

    private var targets: [Agreement] {
        guard let userId = session.currentUserID,
              let householdId = session.currentHouseholdID else { return [] }
        return agreements
            .filter {
                $0.householdId == householdId &&
                $0.deletedAt == nil &&
                $0.applies(to: userId)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var current: Agreement? {
        guard index < targets.count else { return nil }
        return targets[index]
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .selfReview:
                    selfReviewContent
                case .waiting:
                    waitingContent
                case .partner:
                    partnerContent
                case .done:
                    doneContent
                }
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
            .onAppear { prepare() }
            .onChange(of: reflections.count) { _, _ in
                if phase == .waiting, session.bothCompletedReview(weekStart: weekStart) {
                    phase = .partner
                }
            }
        }
    }

    @ViewBuilder
    private var selfReviewContent: some View {
        if targets.isEmpty {
            VStack(spacing: 20) {
                ScreenHeader(
                    title: "今週のふりかえり",
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
                        .font(.titleSerif(26))
                        .foregroundStyle(AppTheme.ink)

                    if answer.wrappedValue.applicable == nil || answer.wrappedValue.applicable == false || answer.wrappedValue.selfReflection == nil {
                        Text(AppCopy.applicableAsk)
                            .font(.bodyRounded(17))
                            .foregroundStyle(AppTheme.inkMuted)
                        HStack(spacing: 12) {
                            Button(AppCopy.had) {
                                answer.wrappedValue.applicable = true
                            }
                            .buttonStyle(applicableStyle(selected: answer.wrappedValue.applicable == true))
                            Button(AppCopy.hadNot) {
                                answer.wrappedValue.applicable = false
                                answer.wrappedValue.selfReflection = nil
                                goNext()
                            }
                            .buttonStyle(applicableStyle(selected: answer.wrappedValue.applicable == false))
                        }
                    }

                    if answer.wrappedValue.applicable == true {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(AppCopy.selfAsk)
                                .font(.titleSerif(24))
                                .foregroundStyle(AppTheme.ink)
                            ForEach(SelfReflection.allCases) { option in
                                ChoiceCard(selected: answer.wrappedValue.selfReflection == option) {
                                    answer.wrappedValue.selfReflection = option
                                    goNext()
                                } content: {
                                    Text(option.label)
                                        .font(.bodyRounded(16))
                                        .foregroundStyle(AppTheme.ink)
                                }
                            }
                        }
                    }

                    if index > 0 {
                        Button("ひとつ前へ") { index -= 1 }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(24)
                .readableWidth()
            }
        }
    }

    private var waitingContent: some View {
        VStack(spacing: 24) {
            Spacer()
            ScreenHeader(
                title: "相手の振り返りを待ちましょう",
                subtitle: "自分のふりかえりは残りました。相手が終わると、今週感じたことを一緒に見られます。"
            )
            Spacer()
            Button(AppCopy.finish) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
        .readableWidth()
    }

    private var partnerContent: some View {
        let grouped = partnerGrouped()
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(title: AppCopy.partnerFelt)

                if grouped.isEmpty {
                    EmptyNote(text: "今週、相手はまだ何も残していませんでした。")
                } else {
                    ForEach(grouped, id: \.agreement.id) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(group.agreement.title)
                                .font(.titleSerif(22))
                                .foregroundStyle(AppTheme.ink)
                            ForEach(group.items) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.type.display)
                                        .font(.bodyRounded(16, weight: .semibold))
                                        .foregroundStyle(tone(item.type))
                                    Text(AppWeek.weekdayLabel(for: item.createdAt))
                                        .font(.bodyRounded(13))
                                        .foregroundStyle(AppTheme.inkMuted)
                                    if let note = item.note, !note.isEmpty {
                                        Text(note)
                                            .font(.bodyRounded(15))
                                            .foregroundStyle(AppTheme.ink)
                                            .lineSpacing(3)
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.creamDeep.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                        .padding(20)
                        .appCard()
                    }
                }

                Button("次へ") { phase = .done }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
            .readableWidth()
        }
    }

    private var doneContent: some View {
        VStack(spacing: 24) {
            Spacer()
            ScreenHeader(
                title: AppCopy.reviewDoneTitle,
                subtitle: AppCopy.reviewDoneBody
            )
            Spacer()
            Button(AppCopy.finish) {
                session.markPartnerRevealSeen(weekStart: weekStart)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
        .readableWidth()
    }

    private func prepare() {
        if session.hasCompletedOwnReview(weekStart: weekStart) {
            advanceAfterSelfReview()
            return
        }
        drafts = targets.map { agreement in
            if let existing = reflections.first(where: {
                $0.agreementId == agreement.id &&
                $0.userId == session.currentUserID &&
                AppWeek.calendar.isDate($0.weekStartDate, inSameDayAs: weekStart)
            }) {
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
        ], weekStart: weekStart)
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
        try? session.saveReflections(payload, weekStart: weekStart)
        advanceAfterSelfReview()
    }

    private func advanceAfterSelfReview() {
        if session.partner == nil {
            session.markPartnerRevealSeen(weekStart: weekStart)
            phase = .done
        } else if session.bothCompletedReview(weekStart: weekStart) {
            phase = .partner
        } else {
            phase = .waiting
        }
    }

    private func partnerGrouped() -> [(agreement: Agreement, items: [DailyObservation])] {
        guard let partnerId = session.partner?.id else { return [] }
        let items = observations
            .filter {
                $0.authorId == partnerId &&
                !$0.isDeleted &&
                $0.isPublished &&
                AppWeek.contains($0.createdAt, weekStart: weekStart)
            }
            .sorted { $0.createdAt < $1.createdAt }
        let ids = Array(Set(items.map(\.agreementId)))
        return ids.compactMap { id in
            guard let agreement = agreements.first(where: { $0.id == id }) else { return nil }
            let list = items.filter { $0.agreementId == id }
            return (agreement, list)
        }
        .sorted { $0.agreement.createdAt < $1.agreement.createdAt }
    }

    private func applicableStyle(selected: Bool) -> some ButtonStyle {
        ReviewChoiceButtonStyle(selected: selected)
    }

    private func tone(_ type: ObservationType) -> Color {
        switch type {
        case .positive: AppTheme.sage
        case .concern: AppTheme.ochre
        case .other: AppTheme.sky
        }
    }
}

struct ReviewAnswer {
    var agreementId: UUID
    var applicable: Bool?
    var selfReflection: SelfReflection?
}

struct ReviewChoiceButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyRounded(16, weight: .semibold))
            .foregroundStyle(selected ? .white : AppTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selected ? AppTheme.terracotta : AppTheme.paper)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous)
                    .stroke(selected ? AppTheme.terracotta : AppTheme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}
