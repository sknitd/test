import SwiftUI

/// Everything a node needs to draw itself and to talk back to its host. The same renderer serves live
/// overlay windows, the builder preview and the WidgetKit extension; the host decides what is interactive
/// by supplying (or withholding) the closures below.
struct RenderEnvironment {
    /// Data the templates resolve against: `state`, `settings`, `sources` and one key per data source id.
    var context: JSONValue = .object([:])
    var tint: Color = .accentColor
    /// Content size the layout was designed for (used by canvas constraints).
    var designSize = WidgetSize(320, 200)
    /// False in the builder canvas and for locked previews: controls draw but do nothing.
    var isInteractive = true
    /// True inside the WidgetKit extension, where only App Intent buttons may be interactive.
    var isWidgetKit = false
    /// The date a WidgetKit timeline entry represents (live views use the wall clock instead).
    var entryDate: Date?
    /// Layout produced by the widget's script, shown by `script` nodes.
    var scriptNode: WidgetNode?
    var scriptMessage: String?
    /// Hosts from which `image` nodes may load remote pictures.
    var imageHosts: [String] = []

    var perform: (WidgetAction) -> Void = { _ in }
    var setState: (String, JSONValue) -> Void = { _, _ in }
    /// Reads the clipboard after a permission check; nil when not permitted.
    var readClipboard: () -> String? = { nil }
    var notify: (String, String) -> Void = { _, _ in }
    /// Supplied by the app to embed a WKWebView; absent in WidgetKit.
    var webView: ((URL) -> AnyView)?
    /// Supplied by the WidgetKit extension to wrap a label in `Button(intent:)`.
    var intentButton: ((WidgetAction, AnyView) -> AnyView)?

    // MARK: Resolution helpers

    var now: Date { entryDate ?? Date() }

    func text(_ node: WidgetNode, _ key: String, default fallback: String = "") -> String {
        guard let value = node.props[key] else { return fallback }
        if case .string(let s) = value { return TemplateRenderer.render(s, context: context, now: now) }
        return value.displayString
    }

    func value(_ node: WidgetNode, _ key: String) -> JSONValue? {
        node.props[key].map { TemplateRenderer.resolve($0, context: context, now: now) }
    }

    func number(_ node: WidgetNode, _ key: String) -> Double? {
        guard let v = value(node, key), !v.isNull else { return nil }
        if case .string(let s) = v, s.isEmpty { return nil }
        return v.doubleValue
    }

    func bool(_ node: WidgetNode, _ key: String) -> Bool? { value(node, key)?.boolValue }

    func state(_ key: String) -> JSONValue? { context.path("state.\(key)") }

    func isVisible(_ node: WidgetNode) -> Bool {
        guard let rule = node.props["visibleWhen"]?.objectValue, let path = rule["path"]?.stringValue else { return true }
        let op = Condition.Operator(rawValue: rule["op"]?.stringValue ?? "==") ?? .equals
        return Condition(path, op, rule["value"] ?? .null).evaluate(in: context)
    }

    /// An action with its string fields template-resolved (e.g. a shortcut name taken from settings).
    func resolved(_ action: WidgetAction) -> WidgetAction {
        func r(_ s: String) -> String { TemplateRenderer.render(s, context: context, now: now) }
        switch action {
        case .openURL(let url): return .openURL(r(url))
        case .runShortcut(let name): return .runShortcut(r(name))
        case .launchApp(let id): return .launchApp(r(id))
        case .copy(let text): return .copy(r(text))
        case .setState(let key, let value): return .setState(key: key, value: TemplateRenderer.resolve(value, context: context, now: now))
        default: return action
        }
    }

    /// A button that works in every host: a plain action in the app, an App Intent in WidgetKit.
    func button<Label: View>(_ action: WidgetAction?, @ViewBuilder label: () -> Label) -> AnyView {
        let content = label()
        guard let action, isInteractive else { return AnyView(content) }
        let final = resolved(action)
        if isWidgetKit {
            if let intentButton { return intentButton(final, AnyView(content)) }
            return AnyView(content)
        }
        let run = perform
        return AnyView(Button(action: { run(final) }, label: { content }).buttonStyle(.plain))
    }
}

