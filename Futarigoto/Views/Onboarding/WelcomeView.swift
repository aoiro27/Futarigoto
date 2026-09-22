import SwiftUI

struct WelcomeView: View {
    @Environment(AppSession.self) private var session
    @State private var path: [OnboardingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
            VStack(spacing: 0) {
                Text("ふたりの暮らしに、小さな花を。")
                    .font(.bodyRounded(14, weight: .medium))
                    .foregroundStyle(AppTheme.terracotta)
                    .padding(.top, 36)
                    .padding(.bottom, 28)
                WelcomeIllustration()
                    .padding(.bottom, 28)

                Text(AppCopy.welcomeTitle)
                    .font(.titleRounded(32))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)

                Text("伝えることから、\nもっと心地よい、わが家へ。")
                    .font(.bodyRounded(16))
                    .foregroundStyle(AppTheme.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.top, 20)

                VStack(spacing: 14) {
                    Button(AppCopy.start) {
                        path.append(.createUser)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("招待コードを持っている") {
                        path.append(.join)
                    }
                    .buttonStyle(QuietButtonStyle())
                    .frame(minHeight: 44)
                }
                .padding(.top, 36)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .readableWidth()
            }
            .screenBackground()
            .navigationDestination(for: OnboardingRoute.self) { route in
                switch route {
                case .createUser:
                    CreateUserView(mode: .createHousehold)
                case .join:
                    CreateUserView(mode: .join)
                }
            }
            .onAppear {
                if session.pendingInviteCode != nil, path.isEmpty {
                    path = [.join]
                }
            }
        }
        .tint(AppTheme.terracotta)
    }
}

enum OnboardingRoute: Hashable {
    case createUser
    case join
}

struct WelcomeIllustration: View {
    var body: some View {
        TogetherIllustration()
            .frame(maxWidth: 360)
            .padding(12)
            .background(AppTheme.terracottaSoft, in: RoundedRectangle(cornerRadius: 48))
            .rotationEffect(.degrees(-3))
            .accessibilityHidden(true)
    }
}

struct CreateUserView: View {
    enum Mode {
        case createHousehold
        case join
    }

    let mode: Mode
    @Environment(AppSession.self) private var session
    @State private var name = ""
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(title: AppCopy.yourName)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("ゆうき", text: $name)
                        .font(.bodyRounded(20))
                        .padding(18)
                        .appCard()
                }

                if mode == .join {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("招待コード")
                            .font(.titleRounded(22))
                            .foregroundStyle(AppTheme.ink)
                        TextField("ABC123", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .textContentType(.oneTimeCode)
                            .font(.bodyRounded(20))
                            .padding(18)
                            .appCard()
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.bodyRounded(14))
                        .foregroundStyle(AppTheme.terracotta)
                }

                Button(mode == .join ? "家庭に入る" : "家庭をつくる") {
                    Task { await submit() }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: canSubmit && !isWorking))
                .disabled(!canSubmit || isWorking)

                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(mode == .join ? "家庭を探しています…" : "家庭をつくっています…")
                            .font(.bodyRounded(14))
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .readableWidth()
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let pending = session.pendingInviteCode, code.isEmpty {
                code = pending
            }
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (mode == .createHousehold || !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func submit() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            if mode == .join {
                try await session.createUserAndJoin(displayName: name, code: code)
            } else {
                try await session.createUserAndHousehold(displayName: name)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InvitePartnerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showsShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(title: AppCopy.startTogetherTitle)

                VStack(alignment: .leading, spacing: 12) {
                    Text("招待コード")
                        .font(.bodyRounded(13, weight: .semibold))
                        .foregroundStyle(AppTheme.terracotta)
                    Text(session.currentHousehold?.inviteCode ?? "")
                        .font(.titleRounded(36))
                        .foregroundStyle(AppTheme.ink)
                        .tracking(4)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                Button("送る") {
                    showsShare = true
                }
                .buttonStyle(PrimaryButtonStyle())

                if session.cloudPublishFailed {
                    Text("共有できませんでした。通信できる場所でもう一度試してください。")
                        .font(.bodyRounded(14))
                        .foregroundStyle(AppTheme.terracotta)
                    Button("もう一度") {
                        Task { await session.retryCloudPublish() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Button("あとで") {
                    session.dismissPostCreateInvite()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(24)
            .readableWidth()
        }
        .screenBackground()
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsShare) {
            ShareSheet(items: [session.inviteShareText])
        }
        .task {
            await session.retryCloudPublish()
        }
    }
}
