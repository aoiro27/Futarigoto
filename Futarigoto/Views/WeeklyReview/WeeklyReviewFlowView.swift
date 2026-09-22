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
    @State private var phase: Phase = .loading
    @State private var isSaving = false
    @State private var saveError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Phase {
        case loading
        case selfReview
        case waiting
        case recap
    }

    private var questions: [ReviewQuestion] {
        guard let userId = session.currentUserID else { return [] }
        let partner = session.partner
        var items: [ReviewQuestion] = []
        for agreement in householdAgreements {
            if agreement.applies(to: userId) {
                items.append(
                    ReviewQuestion(
                        agreementId: agreement.id,
                        title: agreement.title,
                        focus: .selfEval,
                        eyebrow: "自分のこと",
                        ask: AppCopy.applicableAsk
                    )
                )
            }
            if let partner, agreement.applies(to: partner.id) {
                items.append(
                    ReviewQuestion(
                        agreementId: agreement.id,
                        title: agreement.title,
                        focus: .partnerEval,
                        eyebrow: "\(partner.displayName)のこと",
                        ask: "\(partner.displayName)\(AppCopy.partnerAskSuffix)"
                    )
                )
            }
        }
        return items
    }

    private var householdAgreements: [Agreement] {
        guard let householdId = session.currentHouseholdID else { return [] }
        return agreements
            .filter { $0.householdId == householdId && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var pages: [ReviewPage] { ReviewPage.group(questions) }

    private var current: ReviewPage? {
        guard pages.indices.contains(index) else { return nil }
        return pages[index]
    }

    private func isComplete(_ page: ReviewPage) -> Bool {
        page.isComplete(in: drafts)
    }

    var body: some View {
        let _ = session.syncRevision
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    loadingContent
                case .selfReview:
                    selfReviewContent
                case .waiting:
                    waitingContent
                case .recap:
                    recapContent
                        .task {
                            await session.syncSharedReviewNotes(reviewDate: reviewDate)
                        }
                }
            }
            .screenBackground()
            .alert("保存できませんでした", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "もう一度お試しください。")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                        .disabled(isSaving)
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

    private var loadingContent: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("読み込み中")
    }

    @ViewBuilder
    private var selfReviewContent: some View {
        if questions.isEmpty {
            VStack(spacing: 20) {
                ScreenHeader(title: "ふりかえり")
                EmptyNote(text: "約束がありません")
                Button("とじる") { finishSelfReview() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
        } else if let current {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        reviewProgress
                            .id("reviewTop")

                        VStack(alignment: .leading, spacing: 10) {
                            Label("この約束、今日はどうだった？", systemImage: "heart.fill")
                                .font(.bodyRounded(13, weight: .medium))
                                .foregroundStyle(AppTheme.terracotta)
                            Text(current.title)
                                .font(.titleRounded(23))
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)

                        ForEach(current.questions) { question in
                            ReflectionMoodPicker(
                                name: question.focus == .selfEval ? "自分" : session.partner?.displayName ?? "相手",
                                isSelf: question.focus == .selfEval,
                                answer: binding(for: question)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .readableWidth()
                }
                .onChange(of: index) { _, _ in
                    proxy.scrollTo("reviewTop", anchor: .top)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    reviewNavigation(current)
                }
            }
        } else {
            ProgressView()
                .onAppear { prepare() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var reviewProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ふたりのふりかえり")
                    .font(.bodyRounded(14, weight: .medium))
                Spacer()
                Text("約束 \(index + 1) / \(pages.count)")
                    .font(.bodyRounded(12, weight: .medium))
            }
            .foregroundStyle(AppTheme.inkMuted)
            ProgressView(value: Double(index + 1), total: Double(pages.count))
                .tint(AppTheme.terracotta)
                .accessibilityLabel("約束 \(index + 1) / \(pages.count)")
        }
    }

    private func reviewNavigation(_ page: ReviewPage) -> some View {
        HStack(spacing: 16) {
            if index > 0 {
                Button {
                    index -= 1
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                        .frame(minHeight: 48)
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isSaving)
            }
            Button {
                goNext()
            } label: {
                HStack(spacing: 8) {
                    if isSaving { ProgressView().tint(.white) }
                    Text(index + 1 == pages.count ? "ふりかえりを残す" : "次の約束へ")
                    Image(systemName: index + 1 == pages.count ? "heart.fill" : "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: isComplete(page) && !isSaving))
            .disabled(!isComplete(page) || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .readableWidth()
        .background(AppTheme.cream)
    }

    private var waitingContent: some View {
        ReviewWaitingView(partnerName: session.partner?.displayName ?? "パートナー") {
            dismiss()
        }
    }

    private var recapContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ReviewRecapHeader(
                    date: AppWeek.dayLabel(for: reviewDate),
                    isTogether: session.partner != nil && session.bothCompletedReview(reviewDate: reviewDate)
                )

                if householdAgreements.isEmpty {
                    EmptyNote(text: "約束がありません")
                } else {
                    ForEach(Array(householdAgreements.enumerated()), id: \.element.id) { index, agreement in
                        recapCard(for: agreement, index: index)
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

    private func recapCard(for agreement: Agreement, index: Int) -> some View {
        let people = recapPeople(for: agreement)
        let notes = reviewNotes(for: agreement.id)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("約束 \(String(format: "%02d", index + 1))", systemImage: "heart.fill")
                    .font(.bodyRounded(12, weight: .medium))
                    .foregroundStyle(AppTheme.terracotta)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.terracottaSoft.opacity(0.6), in: Capsule())
                Text(agreement.title)
                    .font(.titleRounded(21))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !people.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(people, id: \.userId) { person in
                        RecapPersonCard(person: person)
                    }
                }
            }

            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("この日に残した、ひとこと", systemImage: "book.closed.fill")
                        .font(.bodyRounded(13, weight: .medium))
                        .foregroundStyle(AppTheme.plum)
                    ForEach(notes) { item in
                        reviewNoteRow(item, showsAuthor: true)
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
        drafts = questions.map { question in
            let existing = reflection(userId: session.currentUserID, agreementId: question.agreementId)
            switch question.focus {
            case .selfEval:
                return ReviewAnswer(
                    agreementId: question.agreementId,
                    focus: .selfEval,
                    applicable: existing?.hasSelfAnswer == true ? existing?.applicable : nil,
                    reflection: existing?.selfReflection
                )
            case .partnerEval:
                return ReviewAnswer(
                    agreementId: question.agreementId,
                    focus: .partnerEval,
                    applicable: existing?.otherApplicable,
                    reflection: existing?.otherReflection
                )
            }
        }
        index = pages.firstIndex(where: { !isComplete($0) }) ?? 0
        phase = .selfReview
    }

    private func considerAdvanceFromWaiting() {
        guard phase == .waiting, session.bothCompletedReview(reviewDate: reviewDate) else { return }
        phase = .loading
        Task {
            await session.syncSharedReviewNotes(reviewDate: reviewDate)
            phase = .recap
        }
    }

    private func binding(for question: ReviewQuestion) -> Binding<ReviewAnswer> {
        Binding(
            get: {
                drafts.first(where: { $0.id == question.id })
                    ?? ReviewAnswer(agreementId: question.agreementId, focus: question.focus)
            },
            set: { newValue in
                if let i = drafts.firstIndex(where: { $0.id == question.id }) {
                    drafts[i] = newValue
                } else {
                    drafts.append(newValue)
                }
            }
        )
    }

    private func goNext() {
        guard !isSaving, let current, isComplete(current) else { return }
        if index + 1 == pages.count {
            finishSelfReview()
            return
        }
        do {
            let ids = Set(current.questions.map(\.id))
            let payload = drafts.filter { ids.contains($0.id) }.compactMap(reflectionDraft(from:))
            try session.saveReflections(payload, reviewDate: reviewDate)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                index += 1
            }
        } catch {
            saveError = "入力はこの画面に残っています。もう一度お試しください。"
        }
    }

    private func finishSelfReview() {
        guard !isSaving, pages.allSatisfy({ isComplete($0) }) else { return }
        isSaving = true
        do {
            let payload = drafts.compactMap(reflectionDraft(from:))
            try session.saveReflections(payload, reviewDate: reviewDate)
        } catch {
            isSaving = false
            saveError = "入力はこの画面に残っています。もう一度お試しください。"
            return
        }
        Task {
            await session.refreshFromCloud()
            await session.syncSharedReviewNotes(reviewDate: reviewDate)
            isSaving = false
            advanceAfterSelfReview()
        }
    }

    private func reflectionDraft(from answer: ReviewAnswer) -> ReflectionDraft? {
        guard answer.isComplete, let applicable = answer.applicable else { return nil }
        switch answer.focus {
        case .selfEval:
            return ReflectionDraft(
                agreementId: answer.agreementId,
                applicable: applicable,
                selfReflection: applicable ? answer.reflection : nil
            )
        case .partnerEval:
            return ReflectionDraft(
                agreementId: answer.agreementId,
                otherApplicable: applicable,
                otherReflection: applicable ? answer.reflection : nil
            )
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

    private func reviewNoteRow(_ item: DailyObservation, showsAuthor: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if showsAuthor {
                    Text(authorName(item.authorId))
                        .font(.bodyRounded(14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                }
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
            if let data = item.visibleImageData {
                ObservationPhotoView(data: data, height: 140)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.creamDeep.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recapPeople(for agreement: Agreement) -> [RecapPerson] {
        let members = session.householdMembers.sorted { lhs, rhs in
            let byName = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return members.compactMap { member in
            guard agreement.applies(to: member.id) else { return nil }
            let selfValue = selfReflectionValue(userId: member.id, agreementId: agreement.id)
            let other = members.first(where: { $0.id != member.id })
            let otherValue = other.flatMap {
                otherReflectionValue(reviewerId: $0.id, agreementId: agreement.id)
            }
            return RecapPerson(
                userId: member.id,
                name: member.displayName,
                selfLabel: selfReflectionLabel(userId: member.id, agreementId: agreement.id),
                selfValue: selfValue,
                otherValue: otherValue,
                otherName: other?.displayName,
                otherLabel: other.map { otherViewLabel(reviewerId: $0.id, agreementId: agreement.id) },
                gap: ReflectionGap(selfValue: selfValue, otherValue: otherValue)
            )
        }
    }

    private func selfReflectionLabel(userId: UUID, agreementId: UUID) -> String {
        guard let item = reflection(userId: userId, agreementId: agreementId) else {
            return "まだ入力がありません"
        }
        if !item.applicable {
            return AppCopy.notThisWeek
        }
        return item.selfReflection?.label ?? "—"
    }

    private func otherViewLabel(reviewerId: UUID, agreementId: UUID) -> String {
        guard let item = reflection(userId: reviewerId, agreementId: agreementId),
              let otherApplicable = item.otherApplicable else {
            return "まだ入力がありません"
        }
        if !otherApplicable {
            return AppCopy.notThisWeek
        }
        return item.otherReflection?.label ?? "—"
    }

    private func selfReflectionValue(userId: UUID, agreementId: UUID) -> SelfReflection? {
        guard let item = reflection(userId: userId, agreementId: agreementId), item.applicable else {
            return nil
        }
        return item.selfReflection
    }

    private func otherReflectionValue(reviewerId: UUID, agreementId: UUID) -> SelfReflection? {
        guard let item = reflection(userId: reviewerId, agreementId: agreementId),
              item.otherApplicable == true else {
            return nil
        }
        return item.otherReflection
    }

    private func reflection(userId: UUID?, agreementId: UUID) -> WeeklyReflection? {
        guard let userId else { return nil }
        return reflections.first {
            $0.userId == userId &&
            $0.agreementId == agreementId &&
            AppWeek.isSameDay($0.weekStartDate, reviewDate)
        }
    }

    private func belongsToReview(_ item: DailyObservation) -> Bool {
        if AppWeek.isSameDay(item.createdAt, reviewDate) {
            return true
        }
        if let published = item.publishedAt {
            return AppWeek.isSameDay(published, reviewDate)
        }
        return false
    }

    private func reviewNotes(for agreementId: UUID) -> [DailyObservation] {
        let revealShared = session.partner == nil || session.bothCompletedReview(reviewDate: reviewDate)
        return observations
            .filter { item in
                guard item.agreementId == agreementId, !item.isDeleted else { return false }
                guard belongsToReview(item) else { return false }
                return revealShared || item.authorId == session.currentUserID
            }
            .sorted(by: reviewNoteOrder)
    }

    private func reviewNoteOrder(_ lhs: DailyObservation, _ rhs: DailyObservation) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        if lhs.authorId != rhs.authorId {
            return lhs.authorId.uuidString < rhs.authorId.uuidString
        }
        return lhs.id.uuidString < rhs.id.uuidString
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

enum ReviewFocus: Hashable {
    case selfEval
    case partnerEval
}

struct ReviewQuestion: Identifiable, Hashable {
    var agreementId: UUID
    var title: String
    var focus: ReviewFocus
    var eyebrow: String
    var ask: String

    var id: String { "\(agreementId.uuidString)-\(focus)" }
}

struct ReviewPage: Identifiable {
    let agreementId: UUID
    let title: String
    let questions: [ReviewQuestion]

    var id: UUID { agreementId }

    static func group(_ questions: [ReviewQuestion]) -> [ReviewPage] {
        var order: [UUID] = []
        var grouped: [UUID: [ReviewQuestion]] = [:]
        for question in questions {
            if grouped[question.agreementId] == nil { order.append(question.agreementId) }
            grouped[question.agreementId, default: []].append(question)
        }
        return order.compactMap { id in
            guard let items = grouped[id], let first = items.first else { return nil }
            return ReviewPage(agreementId: id, title: first.title, questions: items)
        }
    }

    func isComplete(in answers: [ReviewAnswer]) -> Bool {
        questions.allSatisfy { question in
            answers.first(where: { $0.id == question.id })?.isComplete == true
        }
    }
}

struct ReviewAnswer: Identifiable {
    var agreementId: UUID
    var focus: ReviewFocus
    var applicable: Bool?
    var reflection: SelfReflection?

    var id: String { "\(agreementId.uuidString)-\(focus)" }

    var isComplete: Bool {
        guard let applicable else { return false }
        return applicable == false || reflection != nil
    }
}

private enum ReflectionGap {
    case better
    case worse

    init?(selfValue: SelfReflection?, otherValue: SelfReflection?) {
        guard let selfValue, let otherValue else { return nil }
        if otherValue.rank > selfValue.rank {
            self = .better
        } else if otherValue.rank < selfValue.rank {
            self = .worse
        } else {
            return nil
        }
    }

    var color: Color {
        switch self {
        case .better: AppTheme.sage
        case .worse: AppTheme.ochre
        }
    }

    var background: Color {
        switch self {
        case .better: AppTheme.sageSoft
        case .worse: AppTheme.ochreSoft
        }
    }
}

private struct RecapPerson {
    var userId: UUID
    var name: String
    var selfLabel: String
    var selfValue: SelfReflection?
    var otherValue: SelfReflection?
    var otherName: String?
    var otherLabel: String?
    var gap: ReflectionGap?
}

struct PresentedReview: Identifiable {
    let date: Date
    var readOnly: Bool
    var id: TimeInterval { date.timeIntervalSince1970 }
}

private struct ReflectionMoodPicker: View {
    let name: String
    let isSelf: Bool
    @Binding var answer: ReviewAnswer
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { isSelf ? AppTheme.terracotta : AppTheme.plum }
    private var soft: Color { isSelf ? AppTheme.terracottaSoft : AppTheme.lavender }
    private var selectionLabel: String {
        if answer.applicable == false { return "今回は、その機会がなかった" }
        return answer.reflection?.label ?? "近い表情を、ひとつ選んでね"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.bodyRounded(17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(isSelf ? "のこと" : "を見ていて")
                    .font(.bodyRounded(12))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer(minLength: 0)
                if answer.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                        .accessibilityLabel("選択済み")
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 10) {
                ForEach(SelfReflection.allCases) { option in
                    moodButton(option)
                }
            }

            Text(selectionLabel)
                .font(.bodyRounded(13, weight: .medium))
                .foregroundStyle(answer.isComplete ? accent : AppTheme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    answer.applicable = false
                    answer.reflection = nil
                }
            } label: {
                Label("今回はなかった", systemImage: answer.applicable == false ? "checkmark.circle.fill" : "minus.circle")
                    .font(.bodyRounded(12, weight: .medium))
                    .foregroundStyle(answer.applicable == false ? accent : AppTheme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(answer.applicable == false ? soft : AppTheme.cream, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name)：今回はなかった")
            .accessibilityAddTraits(answer.applicable == false ? .isSelected : [])
        }
        .padding(16)
        .appCard()
        .overlay(alignment: .top) {
            Capsule().fill(soft).frame(width: 44, height: 4)
        }
        .accessibilityElement(children: .contain)
    }

    private func moodButton(_ option: SelfReflection) -> some View {
        let selected = answer.applicable == true && answer.reflection == option
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.65)) {
                answer.applicable = true
                answer.reflection = option
            }
        } label: {
            VStack(spacing: 6) {
                ReflectionFace(reflection: option)
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(selected ? -7 : 0))
                    .scaleEffect(selected ? 1.06 : 1)
                Text(option.moodCaption)
                    .font(.bodyRounded(11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selected ? soft : .clear, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(selected ? accent : .clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)：\(option.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension SelfReflection {
    var moodCaption: String {
        switch self {
        case .veryGood: "まもれた"
        case .mostlyGood: "だいたい"
        case .sometimesMissed: "ときどき"
        case .oftenMissed: "むずかしい"
        }
    }

    var moodColor: Color {
        switch self {
        case .veryGood: AppTheme.ochreSoft
        case .mostlyGood: AppTheme.sageSoft
        case .sometimesMissed: AppTheme.skySoft
        case .oftenMissed: AppTheme.lavender
        }
    }
}

/// Gentle expressions, without scores or a punitive red "bad" state.
private struct ReflectionFace: View {
    let reflection: SelfReflection

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 48, y: size.height / 48)
            context.fill(Path(roundedRect: CGRect(x: 2, y: 2, width: 44, height: 44), cornerRadius: 18), with: .color(reflection.moodColor))
            func stroke(_ path: Path) {
                context.stroke(path, with: .color(AppTheme.ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            for x: CGFloat in [16, 32] {
                if reflection == .veryGood {
                    var eye = Path()
                    eye.move(to: CGPoint(x: x - 3, y: 21))
                    eye.addQuadCurve(to: CGPoint(x: x + 3, y: 21), control: CGPoint(x: x, y: 15))
                    stroke(eye)
                } else {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: 18, width: 3, height: 4)), with: .color(AppTheme.ink))
                }
            }
            for x: CGFloat in [9, 33] {
                context.fill(Path(ellipseIn: CGRect(x: x, y: 26, width: 7, height: 4)), with: .color(AppTheme.peach.opacity(0.65)))
            }
            var mouth = Path()
            switch reflection {
            case .veryGood:
                mouth.move(to: CGPoint(x: 18, y: 28))
                mouth.addQuadCurve(to: CGPoint(x: 30, y: 28), control: CGPoint(x: 24, y: 41))
                mouth.closeSubpath()
                context.fill(mouth, with: .color(AppTheme.ink))
            case .mostlyGood:
                mouth.move(to: CGPoint(x: 19, y: 29))
                mouth.addQuadCurve(to: CGPoint(x: 29, y: 29), control: CGPoint(x: 24, y: 35))
                stroke(mouth)
            case .sometimesMissed:
                mouth.move(to: CGPoint(x: 20, y: 31))
                mouth.addLine(to: CGPoint(x: 28, y: 30))
                stroke(mouth)
            case .oftenMissed:
                mouth.move(to: CGPoint(x: 20, y: 32))
                mouth.addQuadCurve(to: CGPoint(x: 28, y: 32), control: CGPoint(x: 24, y: 28))
                stroke(mouth)
            }
        }
        .accessibilityHidden(true)
    }
}


private struct ReviewWaitingView: View {
    let partnerName: String
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("ひと足先に、おつかれさま")
                        .font(.bodyRounded(14, weight: .medium))
                        .foregroundStyle(AppTheme.plum)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(AppTheme.lavender, in: Capsule())

                    TogetherIllustration(scene: .promises)
                        .frame(height: 180)
                        .background {
                            Circle()
                                .fill(AppTheme.lavender.opacity(0.45))
                                .frame(width: 170, height: 170)
                        }

                    Text("あなたのふりかえりを\n残しました")
                        .font(.titleRounded(26))
                        .foregroundStyle(AppTheme.ink)
                        .lineSpacing(6)

                    Text("ふたりの答えがそろったら、\nお互いの気持ちを、ゆっくり見てみよう。")
                        .font(.bodyRounded(15))
                        .foregroundStyle(AppTheme.inkMuted)
                        .lineSpacing(6)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    statusRow(name: "自分", status: "入力できました", symbol: "checkmark", color: AppTheme.terracotta, background: AppTheme.terracottaSoft)
                    Rectangle()
                        .fill(AppTheme.line.opacity(0.4))
                        .frame(height: 1)
                        .padding(.vertical, 16)
                    statusRow(name: partnerName, status: "入力を待っています", symbol: "ellipsis", color: AppTheme.plum, background: AppTheme.lavender)
                }
                .padding(20)
                .appCard()

                Label {
                    Text("この画面を閉じても大丈夫。\n「ふりかえり」から、また見にこられます。")
                        .lineSpacing(5)
                } icon: {
                    Image(systemName: "heart")
                        .foregroundStyle(AppTheme.terracotta)
                }
                .font(.bodyRounded(13))
                .foregroundStyle(AppTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("またあとで見る", action: onClose)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .readableWidth()
                .background(AppTheme.cream)
        }
    }

    private func statusRow(name: String, status: String, symbol: String, color: Color, background: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(background, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.bodyRounded(15, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                Text(status)
                    .font(.bodyRounded(13))
                    .foregroundStyle(color)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}


private struct ReviewRecapHeader: View {
    let date: String
    let isTogether: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date)
                .font(.bodyRounded(13, weight: .medium))
                .foregroundStyle(AppTheme.plum)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isTogether ? "ふたりの気持ちが\nそろいました" : "気持ちを残した\nふりかえりノート")
                        .font(.titleRounded(25))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(isTogether ? "同じところも、ちがうところも。" : "その日の気持ちを、ゆっくり。")
                        .font(.bodyRounded(13))
                        .foregroundStyle(AppTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TogetherIllustration(scene: .journal)
                    .frame(width: 96, height: 82)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.lavender.opacity(0.65), in: RoundedRectangle(cornerRadius: 28))
    }
}

private struct RecapPersonCard: View {
    let person: RecapPerson
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(person.name)のこと")
                .font(.bodyRounded(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) { answers }
            } else {
                HStack(alignment: .top, spacing: 10) { answers }
            }

            if person.selfValue != nil && person.otherValue != nil {
                Label {
                    Text(person.gap == nil ? "同じふりかえりでした" : "見え方に、ちょっと違いがありました")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: person.gap == nil ? "heart" : "bubble.left.and.bubble.right")
                }
                .font(.bodyRounded(12))
                .foregroundStyle(AppTheme.plum)
                .padding(.horizontal, 2)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var answers: some View {
        RecapMoodTile(author: "本人の気持ち", value: person.selfValue, label: person.selfLabel, color: AppTheme.terracottaSoft, accent: AppTheme.terracotta)
        if let name = person.otherName, let label = person.otherLabel {
            RecapMoodTile(author: "\(name)から見て", value: person.otherValue, label: label, color: AppTheme.lavender, accent: AppTheme.plum)
        }
    }
}

private struct RecapMoodTile: View {
    let author: String
    let value: SelfReflection?
    let label: String
    let color: Color
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            Text(author)
                .font(.bodyRounded(12, weight: .medium))
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if let value {
                    ReflectionFace(reflection: value)
                } else {
                    Image(systemName: label == AppCopy.notThisWeek ? "moon.zzz.fill" : "ellipsis.bubble.fill")
                        .font(.system(size: 28, weight: .regular, design: .rounded))
                        .foregroundStyle(accent.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 22))
                }
            }
            .frame(width: 60, height: 60)
            .accessibilityHidden(true)
            Text(label)
                .font(.bodyRounded(13, weight: .medium))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .background(color.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}
