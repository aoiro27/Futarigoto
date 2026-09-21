import SwiftUI
import SwiftData

struct ObservationListView: View {
    @Environment(AppSession.self) private var session
    @Query private var observations: [DailyObservation]
    @Query private var agreements: [Agreement]
    @State private var showsAdd = false
    @State private var editing: DailyObservation?

    private var thisWeek: [DailyObservation] {
        guard let userId = session.currentUserID else { return [] }
        let start = AppWeek.start(of: .now)
        return observations
            .filter {
                $0.authorId == userId &&
                !$0.isDeleted &&
                AppWeek.contains($0.createdAt, weekStart: start)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(
                        title: AppCopy.thisWeek,
                        subtitle: "自分が残したことだけが見えます。パートナーの記録は、ふりかえりで開きます。"
                    )

                    Button(AppCopy.addToday) {
                        showsAdd = true
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if thisWeek.isEmpty {
                        EmptyNote(text: "まだ何も残していません。何か感じたときだけで大丈夫です。")
                    } else {
                        let grouped = Dictionary(grouping: thisWeek) {
                            AppWeek.calendar.startOfDay(for: $0.createdAt)
                        }
                        ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(AppWeek.weekdayLabel(for: day))
                                    .font(.titleRounded(20))
                                    .foregroundStyle(AppTheme.ink)
                                ForEach(grouped[day] ?? []) { item in
                                    ObservationCard(
                                        observation: item,
                                        agreementTitle: agreementTitle(for: item.agreementId)
                                    ) {
                                        if !item.isPublished {
                                            editing = item
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .readableWidth()
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsAdd) {
                ObservationFlowView()
            }
            .sheet(item: $editing) { item in
                ObservationFlowView(editing: item)
            }
        }
    }

    private func agreementTitle(for id: UUID) -> String {
        agreements.first(where: { $0.id == id })?.title ?? "約束"
    }
}

struct ObservationCard: View {
    @Environment(AppSession.self) private var session
    let observation: DailyObservation
    let agreementTitle: String
    let onEdit: () -> Void
    @State private var showsDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(observation.type.display)
                .font(.bodyRounded(16, weight: .semibold))
                .foregroundStyle(color(for: observation.type))
            Text(agreementTitle)
                .font(.bodyRounded(15, weight: .medium))
                .foregroundStyle(AppTheme.ink)
            if let note = observation.note, !note.isEmpty {
                Text(note)
                    .font(.bodyRounded(15))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineSpacing(3)
            }
            if !observation.isPublished {
                HStack(spacing: 16) {
                    Button("編集") { onEdit() }
                    Button("削除") { showsDelete = true }
                    Spacer()
                    Text("まだ相手には見えません")
                        .font(.bodyRounded(12))
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .font(.bodyRounded(14, weight: .medium))
                .foregroundStyle(AppTheme.terracotta)
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .alert("この記録を消しますか？", isPresented: $showsDelete) {
            Button(AppCopy.deleteConfirm, role: .destructive) {
                try? session.deleteObservation(observation)
            }
            Button(AppCopy.cancel, role: .cancel) {}
        }
    }

    private func color(for type: ObservationType) -> Color {
        switch type {
        case .positive: AppTheme.sage
        case .concern: AppTheme.ochre
        case .other: AppTheme.sky
        }
    }
}

struct ObservationFlowView: View {
    var editing: DailyObservation? = nil
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Query private var agreements: [Agreement]

    @State private var step = 1
    @State private var selectedAgreementID: UUID?
    @State private var selectedType: ObservationType?
    @State private var note = ""

    private var activeAgreements: [Agreement] {
        guard let householdId = session.currentHouseholdID else { return [] }
        return agreements
            .filter { $0.householdId == householdId && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress
                    .padding(.top, 8)
                Group {
                    switch step {
                    case 1: stepOne
                    case 2: stepTwo
                    default: stepThree
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: step)
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
            .onAppear { populateIfEditing() }
        }
        .presentationDetents([.large])
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? AppTheme.terracotta : AppTheme.line)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
    }

    private var stepOne: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: AppCopy.whichAgreement)
                if activeAgreements.isEmpty {
                    EmptyNote(text: "先に、わが家の約束を残してください。")
                } else {
                    ForEach(activeAgreements) { agreement in
                        ChoiceCard(selected: selectedAgreementID == agreement.id) {
                            selectedAgreementID = agreement.id
                            step = 2
                        } content: {
                            Text(agreement.title)
                                .font(.bodyRounded(16))
                                .foregroundStyle(AppTheme.ink)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .padding(24)
            .readableWidth()
        }
    }

    private var stepTwo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: AppCopy.whatHappened)
                ForEach(ObservationType.allCases) { type in
                    ChoiceCard(selected: selectedType == type) {
                        selectedType = type
                        step = 3
                    } content: {
                        Text(type.display)
                            .font(.bodyRounded(18, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                Button("戻る") { step = 1 }
                    .buttonStyle(QuietButtonStyle())
                    .padding(.top, 8)
            }
            .padding(24)
            .readableWidth()
        }
    }

    private var stepThree: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: AppCopy.aWordTitle, subtitle: AppCopy.aWordBody)
                TextField("リビングに使用済みおむつが残っていた", text: $note, axis: .vertical)
                    .font(.bodyRounded(16))
                    .lineLimit(4...8)
                    .padding(18)
                    .appCard()
                Text("\(note.count)/300")
                    .font(.bodyRounded(12))
                    .foregroundStyle(AppTheme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button(AppCopy.keepRecord) {
                    save()
                }
                .buttonStyle(PrimaryButtonStyle(enabled: selectedAgreementID != nil && selectedType != nil))
                .disabled(selectedAgreementID == nil || selectedType == nil)

                Button("戻る") { step = 2 }
                    .buttonStyle(QuietButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .readableWidth()
        }
        .onChange(of: note) { _, newValue in
            if newValue.count > 300 {
                note = String(newValue.prefix(300))
            }
        }
    }

    private func populateIfEditing() {
        guard let editing else { return }
        selectedAgreementID = editing.agreementId
        selectedType = editing.type
        note = editing.note ?? ""
        step = 3
    }

    private func save() {
        guard let agreementId = selectedAgreementID, let type = selectedType else { return }
        do {
            if let editing {
                try session.updateObservation(editing, type: type, note: note)
            } else {
                try session.addObservation(agreementId: agreementId, type: type, note: note)
            }
            dismiss()
        } catch {}
    }
}
