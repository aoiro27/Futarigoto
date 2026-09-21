import SwiftUI

struct WelcomeView: View {
    @Environment(AppSession.self) private var session
    @State private var path: [OnboardingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Spacer()
                WelcomeIllustration()
                    .padding(.bottom, 36)

                Text(AppCopy.welcomeTitle)
                    .font(.titleRounded(32))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)

                Text(AppCopy.welcomeBody)
                    .font(.bodyRounded(16))
                    .foregroundStyle(AppTheme.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.top, 20)

                Spacer()

                VStack(spacing: 14) {
                    Button(AppCopy.start) {
                        path.append(.createUser)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("招待コードを持っている") {
                        path.append(.join)
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .readableWidth()
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
        ZStack {
            Circle()
                .fill(AppTheme.sageSoft)
                .frame(width: 148, height: 148)
                .offset(x: -28, y: 8)
            Circle()
                .fill(AppTheme.terracottaSoft)
                .frame(width: 148, height: 148)
                .offset(x: 28, y: -8)
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppTheme.paper)
                .frame(width: 112, height: 112)
                .rotationEffect(.degrees(-8))
                .shadow(color: AppTheme.terracotta.opacity(0.08), radius: 16, y: 8)
            Image(systemName: "house")
                .font(.system(size: 48, weight: .ultraLight, design: .rounded))
                .foregroundStyle(AppTheme.terracotta)
            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.terracotta)
                .offset(y: 8)
            Image(systemName: "leaf.fill")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(AppTheme.sage)
                .rotationEffect(.degrees(-25))
                .offset(x: -75, y: 48)
        }
        .frame(height: 170)
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
                ScreenHeader(
                    title: AppCopy.yourName,
                    subtitle: mode == .join
                        ? "パートナーが渡してくれたコードで、同じ家庭に入ります。"
                        : "家のなかで呼び合う名前で大丈夫です。"
                )

                VStack(alignment: .leading, spacing: 8) {
                    TextField("ゆうき", text: $name)
                        .font(.bodyRounded(20))
                        .padding(18)
                        .appCard()
                    Text("例：ゆうき")
                        .font(.bodyRounded(13))
                        .foregroundStyle(AppTheme.inkMuted)
                        .padding(.leading, 6)
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
                ScreenHeader(
                    title: AppCopy.startTogetherTitle,
                    subtitle: AppCopy.startTogetherBody
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("招待コード")
                        .font(.bodyRounded(13, weight: .semibold))
                        .foregroundStyle(AppTheme.terracotta)
                    Text(session.currentHousehold?.inviteCode ?? "")
                        .font(.titleRounded(36))
                        .foregroundStyle(AppTheme.ink)
                        .tracking(4)
                    Text("このコードをパートナーに渡してください。相手の端末で同じコードを入力すると、同じ家庭につながります。")
                        .font(.bodyRounded(15))
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                Button("招待を送る") {
                    showsShare = true
                }
                .buttonStyle(PrimaryButtonStyle())

                if session.cloudPublishFailed {
                    Text("まだ相手と共有できていません。iCloudにサインインしてから、もう一度試してください。")
                        .font(.bodyRounded(14))
                        .foregroundStyle(AppTheme.terracotta)
                    Button("共有し直す") {
                        Task { await session.retryCloudPublish() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Button("ホームへ進む") {
                    session.dismissPostCreateInvite()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Text("ひとりでも、約束を残しておくことはできます。パートナーはあとから参加できます。")
                    .font(.bodyRounded(14))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.top, 8)
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