enum Theme {
    static func color(_ name: String?, tint: Color = .accentColor, fallback: Color = .primary) -> Color {
        guard let raw = name?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return fallback }
        switch raw.lowercased() {
        case "primary": return .primary
        case "secondary": return .secondary
        case "tertiary": return Color.secondary.opacity(0.6)
        case "accent", "tint": return tint
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey": return .gray
        case "white": return .white
        case "black": return .black
        case "clear": return .clear
        default: return hex(raw) ?? fallback
        }
    }

    /// #RGB, #RRGGBB or #RRGGBBAA.
    static func hex(_ text: String) -> Color? {
        var s = text.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    static func weight(_ name: String?) -> Font.Weight {
        switch name?.lowercased() {
        case "ultralight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .regular
        }
    }

    static func design(_ name: String?) -> Font.Design {
        switch name?.lowercased() {
        case "rounded": return .rounded
        case "monospaced", "mono": return .monospaced
        case "serif": return .serif
        default: return .default
        }
    }

    static func font(_ node: WidgetNode, defaultSize: Double = 13) -> Font {
        .system(size: CGFloat(node.number("fontSize") ?? defaultSize), weight: weight(node.string("fontWeight")), design: design(node.string("fontDesign")))
    }

    static func alignment(_ name: String?) -> HorizontalAlignment {
        switch name?.lowercased() {
        case "center": return .center
        case "trailing", "right": return .trailing
        default: return .leading
        }
    }

    static func verticalAlignment(_ name: String?) -> VerticalAlignment {
        switch name?.lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        case "firstTextBaseline", "baseline": return .firstTextBaseline
        default: return .center
        }
    }

    static func frameAlignment(_ name: String?) -> Alignment {
        switch name?.lowercased() {
        case "center": return .center
        case "trailing", "right": return .trailing
        default: return .leading
        }
    }

    static func textAlignment(_ name: String?) -> TextAlignment {
        switch name?.lowercased() {
        case "center": return .center
        case "trailing", "right": return .trailing
        default: return .leading
        }
    }

    /// SF Symbol for a WMO weather interpretation code (the scheme Open-Meteo uses).
    static func weatherSymbol(code: Int) -> (symbol: String, text: String) {
        switch code {
        case 0: return ("sun.max.fill", "Clear")
        case 1: return ("sun.max", "Mostly clear")
        case 2: return ("cloud.sun.fill", "Partly cloudy")
        case 3: return ("cloud.fill", "Overcast")
        case 45, 48: return ("cloud.fog.fill", "Fog")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 65, 66, 67: return ("cloud.rain.fill", "Rain")
        case 71, 73, 75, 77: return ("cloud.snow.fill", "Snow")
        case 80, 81, 82: return ("cloud.heavyrain.fill", "Showers")
        case 85, 86: return ("cloud.snow.fill", "Snow showers")
        case 95, 96, 99: return ("cloud.bolt.rain.fill", "Thunderstorm")
        default: return ("cloud", "–")
        }
    }
}

/// Applies the decoration props every component understands: padding, background, corner radius, border,
/// shadow, opacity and a simple entrance/attention animation.
struct NodeDecoration: ViewModifier {
    let node: WidgetNode
    let tint: Color
    @State private var pulse = false

    func body(content: Content) -> some View {
        let radius = CGFloat(node.number("cornerRadius") ?? 0)
        let borderWidth = CGFloat(node.number("borderWidth") ?? 0)
        let animation = node.string("animation") ?? "none"
        return content
            .padding(CGFloat(node.number("padding") ?? 0))
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.color(node.string("background"), tint: tint, fallback: .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.color(node.string("borderColor"), tint: tint, fallback: .clear), lineWidth: borderWidth)
            )
            .shadow(color: .black.opacity(node.number("shadowRadius") ?? 0 > 0 ? 0.25 : 0), radius: CGFloat(node.number("shadowRadius") ?? 0), y: 1)
            .opacity(node.number("opacity") ?? 1)
            .opacity(animation == "pulse" && pulse ? 0.45 : 1)
            .scaleEffect(animation == "bounce" && pulse ? 1.06 : 1)
            .onAppear {
                guard animation == "pulse" || animation == "bounce" else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
            .transition(animation == "fade" ? .opacity : .identity)
    }
}
