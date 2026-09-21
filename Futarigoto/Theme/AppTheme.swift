import SwiftUI

enum AppTheme {
    static let cream = Color(red: 0.992, green: 0.969, blue: 0.949)
    static let creamDeep = Color(red: 0.957, green: 0.914, blue: 0.886)
    static let paper = Color(red: 1.000, green: 0.992, blue: 0.984)
    static let terracotta = Color(red: 0.647, green: 0.365, blue: 0.400)
    static let terracottaSoft = Color(red: 0.961, green: 0.878, blue: 0.871)
    static let ink = Color(red: 0.310, green: 0.251, blue: 0.247)
    static let inkMuted = Color(red: 0.478, green: 0.396, blue: 0.380)
    static let sage = Color(red: 0.357, green: 0.478, blue: 0.388)
    static let sageSoft = Color(red: 0.894, green: 0.929, blue: 0.882)
    static let ochre = Color(red: 0.573, green: 0.431, blue: 0.227)
    static let ochreSoft = Color(red: 0.973, green: 0.925, blue: 0.820)
    static let sky = Color(red: 0.365, green: 0.467, blue: 0.529)
    static let skySoft = Color(red: 0.894, green: 0.929, blue: 0.945)
    static let line = Color(red: 0.898, green: 0.831, blue: 0.808)

    static let cardRadius: CGFloat = 28
    static let buttonRadius: CGFloat = 26
}

extension Font {
    static func titleRounded(_ size: CGFloat) -> Font {
        .custom("HiraginoMaruGothicProN-W4", size: size, relativeTo: .title2)
    }

    static func bodyRounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("HiraginoMaruGothicProN-W4", size: size, relativeTo: .body)
            .weight(weight)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .strokeBorder(AppTheme.line.opacity(0.4), lineWidth: 1)
            }
            .shadow(color: AppTheme.terracotta.opacity(0.045), radius: 18, x: 0, y: 6)
    }
}

extension View {
    func appCard() -> some View {
        modifier(CardBackground())
    }

    func screenBackground() -> some View {
        background {
            LinearGradient(
                colors: [AppTheme.cream, AppTheme.paper, AppTheme.cream],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    func readableWidth() -> some View {
        frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyRounded(17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(enabled ? AppTheme.terracotta : AppTheme.terracotta.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyRounded(17, weight: .semibold))
            .foregroundStyle(AppTheme.terracotta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.paper)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyRounded(16, weight: .medium))
            .foregroundStyle(AppTheme.inkMuted)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct ChoiceCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                content()
                Spacer(minLength: 0)
                Circle()
                    .stroke(selected ? AppTheme.terracotta : AppTheme.line, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if selected {
                            Circle()
                                .fill(AppTheme.terracotta)
                                .frame(width: 12, height: 12)
                        }
                    }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AppTheme.terracottaSoft : AppTheme.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(selected ? AppTheme.terracotta.opacity(0.45) : AppTheme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ScreenHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.bodyRounded(13, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)
                    .tracking(0.6)
            }
            Text(title)
                .font(.titleRounded(28))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.bodyRounded(16))
                    .foregroundStyle(AppTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyNote: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 26, weight: .light, design: .rounded))
                .foregroundStyle(AppTheme.terracotta)
                .accessibilityHidden(true)
            Text(text)
                .lineSpacing(5)
        }
            .font(.bodyRounded(15))
            .foregroundStyle(AppTheme.inkMuted)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity)
            .appCard()
    }
}

struct WarmMotif: View {
    let symbol: String
    var color: Color = AppTheme.terracotta
    var background: Color = AppTheme.terracottaSoft

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .light, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 48, height: 48)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }
}
