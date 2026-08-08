import AppKit
import SwiftUI

enum AppTheme {
    static let background = adaptiveColor(light: 0xF7F8FB, dark: 0x101418)
    static let surface = adaptiveColor(light: 0xFFFFFF, dark: 0x1A1F25)
    static let surfaceAlt = adaptiveColor(light: 0xEEF3F8, dark: 0x151A20)
    static let field = adaptiveColor(light: 0xF8FAFC, dark: 0x222832)
    static let text = Color.primary
    static let muted = Color.secondary
    static let line = adaptiveColor(light: 0xDFE5EC, dark: 0x313944)
    static let softLine = adaptiveColor(light: 0xBCC7D5, dark: 0x465262).opacity(0.7)
    static let selection = adaptiveColor(light: 0xDFEFFF, dark: 0x183A5C)
    static let progressTrack = adaptiveColor(light: 0xDAE3EE, dark: 0x313944)
    static let dropBorder = adaptiveColor(light: 0x9DB6D8, dark: 0x3D648C)
    static let cardShadow = adaptiveColor(light: 0x12243D, dark: 0x000000)
    static let blue = adaptiveColor(light: 0x1267DC, dark: 0x5EA2FF)
    static let blueStrong = adaptiveColor(light: 0x0757C8, dark: 0x3F86E8)
    static let blueHighlight = adaptiveColor(light: 0x4CA0FF, dark: 0x83BEFF)
    static let blueSoft = adaptiveColor(light: 0xE8F1FF, dark: 0x17324F)
    static let red = adaptiveColor(light: 0xE82F2F, dark: 0xFF6B6B)
    static let redSoft = adaptiveColor(light: 0xFFF1F1, dark: 0x3A1E22)
    static let green = adaptiveColor(light: 0x2BA84A, dark: 0x54D06D)
    static let orange = adaptiveColor(light: 0xFF9F1C, dark: 0xFFB74D)

    static let radius: CGFloat = 8

    private static func adaptiveColor(light: Int, dark: Int, opacity: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark,
                .darkAqua,
                .vibrantDark,
                .accessibilityHighContrastAqua,
                .accessibilityHighContrastVibrantLight,
                .aqua,
                .vibrantLight
            ])
            let resolvedHex = match?.isDarkAppearance == true ? dark : light
            return NSColor(hex: resolvedHex, opacity: opacity)
        })
    }
}

private extension NSAppearance.Name {
    var isDarkAppearance: Bool {
        switch self {
        case .accessibilityHighContrastDarkAqua,
             .accessibilityHighContrastVibrantDark,
             .darkAqua,
             .vibrantDark:
            return true
        default:
            return false
        }
    }
}

private extension NSColor {
    convenience init(hex: Int, opacity: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(opacity)
        )
    }
}

extension Color {
    init(hex: Int, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct AppDivider: View {
    enum Axis {
        case horizontal
        case vertical
    }

    var axis: Axis

    var body: some View {
        Rectangle()
            .fill(AppTheme.line)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

struct BrandMarkView: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.blue, AppTheme.blueHighlight],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
    }
}

struct AppCardModifier: ViewModifier {
    var padding: CGFloat
    var background: Color
    var border: Color
    var shadow: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background, in: RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
            .shadow(
                color: shadow ? AppTheme.cardShadow.opacity(0.10) : .clear,
                radius: shadow ? 18 : 0,
                x: 0,
                y: shadow ? 8 : 0
            )
    }
}

extension View {
    func appCard(
        padding: CGFloat = 16,
        background: Color = AppTheme.surface,
        border: Color = AppTheme.line,
        shadow: Bool = false
    ) -> some View {
        modifier(AppCardModifier(padding: padding, background: background, border: border, shadow: shadow))
    }
}

struct AppInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(AppTheme.text)
            .tint(AppTheme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
    }
}

extension View {
    func appInput() -> some View {
        modifier(AppInputModifier())
    }
}

struct PrimaryAppButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(configuration.isPressed ? AppTheme.blueStrong : AppTheme.blue)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
            .shadow(color: AppTheme.blue.opacity(configuration.isPressed ? 0.08 : 0.22), radius: 12, x: 0, y: 6)
    }
}

struct SecondaryAppButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(configuration.isPressed ? AppTheme.surfaceAlt : AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
    }
}

struct LinearUploadProgressView: View {
    var value: Double
    var tint: Color = AppTheme.blue
    var sparkles = false
    var accessibilityLabelText = "Upload progress"

    var body: some View {
        GeometryReader { proxy in
            let clampedValue = min(max(value, 0), 1)
            let progressWidth = proxy.size.width * clampedValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.progressTrack)

                if sparkles {
                    UploadProgressSparkleLayer(color: tint.opacity(0.82))
                        .opacity(0.38)
                }

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.82),
                                tint,
                                tint.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: progressWidth)
                    .overlay {
                        if sparkles {
                            UploadProgressSparkleLayer(color: .white)
                                .opacity(0.72)
                                .blendMode(.screen)
                        }
                    }
                    .clipShape(Capsule())
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(sparkles ? tint.opacity(0.32) : .clear, lineWidth: 0.5)
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}

