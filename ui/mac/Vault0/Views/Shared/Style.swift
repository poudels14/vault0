import SwiftUI

extension Color {
    /// Primary accent - refined blue
    static let vault0Accent = Color(red: 0.22, green: 0.47, blue: 0.96)

    // Semantic colors
    static let vault0Success = Color(red: 0.16, green: 0.65, blue: 0.45)
    static let vault0Warning = Color(red: 0.91, green: 0.61, blue: 0.15)
    static let vault0Error = Color(red: 0.86, green: 0.24, blue: 0.24)

    // Neutral palette for light mode
    static let vault0Background = Color.white
    static let vault0Surface = Color(red: 0.98, green: 0.98, blue: 0.99)
    static let vault0Border = Color(red: 0.91, green: 0.92, blue: 0.93)
    static let vault0BorderLight = Color(red: 0.95, green: 0.95, blue: 0.96)

    // Text colors
    static let vault0TextPrimary = Color(red: 0.12, green: 0.14, blue: 0.17)
    static let vault0TextSecondary = Color(red: 0.45, green: 0.48, blue: 0.52)
    static let vault0TextTertiary = Color(red: 0.62, green: 0.65, blue: 0.69)
}

struct CustomTextFieldStyle: TextFieldStyle {
    var isError: Bool = false
    @FocusState private var isFocused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.vault0Background)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isError ? Color.vault0Error :
                            isFocused ? Color.vault0Accent :
                            Color.vault0Border,
                        lineWidth: isFocused ? 1.5 : 1,
                    ),
            )
            .focused($isFocused)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDestructive ? Color.vault0Error : Color.vault0Accent),
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.4)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.vault0TextPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.vault0Surface),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.vault0Border, lineWidth: 1),
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1.0) : 0.4)
    }
}

struct IconButtonStyle: ButtonStyle {
    var color: Color = .vault0TextSecondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(color)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.vault0Surface : Color.clear),
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

extension View {
    func customTextField(isError: Bool = false) -> some View {
        textFieldStyle(CustomTextFieldStyle(isError: isError))
    }
}

struct StatusDot: View {
    enum Status {
        case active
        case warning
        case inactive

        var color: Color {
            switch self {
            case .active: .vault0Success
            case .warning: .vault0Warning
            case .inactive: .vault0TextTertiary
            }
        }
    }

    let status: Status
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}

struct Badge: View {
    enum Style {
        case warning
        case error
        case info
        case neutral

        var backgroundColor: Color {
            switch self {
            case .warning: Color.vault0Warning.opacity(0.12)
            case .error: Color.vault0Error.opacity(0.12)
            case .info: Color.vault0Accent.opacity(0.1)
            case .neutral: Color.vault0Surface
            }
        }

        var foregroundColor: Color {
            switch self {
            case .warning: Color(red: 0.7, green: 0.45, blue: 0.05)
            case .error: Color.vault0Error
            case .info: Color.vault0Accent
            case .neutral: Color.vault0TextSecondary
            }
        }
    }

    let text: String
    let style: Style
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(style.foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(style.backgroundColor),
        )
    }
}

struct ActionButton: View {
    let icon: String
    let action: () -> Void
    var color: Color = .vault0TextTertiary
    var hoverColor: Color = .vault0TextPrimary

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(isHovering ? hoverColor : color)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.vault0TextTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.vault0TextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.vault0Background),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.vault0Border, lineWidth: 1),
        )
    }
}

struct TableHeader: View {
    let columns: [(String, CGFloat?)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                Text(column.0.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.vault0TextTertiary)
                    .tracking(0.5)
                    .frame(width: column.1, alignment: .leading)
                if column.1 == nil {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.vault0Surface)
    }
}
