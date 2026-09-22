import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import CoreTransferable

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
                    ScreenHeader(eyebrow: "LITTLE MOMENTS", title: "今日のこと")

                    IllustratedBanner(title: "何気ない日も、たいせつな一日。", subtitle: "うれしかったこと、伝えておきたいこと。\n写真やひとことにして、残しておこう。", scene: .journal, color: AppTheme.ochreSoft)

                    Button {
                        showsAdd = true
                    } label: {
                        Label("今日のことを残す", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if thisWeek.isEmpty {
                        EmptyNote(text: "今週のページは、これから。", symbol: "book.closed", detail: "覚えておきたい出来事を、\nあなたの言葉で残せます。")
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
            HStack {
                Text(observation.type.display)
                    .font(.bodyRounded(14, weight: .semibold))
                    .foregroundStyle(color(for: observation.type))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(color(for: observation.type).opacity(0.09), in: Capsule())
                Spacer()
                Text(observation.createdAt, style: .time)
                    .font(.bodyRounded(12))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Text(agreementTitle)
                .font(.bodyRounded(15, weight: .medium))
                .foregroundStyle(AppTheme.ink)
            if let note = observation.note, !note.isEmpty {
                Text(note)
                    .font(.bodyRounded(15))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineSpacing(3)
            }
            if let data = observation.visibleImageData {
                ObservationPhotoView(data: data)
            }
            if !observation.isPublished {
                HStack(spacing: 16) {
                    Button("編集") { onEdit() }
                    Button("削除") { showsDelete = true }
                    Spacer()
                    Text("未公開")
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
    @State private var imageData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsPhotoSource = false
    @State private var showsLibrary = false
    @State private var showsCamera = false
    @State private var isLoadingPhoto = false
    @State private var photoLoadFailed = false

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
                    EmptyNote(text: "先に約束を追加してください")
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
                ScreenHeader(title: AppCopy.aWordTitle)
                TextField("今日の出来事や、そのときの気持ちをひとこと", text: $note, axis: .vertical)
                    .font(.bodyRounded(16))
                    .lineLimit(4...8)
                    .padding(18)
                    .appCard()
                Text("\(note.count)/300")
                    .font(.bodyRounded(12))
                    .foregroundStyle(AppTheme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                photoSection

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
        .confirmationDialog(AppCopy.addPhoto, isPresented: $showsPhotoSource, titleVisibility: .visible) {
            Button(AppCopy.photoLibrary) { showsLibrary = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(AppCopy.takePhoto) { showsCamera = true }
            }
            if imageData != nil {
                Button(AppCopy.removePhoto, role: .destructive) { imageData = nil }
            }
            Button(AppCopy.cancel, role: .cancel) {}
        }
        .photosPicker(isPresented: $showsLibrary, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            loadPhoto(from: item)
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPickerView { data in
                showsCamera = false
                guard let data else { return }
                if let prepared = ObservationPhoto.prepare(data) {
                    imageData = prepared
                } else {
                    photoLoadFailed = true
                }
            }
            .ignoresSafeArea()
        }
        .alert(AppCopy.photoLoadFailedTitle, isPresented: $photoLoadFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(AppCopy.photoLoadFailedBody)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageData, let image = ObservationPhoto.image(from: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel("添付した写真")
            }

            Button {
                showsPhotoSource = true
            } label: {
                HStack(spacing: 10) {
                    if isLoadingPhoto {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "photo")
                    }
                    Text(imageData == nil ? AppCopy.addPhoto : AppCopy.changePhoto)
                    Spacer(minLength: 0)
                }
                .font(.bodyRounded(16, weight: .medium))
                .foregroundStyle(AppTheme.terracotta)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPhoto)
        }
    }

    private func populateIfEditing() {
        guard let editing else { return }
        selectedAgreementID = editing.agreementId
        selectedType = editing.type
        note = editing.note ?? ""
        imageData = editing.visibleImageData
        step = 3
    }

    private func save() {
        guard let agreementId = selectedAgreementID, let type = selectedType else { return }
        do {
            if let editing {
                try session.updateObservation(editing, type: type, note: note, imageData: imageData)
            } else {
                try session.addObservation(agreementId: agreementId, type: type, note: note, imageData: imageData)
            }
            dismiss()
        } catch {}
    }

    private func loadPhoto(from item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            let prepared: Data?
            if let transfer = try? await item.loadTransferable(type: ObservationPhotoTransfer.self) {
                prepared = ObservationPhoto.prepare(transfer.data)
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                prepared = ObservationPhoto.prepare(data)
            } else {
                prepared = nil
            }
            await MainActor.run {
                if let prepared {
                    imageData = prepared
                } else {
                    photoLoadFailed = true
                }
                isLoadingPhoto = false
                pickerItem = nil
            }
        }
    }
}

struct ObservationPhotoView: View {
    let data: Data
    var height: CGFloat = 160
    @State private var showsViewer = false

    var body: some View {
        if let image = ObservationPhoto.image(from: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture { showsViewer = true }
                .fullScreenCover(isPresented: $showsViewer) {
                    ObservationPhotoViewer(image: image)
                }
                .accessibilityLabel("添付した写真")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("拡大して見る")
        }
    }
}

struct ObservationPhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .onTapGesture { dismiss() }
            VStack {
                HStack {
                    Spacer()
                    Button("とじる") { dismiss() }
                        .font(.bodyRounded(16, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(16)
                }
                Spacer()
            }
        }
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.originalImage] as? UIImage)
            onFinish(image?.jpegData(compressionQuality: 0.9))
        }
    }
}

private struct ObservationPhotoTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ObservationPhotoTransfer(data: data)
        }
    }
}
