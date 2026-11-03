import SwiftUI

struct AuthBackdrop: View {
    var body: some View {
        ZStack {
            Palette.background
            RadialGradient(colors: [Palette.violet.opacity(0.22), .clear], center: .topTrailing, startRadius: 10, endRadius: 480)
            RadialGradient(colors: [Palette.acid.opacity(0.1), .clear], center: .bottomLeading, startRadius: 0, endRadius: 420)
            LinearGradient(colors: [.white.opacity(0.025), .clear, .black.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct AuthGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.15)))
        } else {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
            } else { fallback(content) }
#else
            fallback(content)
#endif
        }
    }
    private func fallback(_ content: Content) -> some View {
        content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}
extension View { func authGlass(radius: CGFloat = 24) -> some View { modifier(AuthGlass(radius: radius)) } }

struct AuthActionButton: View {
    let title: String
    var busy = false
    var enabled = true
    let action: () -> Void
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Button(action: action) { label }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
                .tint(Palette.acid).foregroundStyle(.black).disabled(!enabled || busy)
                .accessibilityIdentifier("auth.primary")
        } else { fallback }
#else
        fallback
#endif
    }
    private var fallback: some View {
        Button(action: action) { label.padding(.vertical, 5) }.buttonStyle(AuthPrimaryStyle())
            .disabled(!enabled || busy).accessibilityIdentifier("auth.primary")
    }
    private var label: some View {
        HStack(spacing: 10) {
            if busy { ProgressView().tint(.black).accessibilityLabel("Working") }
            Text(title).font(.headline)
            if !busy { Image(systemName: "arrow.right").font(.subheadline.weight(.semibold)) }
        }.frame(maxWidth: .infinity).frame(minHeight: 28)
    }
}
private struct AuthPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 22).padding(.vertical, 12)
            .foregroundStyle(.black).background(Palette.acid.opacity(enabled ? 1 : 0.35), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
struct AuthRoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.body.weight(.medium)).frame(width: 46, height: 46).contentShape(Circle()) }
            .buttonStyle(.plain).foregroundStyle(.white).authGlass(radius: 23).accessibilityLabel(label)
    }
}
struct AuthField<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) { self.title = title; self.symbol = symbol; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 13) {
                Image(systemName: symbol).foregroundStyle(Palette.acid.opacity(0.9)).frame(width: 20).accessibilityHidden(true)
                content.font(.body).tint(Palette.acid)
            }.padding(.horizontal, 18).frame(minHeight: 62)
                .background(reduceTransparency ? Color(white: 0.13) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.1)))
        }
    }
}
struct AuthTicketArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false
    var body: some View {
        ZStack {
            Circle().fill(Palette.acid.opacity(0.1)).frame(width: 240, height: 240).blur(radius: 45)
            RoundedRectangle(cornerRadius: 30).fill(Palette.violet.opacity(0.16)).frame(width: 230, height: 270)
                .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.1))).rotationEffect(.degrees(-13)).offset(x: -22, y: 4)
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("pullup↗").font(.title3.weight(.black)); Spacer(); Image(systemName: "sparkle").foregroundStyle(Palette.acid) }
                Spacer(minLength: 16)
                Text("GOOD\nNIGHTS\nAHEAD.").font(.system(size: 35, weight: .black, design: .rounded)).tracking(-1)
                Spacer(minLength: 16)
                HStack { Text("YOUR WAY IN").font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(1.6); Spacer(); Image(systemName: "arrow.up.right") }.foregroundStyle(Palette.acid)
            }.padding(25).frame(width: 225, height: 265).authGlass(radius: 30)
                .rotationEffect(.degrees(floating && !reduceMotion ? 8 : 4)).offset(y: floating && !reduceMotion ? -6 : 3)
                .shadow(color: .black.opacity(0.3), radius: 25, y: 24)
        }.frame(height: 310).frame(maxWidth: .infinity).accessibilityHidden(true)
            .onAppear { if !reduceMotion && !AuthenticationFactory.quietUITests { withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { floating = true } } }
    }
}
