import GroveKit
import SwiftUI

/// Small original glyphs for the two forges (SF Symbols has no brand marks): a cat-eared disc for GitHub and
/// a geometric fox head for GitLab. Template-style: they take the foreground color.
struct ForgeIcon: View {
    let forge: Forge

    var body: some View {
        Group {
            switch forge {
            case .github: GitHubGlyph().fill()
            case .gitlab: GitLabGlyph().fill()
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

private nonisolated struct GitHubGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(
            ellipseIn: rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.12).offsetBy(
                dx: 0, dy: rect.height * 0.06))
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.14, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.04))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.2))
        path.closeSubpath()
        path.move(to: CGPoint(x: w * 0.86, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.04))
        path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.2))
        path.closeSubpath()
        return path
    }
}

private nonisolated struct GitLabGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [
            (0.5, 0.97), (0.03, 0.57), (0.19, 0.06), (0.35, 0.46), (0.65, 0.46), (0.81, 0.06), (0.97, 0.57),
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + rect.width * point.0, y: rect.minY + rect.height * point.1)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }
}

/// The "open on the web" button: the forge glyph, with a badge for the state of the PR/MR it opens (none for
/// the plain repo page).
struct WebButton: View {
    let forge: Forge
    let url: URL
    var state: PullRequestState?
    var size = CGSize(width: 24, height: 22)
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.openWeb(url)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ForgeIcon(forge: forge)
                if let state {
                    Image(systemName: badgeSymbol(state))
                        .font(.system(size: 8, weight: .bold))
                        .padding(1.5)
                        .background(badgeFill(state), in: Circle())
                        .foregroundStyle(.white)
                        .offset(x: 4, y: 3)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private func badgeSymbol(_ state: PullRequestState) -> String {
        switch state {
        case .open: "arrow.triangle.pull"
        case .merged: "checkmark"
        case .closed: "xmark"
        }
    }

    private func badgeFill(_ state: PullRequestState) -> AnyShapeStyle {
        switch state {
        case .open: AnyShapeStyle(.tint)
        case .merged: AnyShapeStyle(Color.purple)
        case .closed: AnyShapeStyle(Color.red)
        }
    }

    private var helpText: String {
        let site = forge == .github ? "GitHub" : "GitLab"
        guard let state else { return "Ouvrir le dépôt sur \(site)" }
        let kind = forge == .github ? "la PR" : "la MR"
        let number = requestNumber(url, on: forge).map { " \($0)" } ?? ""
        let suffix =
            switch state {
            case .open: ""
            case .merged: " (mergée)"
            case .closed: " (fermée)"
            }
        return "Ouvrir \(kind)\(number)\(suffix) sur \(site)"
    }
}
