import SwiftUI

struct TrashButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 12))
                .foregroundColor(isHovered ? Color.red.opacity(0.8) : Color.red.opacity(0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