private struct UploadProgressSparkleLayer: View {
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            UploadProgressSparkleCanvas(color: color, time: 0.35)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                UploadProgressSparkleCanvas(
                    color: color,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
    }
}

private struct UploadProgressSparkleCanvas: View {
    var color: Color
    var time: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            for sparkle in UploadProgressSparkle.all {
                var sparkleContext = context
                let wave = sin((time * sparkle.speed) + sparkle.phase)
                let twinkle = 0.5 + (0.5 * wave)
                let drift = sin((time * 0.42) + sparkle.phase) * sparkle.drift
                let center = CGPoint(
                    x: (sparkle.x * size.width) + drift,
                    y: sparkle.y * size.height
                )
                let radius = sparkle.size * (0.68 + (0.42 * twinkle))
                let alpha = sparkle.opacity * (0.36 + (0.64 * twinkle))
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                sparkleContext.opacity = alpha
                sparkleContext.fill(Path(ellipseIn: rect), with: .color(color))

                if sparkle.drawsStar {
                    var star = Path()
                    star.move(to: CGPoint(x: center.x, y: center.y - radius * 2.2))
                    star.addLine(to: CGPoint(x: center.x, y: center.y + radius * 2.2))
                    star.move(to: CGPoint(x: center.x - radius * 2.2, y: center.y))
                    star.addLine(to: CGPoint(x: center.x + radius * 2.2, y: center.y))

                    sparkleContext.stroke(
                        star,
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: max(0.45, radius * 0.38),
                            lineCap: .round
                        )
                    )
                }
            }
        }
    }
}

private struct UploadProgressSparkle {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let phase: TimeInterval
    let speed: TimeInterval
    let drift: CGFloat
    let opacity: Double
    let drawsStar: Bool

    static let all: [UploadProgressSparkle] = [
        UploadProgressSparkle(
            x: 0.05,
            y: 0.38,
            size: 1.1,
            phase: 0.2,
            speed: 2.8,
            drift: 1.2,
            opacity: 0.68,
            drawsStar: false
        ),
        UploadProgressSparkle(
            x: 0.12,
            y: 0.70,
            size: 0.9,
            phase: 1.5,
            speed: 3.4,
            drift: 0.8,
            opacity: 0.56,
            drawsStar: false
        ),
        UploadProgressSparkle(
            x: 0.19,
            y: 0.43,
            size: 1.4,
            phase: 3.0,
            speed: 2.4,
            drift: 1.5,
            opacity: 0.78,
            drawsStar: true
        ),
        UploadProgressSparkle(
            x: 0.27,
            y: 0.62,
            size: 0.8,
            phase: 4.6,
            speed: 3.1,
            drift: 1.0,
            opacity: 0.58,
            drawsStar: false
        ),
        UploadProgressSparkle(
            x: 0.34,
            y: 0.31,
            size: 1.0,
            phase: 5.7,
            speed: 2.9,
            drift: 1.4,
            opacity: 0.62,
            drawsStar: false
        ),
        UploadProgressSparkle(
            x: 0.42,
            y: 0.58,
            size: 1.2,
            phase: 2.1,
            speed: 3.8,
            drift: 0.7,
            opacity: 0.72,
            drawsStar: true
        ),
        UploadProgressSparkle(
            x: 0.50,
            y: 0.37,
            size: 0.9,
            phase: 6.0,
            speed: 3.3,
            drift: 1.3,
            opacity: 0.58,
            drawsStar: false
        ),
        UploadProgressSparkle(
            x: 0.58,
            y: 0.66,
            size: 1.3,
            phase: 0.9,
            speed: 2.7,
            drift: 1.6,
            opacity: 0.74,
            drawsStar: true
        ),
        UploadProgressSparkle(
            x: 0.65,
            y: 0.42,
            size: 0.8,
            phase: 3.8,
            speed: 3.6,
            drift: 0.9,
            opacity: 0.60,
            drawsStar: false
        ),
        UploadProgressSparkle(
            x: 0.73,
            y: 0.28,
            size: 1.1,
            phase: 4.9,
            speed: 2.5,
            drift: 1.4,
            opacity: 0.64,
            drawsStar: false
        ),
        UploadProgressSparkle(
            x: 0.80,
            y: 0.63,
            size: 1.4,
            phase: 2.7,
            speed: 3.2,
            drift: 1.1,
            opacity: 0.80,
            drawsStar: true
        ),
        UploadProgressSparkle(
            x: 0.88,
            y: 0.40,
            size: 0.9,
            phase: 5.2,
            speed: 3.5,
            drift: 1.2,
            opacity: 0.58,
            drawsStar: false
        ),
        UploadProgressSparkle(
            x: 0.95,
            y: 0.68,
            size: 1.0,
            phase: 1.1,
            speed: 2.6,
            drift: 0.7,
            opacity: 0.62,
            drawsStar: false
        )
    ]
}
