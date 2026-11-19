import SwiftUI
import AppKit

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

/// Design language of lurohome.de: warm paper, Terrakotta only as accent, hairlines instead of shadows.
enum Theme {
    static let bg = Color(light: 0xf5f2ed, dark: 0x1d1b1a)
    static let surface = Color(light: 0xfffdf9, dark: 0x282523)
    static let ink = Color(light: 0x242321, dark: 0xf6f0e8)
    static let muted = Color(light: 0x77736c, dark: 0xb8aea4)
    static let line = Color(light: 0xd9d3ca, dark: 0x49413b)
    static let accent = Color(light: 0xc75d3b, dark: 0xe47a55)
    static let accentStrong = Color(light: 0xa7472c, dark: 0xf09a76)
    static let soft = Color(light: 0xeee8df, dark: 0x352e2a)

    static let radius: CGFloat = 2

    static func serif(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Regular", size: size) }
    static func serifItalic(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Italic", size: size) }
    static func text(_ size: CGFloat) -> Font { .custom("Inter-Regular", size: size) }
    static func textMedium(_ size: CGFloat) -> Font { .custom("Inter-Medium", size: size) }
    static func label(_ size: CGFloat) -> Font { .custom("Archivo-SemiBold", size: size) }
    static func mono(_ size: CGFloat) -> Font { .custom("GeistMono-Regular", size: size) }
}

/// Small caps line in Geist Mono, as on the website ("Eyebrow").
struct Eyebrow: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased()).font(Theme.mono(11)).tracking(1.6).foregroundColor(Theme.muted)
    }
}

/// Heading with a Terrakotta italic accent word: "Rotor" + "wacht".
struct AccentTitle: View {
    let plain: String
    let accent: String
    let size: CGFloat
    var body: some View {
        (Text(plain).font(Theme.serif(size)).foregroundColor(Theme.ink)
         + Text(accent).font(Theme.serifItalic(size)).foregroundColor(Theme.accent))
    }
}

/// Wordmark "luro" as footer: `lu` upright in ink, `ro` italic in Terrakotta, links to lurohome.de.
struct Wordmark: View {
    var size: CGFloat = 22
    var body: some View {
        Link(destination: URL(string: "https://lurohome.de")!) {
            (Text("lu").font(Theme.serif(size)).foregroundColor(Theme.ink)
             + Text("ro").font(Theme.serifItalic(size)).foregroundColor(Theme.accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("luro · lurohome.de")
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(14))
            .foregroundColor(Color(light: 0xfffdf9, dark: 0x1d1b1a))
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(configuration.isPressed ? Theme.accentStrong : Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(14))
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(configuration.isPressed ? Theme.soft : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
    }
}
