import SwiftUI

enum AdminTheme {
    static let violet = Color(red: 0.43, green: 0.34, blue: 0.98)
    static let deepViolet = Color(red: 0.27, green: 0.20, blue: 0.78)
    static let canvas = Color(red: 0.985, green: 0.987, blue: 0.996)
    static let surface = Color.white
    static let softViolet = Color(red: 0.935, green: 0.920, blue: 1.000)
    static let stroke = Color.black.opacity(0.065)
    static let ink = Color(red: 0.045, green: 0.050, blue: 0.070)
    static let mutedInk = Color(red: 0.40, green: 0.40, blue: 0.47)
    static let safe = Color(red: 0.086, green: 0.643, blue: 0.290)
    static let caution = Color(red: 0.851, green: 0.467, blue: 0.024)
    static let danger = Color(red: 0.863, green: 0.149, blue: 0.149)

    static let route = Color(red: 0.00, green: 0.34, blue: 0.96)
    static let transition = Color(red: 1.0, green: 0.80, blue: 0.08)

    static let cardRadius: CGFloat = 32
    static let controlRadius: CGFloat = 24
    static let screenPadding: CGFloat = 22
    static let touchTarget: CGFloat = 64

    static func shadow(_ opacity: Double = 0.10) -> Color {
        Color(red: 0.025, green: 0.06, blue: 0.16).opacity(opacity)
    }

    static var brandCanvasGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.995, green: 0.996, blue: 1.0),
                Color(red: 0.965, green: 0.960, blue: 1.0),
                Color(red: 0.930, green: 0.922, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.25, green: 0.20, blue: 0.66),
                Color(red: 0.42, green: 0.33, blue: 0.94),
                Color(red: 0.58, green: 0.52, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AdminSurfaceModifier: ViewModifier {
    var radius: CGFloat = AdminTheme.cardRadius
    var shadowOpacity: Double = 0.08

    func body(content: Content) -> some View {
        content
            .background(AdminTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AdminTheme.stroke, lineWidth: 1)
            )
            .shadow(color: AdminTheme.shadow(shadowOpacity), radius: 16, y: 8)
    }
}

extension View {
    func adminSurface(radius: CGFloat = AdminTheme.cardRadius, shadowOpacity: Double = 0.08) -> some View {
        modifier(AdminSurfaceModifier(radius: radius, shadowOpacity: shadowOpacity))
    }
}

struct AdminPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.black))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: AdminTheme.touchTarget)
            .background(
                AdminTheme.heroGradient,
                in: RoundedRectangle(cornerRadius: AdminTheme.controlRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminTheme.controlRadius, style: .continuous)
                    .stroke(.white.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: AdminTheme.shadow(configuration.isPressed ? 0.08 : 0.16), radius: configuration.isPressed ? 8 : 16, y: configuration.isPressed ? 3 : 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct AdminSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(AdminTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                AdminTheme.surface.opacity(configuration.isPressed ? 0.84 : 1.0),
                in: RoundedRectangle(cornerRadius: AdminTheme.controlRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminTheme.controlRadius, style: .continuous)
                    .stroke(AdminTheme.stroke, lineWidth: 1)
            )
            .shadow(color: AdminTheme.shadow(configuration.isPressed ? 0.04 : 0.08), radius: configuration.isPressed ? 6 : 12, y: configuration.isPressed ? 2 : 6)
    }
}

struct AdminIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.black))
                .foregroundStyle(AdminTheme.ink)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.94), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.50), lineWidth: 1))
                .shadow(color: AdminTheme.shadow(0.11), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
