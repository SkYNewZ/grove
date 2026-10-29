import GroveKit
import SwiftUI

/// Small original glyphs for the tools that create worktrees: a starburst for Claude Code and a knot of
/// overlapping hexagons for Codex. Template-style: they take the foreground color (secondary).
struct OriginIcon: View {
    let origin: WorktreeOrigin

    var body: some View {
        Group {
            switch origin {
            case .claudeCode: BurstGlyph().stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            case .codex: KnotGlyph().stroke(style: StrokeStyle(lineWidth: 0.9, lineJoin: .round))
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 12, height: 12)
        .help(label)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch origin {
        case .claudeCode: "Créé par Claude Code"
        case .codex: "Créé par Codex"
        }
    }
}

/// Eight rounded rays, alternately long and short.
private nonisolated struct BurstGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 1
        var path = Path()
        for ray in 0..<8 {
            let angle = Double(ray) * .pi / 4
            let (dx, dy) = (cos(angle), sin(angle))
            let (inner, outer) = (radius * 0.2, radius * (ray.isMultiple(of: 2) ? 1 : 0.7))
            path.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
            path.addLine(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
        }
        return path
    }
}

/// Three hexagon outlines, each nudged toward one of three directions, overlapping into a knot.
private nonisolated struct KnotGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let (shift, radius) = (side * 0.125, side * 0.35)
        var path = Path()
        for lobe in 0..<3 {
            let direction = (Double(lobe) * 120 - 90) * .pi / 180
            let center = CGPoint(
                x: rect.midX + shift * cos(direction), y: rect.midY + shift * sin(direction))
            for corner in 0..<6 {
                let angle = (Double(corner) * 60 - 90) * .pi / 180
                let point = CGPoint(
                    x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                corner == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
        }
        return path
    }
}
