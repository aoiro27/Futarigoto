import SwiftUI

enum AppTheme {
    static let cream = Color(red: 0.969, green: 0.945, blue: 0.910)
    static let creamDeep = Color(red: 0.945, green: 0.910, blue: 0.855)
    static let paper = Color(red: 1.000, green: 0.988, blue: 0.976)
    static let terracotta = Color(red: 0.769, green: 0.471, blue: 0.353)
    static let terracottaSoft = Color(red: 0.769, green: 0.471, blue: 0.353).opacity(0.14)
    static let ink = Color(red: 0.239, green: 0.204, blue: 0.173)
    static let inkMuted = Color(red: 0.541, green: 0.478, blue: 0.424)
    static let sage = Color(red: 0.478, green: 0.608, blue: 0.478)
    static let sageSoft = Color(red: 0.478, green: 0.608, blue: 0.478).opacity(0.14)
    static let ochre = Color(red: 0.769, green: 0.627, blue: 0.353)
    static let ochreSoft = Color(red: 0.769, green: 0.627, blue: 0.353).opacity(0.16)
    static let sky = Color(red: 0.420, green: 0.541, blue: 0.604)
    static let skySoft = Color(red: 0.420, green: 0.541, blue: 0.604).opacity(0.14)
    static let line = Color(red: 0.855, green: 0.804, blue: 0.745)

    static let cardRadius: CGFloat = 22
    static let buttonRadius: CGFloat = 16
}

extension Font {
    static func titleSerif(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func bodyRounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .shadow(color: AppTheme.ink.opacity(0.06), radius: 16, x: 0, y: 6)
    }
}

extension View {
    func appCard() -> some View {
        modifier(CardBackground())
    }

    func screenBackground() -> some View {
        background(AppTheme.cream.ignoresSafeArea())
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? AppTheme.terracotta.opacity(0.45) : AppTheme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    .tracking(1.2)
            }
            Text(title)
                .font(.titleSerif(28))
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
        Text(text)
            .font(.bodyRounded(15))
            .foregroundStyle(AppTheme.inkMuted)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity)
            .appCard()
    }
}
