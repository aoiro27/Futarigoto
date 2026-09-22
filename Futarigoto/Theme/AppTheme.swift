import SwiftUI

enum AppTheme {
    static let cream = Color(red: 1.000, green: 0.977, blue: 0.953)
    static let creamDeep = Color(red: 0.957, green: 0.914, blue: 0.886)
    static let paper = Color(red: 1.000, green: 0.992, blue: 0.984)
    static let terracotta = Color(red: 0.710, green: 0.290, blue: 0.357)
    static let terracottaSoft = Color(red: 1.000, green: 0.875, blue: 0.831)
    static let ink = Color(red: 0.286, green: 0.263, blue: 0.337)
    static let inkMuted = Color(red: 0.478, green: 0.431, blue: 0.478)
    static let sage = Color(red: 0.357, green: 0.478, blue: 0.388)
    static let sageSoft = Color(red: 0.865, green: 0.933, blue: 0.867)
    static let ochre = Color(red: 0.573, green: 0.431, blue: 0.227)
    static let ochreSoft = Color(red: 0.973, green: 0.925, blue: 0.820)
    static let sky = Color(red: 0.365, green: 0.467, blue: 0.529)
    static let skySoft = Color(red: 0.894, green: 0.929, blue: 0.945)
    static let line = Color(red: 0.898, green: 0.831, blue: 0.808)

    static let lavender = Color(red: 0.913, green: 0.883, blue: 0.973)
    static let plum = Color(red: 0.447, green: 0.345, blue: 0.580)
    static let peach = Color(red: 0.980, green: 0.678, blue: 0.557)

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
                    .strokeBorder(AppTheme.line.opacity(0.25), lineWidth: 1)
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
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
    var symbol: String = "sparkles"
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.plum)
                .frame(width: 64, height: 64)
                .background(AppTheme.lavender, in: RoundedRectangle(cornerRadius: 24))
                .rotationEffect(.degrees(-8))
                .accessibilityHidden(true)
            Text(text)
                .font(.bodyRounded(16, weight: .medium))
                .foregroundStyle(AppTheme.ink)
            if let detail {
                Text(detail)
                    .font(.bodyRounded(14))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineSpacing(5)
            }
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: .infinity)
        .appCard()
    }
}

