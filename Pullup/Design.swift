import SwiftUI

enum Palette {
    static let background = Color(red: 10/255, green: 10/255, blue: 11/255)
    static let acid = Color(red: 184/255, green: 1, blue: 61/255)
    static let violet = Color(red: 168/255, green: 85/255, blue: 247/255)
}
struct Surface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.09)))
    }
}
extension View { func surface() -> some View { modifier(Surface()) } }
struct PrimaryButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(.black).background(Palette.acid, in: RoundedRectangle(cornerRadius: 19))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
struct Artwork: View {
    let url: String?
    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: url.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [Palette.violet.opacity(0.65), Palette.background, Palette.acid.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }.accessibilityHidden(true)
    }
}
struct Notice: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(Palette.acid)
            Text(title).font(.title2.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 32).surface()
    }
}
struct ErrorBanner: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle").font(.subheadline)
            .foregroundStyle(.white).padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 16)).accessibilityAddTraits(.updatesFrequently)
    }
}
