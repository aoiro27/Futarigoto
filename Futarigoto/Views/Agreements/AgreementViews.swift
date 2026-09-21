import SwiftUI
import SwiftData

struct AgreementListView: View {
    @Environment(AppSession.self) private var session
    @Query private var agreements: [Agreement]
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
                    ScreenHeader(
                        title: AppCopy.agreements,
                        subtitle: "ふたりで話して決めたことを、ここに残します。"
                    )

                    Button("約束を追加する") {
                        showsForm = true
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if householdAgreements.isEmpty {
                        EmptyNote(text: "まだ約束はありません。家で大切にしたいことを、一文で残してみましょう。")
                    } else {
                        VStack(spacing: 10) {
                            ForEach(householdAgreements) { agreement in
                                NavigationLink {
                                    AgreementDetailView(agreementID: agreement.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(agreement.title)
                                            .font(.bodyRounded(17, weight: .medium))
                                            .foregroundStyle(AppTheme.ink)
                                            .multilineTextAlignment(.leading)
                                        Text(session.scopeDisplay(for: agreement))
                                            .font(.bodyRounded(13))
                                            .foregroundStyle(AppTheme.inkMuted)
                                    }
                                    .padding(18)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
    @Query private var observations: [DailyObservation]
    @State private var showsEdit = false
    @State private var showsDeleteConfirm = false

    private var agreement: Agreement? {
        agreements.first(where: { $0.id == agreementID })
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

                    HStack(spacing: 12) {
                        Button(AppCopy.edit) { showsEdit = true }
                            .buttonStyle(SecondaryButtonStyle())
                        Button(AppCopy.delete) { showsDeleteConfirm = true }
                            .buttonStyle(QuietButtonStyle())
                    }

                    historySection(for: agreement)
                    monthlySection(for: agreement)
                    Color.clear.frame(height: 0).accessibilityHidden(true)
                        .onAppear { _ = observations.count }
                }
                .padding(20)
                .readableWidth()
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private func historySection(for agreement: Agreement) -> some View {
        let weeks = session.weeklySummaries(for: agreement)
        VStack(alignment: .leading, spacing: 12) {
            Text(AppCopy.untilNow)
                .font(.titleRounded(22))
                .foregroundStyle(AppTheme.ink)
            if weeks.isEmpty {
                Text("まだ記録はありません。")
                    .font(.bodyRounded(15))
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                VStack(spacing: 8) {
                    ForEach(weeks) { week in
                        HStack {
                            Text(week.label)
                                .font(.bodyRounded(16, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text("😊 \(week.positiveCount)件　😕 \(week.concernCount)件")
                                .font(.bodyRounded(15))
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        .padding(16)
                        .appCard()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func monthlySection(for agreement: Agreement) -> some View {
        let months = session.monthlyConcerns(for: agreement)
        if !months.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(months) { month in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(month.label)
                            .font(.bodyRounded(16, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                        Text("気になったこと　\(month.concernCount)件")
                            .font(.bodyRounded(15))
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
                }
            }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if isEdit {
                        Text(AppCopy.talkFirst)
                            .font(.bodyRounded(15))
                            .foregroundStyle(AppTheme.inkMuted)
                            .padding(.bottom, -8)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppCopy.whatAgreement)
                            .font(.titleRounded(24))
                            .foregroundStyle(AppTheme.ink)
                        TextField("帰りが遅くなりそうなときは連絡する", text: $title, axis: .vertical)
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
                            TextField("遅くなると分かった時点で連絡する。", text: $memo, axis: .vertical)
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
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func populate() {
        if case .edit(let agreement) = mode {
            title = agreement.title
            scope = session.formSelection(for: agreement)
            memo = agreement.memo ?? ""
            showsMemo = agreement.memo?.isEmpty == false
        }
    }

    private func save() {
        do {
            switch mode {
            case .create:
                try session.addAgreement(title: title, scope: scope, memo: showsMemo ? memo : nil)
            case .edit(let agreement):
                try session.updateAgreement(agreement, title: title, scope: scope, memo: showsMemo ? memo : nil)
            }
            dismiss()
        } catch {}
    }
}