/// Small native illustrations stay sharp at every screen size, without remote assets.
struct TogetherIllustration: View {
    enum Scene { case home, journal, promises }
    var scene: Scene = .home

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 320, size.height / 200)
            context.translateBy(x: (size.width - 320 * scale) / 2, y: (size.height - 200 * scale) / 2)
            context.scaleBy(x: scale, y: scale)

            func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
            }
            func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: Color) {
                context.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r), with: .color(color))
            }
            func line(_ points: [CGPoint], _ color: Color, _ width: CGFloat = 3) {
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func face(_ x: CGFloat, _ y: CGFloat) {
                ellipse(x - 12, y, 3.5, 5, AppTheme.ink)
                ellipse(x + 9, y, 3.5, 5, AppTheme.ink)
                ellipse(x - 22, y + 8, 10, 5, AppTheme.peach.opacity(0.7))
                ellipse(x + 13, y + 8, 10, 5, AppTheme.peach.opacity(0.7))
                var smile = Path()
                smile.move(to: CGPoint(x: x - 5, y: y + 9))
                smile.addQuadCurve(to: CGPoint(x: x + 5, y: y + 9), control: CGPoint(x: x, y: y + 16))
                context.stroke(smile, with: .color(AppTheme.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            func flower(_ x: CGFloat, _ y: CGFloat, _ color: Color) {
                for index in 0..<6 {
                    let angle = Double(index) * .pi / 3
                    ellipse(x + CGFloat(cos(angle)) * 10 - 7, y + CGFloat(sin(angle)) * 10 - 7, 14, 14, color)
                }
                ellipse(x - 6, y - 6, 12, 12, AppTheme.ochreSoft)
            }
            ellipse(30, 169, 260, 18, AppTheme.ink.opacity(0.055))
            ellipse(53, 17, 211, 163, AppTheme.paper.opacity(0.65))

            switch scene {
            case .home:
                rounded(103, 64, 116, 105, 16, AppTheme.ochreSoft)
                var roof = Path()
                roof.move(to: CGPoint(x: 88, y: 76))
                roof.addLine(to: CGPoint(x: 160, y: 23))
                roof.addLine(to: CGPoint(x: 233, y: 76))
                roof.closeSubpath()
                context.fill(roof, with: .color(AppTheme.peach))
                rounded(144, 112, 33, 57, 16, AppTheme.paper)
                rounded(120, 83, 22, 22, 7, AppTheme.paper)
                rounded(181, 83, 22, 22, 7, AppTheme.paper)
                ellipse(47, 110, 76, 66, AppTheme.sageSoft)
                face(85, 135)
                rounded(206, 102, 69, 76, 29, AppTheme.lavender)
                face(240, 131)
                flower(47, 65, AppTheme.peach)
                flower(272, 53, AppTheme.lavender)
            case .journal:
                rounded(87, 36, 137, 139, 15, AppTheme.plum.opacity(0.16))
                rounded(79, 27, 137, 139, 15, AppTheme.paper)
                rounded(79, 27, 20, 139, 9, AppTheme.peach)
                rounded(116, 48, 76, 58, 9, AppTheme.sageSoft)
                ellipse(141, 59, 28, 28, AppTheme.ochreSoft)
                face(155, 69)
                line([CGPoint(x: 116, y: 124), CGPoint(x: 187, y: 124)], AppTheme.line)
                line([CGPoint(x: 116, y: 139), CGPoint(x: 165, y: 139)], AppTheme.line)
                rounded(207, 110, 61, 65, 25, AppTheme.lavender)
                face(237, 132)
                flower(53, 116, AppTheme.peach)
                flower(258, 54, AppTheme.sageSoft)
            case .promises:
                rounded(72, 66, 174, 107, 18, AppTheme.paper)
                var flap = Path()
                flap.move(to: CGPoint(x: 74, y: 71))
                flap.addLine(to: CGPoint(x: 159, y: 132))
                flap.addLine(to: CGPoint(x: 244, y: 71))
                context.stroke(flap, with: .color(AppTheme.peach), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                ellipse(126, 34, 39, 39, AppTheme.peach)
                ellipse(156, 34, 39, 39, AppTheme.peach)
                var heart = Path()
                heart.move(to: CGPoint(x: 129, y: 60))
                heart.addLine(to: CGPoint(x: 160, y: 94))
                heart.addLine(to: CGPoint(x: 192, y: 60))
                heart.closeSubpath()
                context.fill(heart, with: .color(AppTheme.peach))
                flower(51, 65, AppTheme.lavender)
                flower(265, 126, AppTheme.sageSoft)
            }
            ellipse(76, 38, 5, 5, AppTheme.plum.opacity(0.5))
            ellipse(285, 94, 6, 6, AppTheme.peach)
            line([CGPoint(x: 29, y: 141), CGPoint(x: 29, y: 153)], AppTheme.sage)
            line([CGPoint(x: 23, y: 147), CGPoint(x: 35, y: 147)], AppTheme.sage)
        }
        .aspectRatio(1.6, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct IllustratedBanner: View {
    let title: String
    let subtitle: String
    var scene: TogetherIllustration.Scene = .home
    var color: Color = AppTheme.terracottaSoft

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TogetherIllustration(scene: scene)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.titleRounded(23))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.bodyRounded(14))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 30))
    }
}

struct AgreementTile: View {
    let title: String
    var subtitle: String? = nil
    var index: Int = 0
    var showsDisclosure: Bool = true

    private var colors: [Color] { [AppTheme.sageSoft, AppTheme.lavender, AppTheme.ochreSoft, AppTheme.terracottaSoft] }
    private var symbols: [String] { ["leaf.fill", "heart.fill", "sun.max.fill", "house.fill"] }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbols[index % symbols.count])
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.7))
                .frame(width: 48, height: 52)
                .background(colors[index % colors.count], in: RoundedRectangle(cornerRadius: 18))
                .rotationEffect(.degrees(index.isMultiple(of: 2) ? -6 : 6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.bodyRounded(16, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.bodyRounded(12))
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.top, 19)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(20)
        .appCard()
    }
}
