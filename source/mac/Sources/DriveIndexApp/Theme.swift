import SwiftUI

/// Toned-down terminal theme: dark, with green reserved for "connected"
/// status and accents. `dim`/`faint` are neutral grays for secondary text
/// and hairlines.
enum Pip {
    static let green    = Color(red: 0.30, green: 0.90, blue: 0.50)
    static let amber    = Color(red: 1.00, green: 0.75, blue: 0.25)   // nearly-full drives
    static let text     = Color.white.opacity(0.88)
    static let dim      = Color.white.opacity(0.55)
    static let faint    = Color.white.opacity(0.14)
    static let bg       = Color(red: 0.075, green: 0.085, blue: 0.078)
    static let bgRaised = Color(red: 0.110, green: 0.125, blue: 0.115)
}

enum Fmt {
    static let relative = RelativeDateTimeFormatter()
}

extension View {
    /// Soft green glow — used sparingly (status dots).
    func pipGlow(_ strength: Double = 0.45) -> some View {
        shadow(color: Pip.green.opacity(strength), radius: 3)
    }
}

/// Quiet bordered button with a green tint.
struct PipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(configuration.isPressed ? Color.black : Pip.green)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed ? Pip.green : Pip.green.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Pip.green.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

/// Steady status dot with a soft glow.
struct StatusDot: View {
    var body: some View {
        Circle()
            .fill(Pip.green)
            .frame(width: 7, height: 7)
            .pipGlow()
    }
}

/// Very faint scanlines — a hint of CRT, nothing more.
struct CRTOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                         with: .color(.black.opacity(0.055)))
                y += 4
            }
        }
        .allowsHitTesting(false)
    }
}

/// Centered placeholder text.
struct PipEmpty: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Pip.text)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Pip.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
