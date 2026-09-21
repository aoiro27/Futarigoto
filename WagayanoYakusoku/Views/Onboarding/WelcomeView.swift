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
                    .font(.titleSerif(32))
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
            Image(systemName: "house")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppTheme.terracotta)
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
                            .font(.titleSerif(22))
                            .foregroundStyle(AppTheme.ink)
                        TextField("ABC123", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
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
                    submit()
                }
                .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                .disabled(!canSubmit)
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

    private func submit() {
        errorMessage = nil
        do {
            if mode == .join {
                try session.createUserAndJoin(displayName: name, code: code)
            } else {
                try session.createUserAndHousehold(displayName: name)
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
    @State private var partnerName = ""
    @State private var showsLocalPartner = false
    @State private var errorMessage: String?

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
                        .font(.titleSerif(36))
                        .foregroundStyle(AppTheme.ink)
                        .tracking(4)
                    Text("このコードか、下のリンクをパートナーに渡してください。")
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

                Button(showsLocalPartner ? "入力を閉じる" : "この端末でパートナーとしてはじめる") {
                    withAnimation { showsLocalPartner.toggle() }
                }
                .buttonStyle(QuietButtonStyle())
                .frame(maxWidth: .infinity)

                if showsLocalPartner {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("パートナーの呼び名")
                            .font(.bodyRounded(15, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                        TextField("あい", text: $partnerName)
                            .font(.bodyRounded(18))
                            .padding(16)
                            .background(AppTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Button("パートナーとしてはじめる") {
                            do {
                                try session.addPartnerOnThisDevice(displayName: partnerName)
                                session.dismissPostCreateInvite()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(partnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(20)
                    .appCard()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.bodyRounded(14))
                        .foregroundStyle(AppTheme.terracotta)
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
    }
}
