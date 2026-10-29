import SwiftUI

extension CGSize {
    static let menuBar = CGSize(width: 20, height: 16)
}

/// Borderless icon button with a tooltip that doubles as its accessibility label.
struct IconButton: View {
    let symbol: String
    let help: String
    var enabled = true
    var size = CGSize(width: 24, height: 22)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: size.width, height: size.height).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
