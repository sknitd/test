import SwiftUI
import AppKit

// Shared building blocks for every MagicForge screen. Semantic colours only, so everything
// works in light and dark appearance.

public enum MFStatusStyle: Sendable {
    case good, warning, bad, neutral, info

    public var color: Color {
        switch self {
        case .good: return Color.green
        case .warning: return Color.orange
        case .bad: return Color.red
        case .neutral: return Color.secondary
        case .info: return Color.blue
        }
    }
}

/// Title + optional subtitle with trailing controls. `MFPage` uses it; screens that cannot live
/// inside a scroll view (lists, forms, split layouts) can use it directly.
public struct MFPageHeader<Toolbar: View>: View {
    private let title: String
    private let subtitle: String?
    private let toolbar: Toolbar

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder toolbar: () -> Toolbar) {
        self.title = title
        self.subtitle = subtitle
        self.toolbar = toolbar()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            toolbar
        }
    }
}

public extension MFPageHeader where Toolbar == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle, toolbar: { EmptyView() })
    }
}

/// Scrolling page with a header.
public struct MFPage<Toolbar: View, Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let toolbar: Toolbar
    private let content: Content

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder toolbar: () -> Toolbar,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.toolbar = toolbar()
        self.content = content()
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                MFPageHeader(title, subtitle: subtitle, toolbar: { toolbar })
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

public extension MFPage where Toolbar == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, toolbar: { EmptyView() }, content: content)
    }
}

/// Rounded container with an optional headline.
public struct MFCard<Content: View>: View {
    private let title: String?
    private let systemImage: String?
    private let content: Content

    public init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder private var header: some View {
        if let title {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

/// Small coloured capsule such as "Granted" or "Unavailable".
public struct MFStatusBadge: View {
    private let text: String
    private let style: MFStatusStyle

    public init(_ text: String, style: MFStatusStyle) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(style.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(style.color.opacity(0.16)))
        .fixedSize()
    }
}

public struct MFEmptyState: View {
    private let systemImage: String
    private let title: String
    private let message: String

    public init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}

public struct MFKeyValueRow: View {
    private let key: String
    private let value: String

    public init(_ key: String, value: String) {
        self.key = key
        self.value = value
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

public extension Color {
    /// Parses "#RGB", "#RRGGBB" or "#RRGGBBAA" (the leading "#" is optional). Nil when malformed.
    init?(hex: String) {
        var text: String = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard !text.isEmpty, text.allSatisfy({ $0.isHexDigit }) else { return nil }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        if text.count == 6 {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        } else {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
