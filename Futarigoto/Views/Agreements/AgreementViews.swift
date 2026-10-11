import SwiftUI
import SwiftData

struct AgreementListView: View {
    @Environment(AppSession.self) private var session
    @Query private var agreements: [Agreement]
    @Query private var steps: [AgreementStep]
    @State private var showsForm = false

    private var householdAgreements: [Agreement] {
        guard let householdId = session.currentHouseholdID else { return [] }
        return agreements
            .filter { $0.householdId == householdId && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(eyebrow: "OUR LITTLE PROMISES", title: AppCopy.agreements)

                    IllustratedBanner(title: "心地よい毎日を、ふたりで。", subtitle: "ふりかえりから、次にやってみることへ。\nふたりで決めた工夫を、ここに。", scene: .promises, color: AppTheme.sageSoft)

                    Button {
                        showsForm = true
                    } label: {
                        Label("約束をつくる", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if session.cloudPublishFailed {
                        Text("端末には保存されています。共有の同期に失敗しました。下に引っ張って再試行してください。")
                            .font(.bodyRounded(14))
                            .foregroundStyle(AppTheme.terracotta)
                    }

                    if householdAgreements.isEmpty {
                        EmptyNote(text: "ふたりらしい約束を。", symbol: "heart", detail: "まずは大切にしたい約束をひとつ。\nやってみる工夫は、約束ごとに残せます。")
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(householdAgreements.enumerated()), id: \.element.id) { index, agreement in
                                NavigationLink {
                                    AgreementDetailView(agreementID: agreement.id)
                                } label: {
                                    AgreementTile(
                                        title: agreement.title,
                                        subtitle: "\(session.scopeDisplay(for: agreement)) ・ やってみること \(steps.filter { $0.agreementId == agreement.id }.count)件",
                                        index: index
                                    )
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
            .refreshable { await session.refreshFromCloud(markFailure: true) }
            .task { await session.refreshFromCloud() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsForm) {
                AgreementFormView(mode: .create)
            }
        }
    }
}

struct AgreementDetailView: View {
    let agreementID: UUID
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Query private var agreements: [Agreement]
    @State private var showsEdit = false
    @State private var showsDeleteConfirm = false
    @State private var showsStepForm = false

    private var agreement: Agreement? {
        agreements.first(where: { $0.id == agreementID && $0.householdId == session.currentHouseholdID && $0.isActive })
    }

    var body: some View {
        ScrollView {
            if let agreement {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(agreement.title)
                            .font(.titleRounded(26))
                            .foregroundStyle(AppTheme.ink)
                        labeledRow(title: "当てはまる人", value: session.scopeDisplay(for: agreement))
                        if let memo = agreement.memo, !memo.isEmpty {
                            labeledRow(title: "メモ", value: memo)
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()

                    if session.cloudPublishFailed {
                        Text("共有の同期に失敗しました。下に引っ張って再試行してください。")
                            .font(.bodyRounded(14))
                            .foregroundStyle(AppTheme.terracotta)
                    }

                    AgreementStepsView(agreementID: agreement.id)

                    Button { showsStepForm = true } label: {
                        Label("やってみることを残す", systemImage: "plus.circle")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    HStack(spacing: 12) {
                        Button(AppCopy.edit) { showsEdit = true }
                            .buttonStyle(SecondaryButtonStyle())
                        Button(AppCopy.delete) { showsDeleteConfirm = true }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(20)
                .readableWidth()
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await session.refreshFromCloud(markFailure: true) }
        .sheet(isPresented: $showsStepForm) {
            if let agreement {
                AgreementStepFormView(agreement: agreement)
            }
        }
        .sheet(isPresented: $showsEdit) {
            if let agreement {
                AgreementFormView(mode: .edit(agreement))
            }
        }
        .alert(AppCopy.deleteAgreementTitle, isPresented: $showsDeleteConfirm) {
            Button(AppCopy.deleteConfirm, role: .destructive) {
                if let agreement {
                    try? session.deleteAgreement(agreement)
                    dismiss()
                }
            }
            Button(AppCopy.cancel, role: .cancel) {}
        } message: {
            Text(AppCopy.deleteAgreementBody)
        }
    }

    private func labeledRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.bodyRounded(13, weight: .semibold))
                .foregroundStyle(AppTheme.inkMuted)
            Text(value)
                .font(.bodyRounded(16))
                .foregroundStyle(AppTheme.ink)
        }
    }

}

struct AgreementFormView: View {
    enum Mode {
        case create
        case edit(Agreement)
    }

    let mode: Mode
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var scope: ScopeFormSelection = .both
    @State private var memo = ""
    @State private var showsMemo = false
    @State private var saveError: String?
    @State private var didPopulate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("ふたりで大切にしたい約束を残しましょう。やってみる工夫は、保存した約束の詳細から「やってみること」として追加できます。")
                        .font(.bodyRounded(14))
                        .foregroundStyle(AppTheme.inkMuted)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppCopy.whatAgreement)
                            .font(.titleRounded(24))
                            .foregroundStyle(AppTheme.ink)
                        TextField("夕食のあと、5分だけふたりで片づける", text: $title, axis: .vertical)
                            .font(.bodyRounded(17))
                            .lineLimit(3...6)
                            .padding(18)
                            .appCard()
                        Text("\(title.count)/100")
                            .font(.bodyRounded(12))
                            .foregroundStyle(AppTheme.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppCopy.whoApplies)
                            .font(.titleRounded(24))
                            .foregroundStyle(AppTheme.ink)
                        ForEach(session.scopeOptions()) { option in
                            ChoiceCard(selected: scope == option) {
                                scope = option
                            } content: {
                                Text(session.scopeLabel(for: option))
                                    .font(.bodyRounded(16))
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        if showsMemo {
                            Text("メモ")
                                .font(.titleRounded(22))
                                .foregroundStyle(AppTheme.ink)
                            TextField("試すタイミングや、ふりかえりで気づいたこと", text: $memo, axis: .vertical)
                                .font(.bodyRounded(16))
                                .lineLimit(3...6)
                                .padding(18)
                                .appCard()
                        } else {
                            Button(AppCopy.addMemo) {
                                withAnimation { showsMemo = true }
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                    }

                    Button(isEdit ? AppCopy.saveChanges : AppCopy.saveAgreement) {
                        save()
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: canSave))
                    .disabled(!canSave)
                }
                .padding(24)
                .readableWidth()
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
            .alert("保存できませんでした", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "もう一度お試しください。")
            }
            .onAppear { populate() }
            .onChange(of: title) { _, newValue in
                if newValue.count > 100 {
                    title = String(newValue.prefix(100))
                }
            }
        }
        .presentationDetents([.large])
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        session.currentHouseholdID != nil && session.currentUserID != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func populate() {
        guard !didPopulate else { return }
        didPopulate = true
        if case .edit(let agreement) = mode {
            title = agreement.title
            scope = session.formSelection(for: agreement)
            memo = agreement.memo ?? ""
            showsMemo = agreement.memo?.isEmpty == false
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            switch mode {
            case .create:
                try session.addAgreement(title: title, scope: scope, memo: showsMemo ? memo : nil)
            case .edit(let agreement):
                try session.updateAgreement(agreement, title: title, scope: scope, memo: showsMemo ? memo : nil)
            }
            dismiss()
        } catch {
            saveError = "入力内容は残っています。もう一度保存してください。"
        }
    }
}

struct AgreementStepsView: View {
    let agreementID: UUID
    var reviewDate: Date? = nil
    @Query private var steps: [AgreementStep]

    private var visibleSteps: [AgreementStep] {
        steps.filter { step in
            guard step.agreementId == agreementID else { return false }
            guard let reviewDate else { return true }
            // Show the steps available on that day, including ones created from its recap later.
            return AppWeek.startOfDay(step.createdAt) <= AppWeek.startOfDay(reviewDate)
                || step.reviewDate.map { AppWeek.isSameDay($0, reviewDate) } == true
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("この約束でやってみること", systemImage: "sparkles")
                .font(.bodyRounded(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            if visibleSteps.isEmpty {
                Text("この約束でやってみる工夫を、ひとつずつ残せます。")
                    .font(.bodyRounded(14))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            ForEach(visibleSteps) { step in
                VStack(alignment: .leading, spacing: 8) {
                    Text(step.text)
                        .font(.bodyRounded(16))
                        .foregroundStyle(AppTheme.ink)
                    Text(step.reviewDate.map { "\(AppWeek.dayLabel(for: $0))のふりかえりから" }
                         ?? "\(AppWeek.dayLabel(for: step.createdAt))に追加")
                        .font(.bodyRounded(12))
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(AppTheme.sageSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

struct AgreementStepFormView: View {
    let agreement: Agreement
    var reviewDate: Date? = nil
    var onSaved: (() -> Void)? = nil
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saveError: String?

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 500
            && agreement.isActive && agreement.householdId == session.currentHouseholdID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("やってみること")
                        .font(.titleRounded(24))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("この約束について")
                            .font(.bodyRounded(13, weight: .semibold))
                            .foregroundStyle(AppTheme.inkMuted)
                        Text(agreement.title)
                            .font(.bodyRounded(18, weight: .semibold))
                        if let reviewDate {
                            Text("\(AppWeek.dayLabel(for: reviewDate))のふりかえりから")
                                .font(.bodyRounded(13))
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .appCard()

                    Text("この約束のために、どんな工夫をしてみる？")
                        .font(.bodyRounded(16))
                    TextField("例：夕食のあと、5分だけふたりで片づける", text: $text, axis: .vertical)
                        .font(.bodyRounded(17))
                        .lineLimit(4...8)
                        .padding(18)
                        .appCard()
                    Text("\(text.count)/500")
                        .font(.bodyRounded(12))
                        .foregroundStyle(AppTheme.inkMuted)
                    Text("この約束に紐づけて保存し、ふたりで見返せます。")
                        .font(.bodyRounded(14))
                        .foregroundStyle(AppTheme.inkMuted)
                    Button("やってみることを保存する") {
                        do {
                            try session.addStep(agreementID: agreement.id, text: text, reviewDate: reviewDate)
                            onSaved?()
                            dismiss()
                        } catch {
                            saveError = "保存できませんでした。約束が削除されていないか確認し、もう一度お試しください。"
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: canSave))
                    .disabled(!canSave)
                }
                .foregroundStyle(AppTheme.ink)
                .padding(24)
                .readableWidth()
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("とじる") { dismiss() }
                }
            }
            .alert("保存できませんでした", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
    }
}
