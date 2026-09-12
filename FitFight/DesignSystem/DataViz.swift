import SwiftUI

// Sections 08–10 of the kit: progress, comparison & ranking, history.

// MARK: - Progress

/// One bar, four contexts. Gold on a moss fill, ember or moss on a card.
/// The track is always the same 9% white.
struct FFProgressBar: View {
    let value: Double
    var height: CGFloat = 7
    var fill: Color?
    var track: Color?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track ?? theme.track)
                Capsule()
                    .fill(fill ?? theme.mossFill)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// Ring — when the number matters more than the trend. The kit draws 76 / 56 / 40pt
/// with stroke 9 / 7 / 5; the radius is a constant fraction of the box in all three.
struct FFRing<Label: View>: View {
    let value: Double
    var size: CGFloat = 76
    var lineWidth: CGFloat = 9
    var fill: Color?
    @ViewBuilder var label: Label

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let diameter = size * 0.786
        ZStack {
            Circle()
                .stroke(theme.track, lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(
                    fill ?? theme.mossFill,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: diameter, height: diameter)
            label
        }
        .frame(width: size, height: size)
    }
}

extension FFRing where Label == EmptyView {
    init(value: Double, size: CGFloat = 76, lineWidth: CGFloat = 9, fill: Color? = nil) {
        self.init(value: value, size: size, lineWidth: lineWidth, fill: fill) { EmptyView() }
    }
}

enum FFStreakState {
    case hit, miss, today, future
}

/// Seven day strip — hit · missed · today · not yet.
struct FFStreakStrip: View {
    let days: [(label: String, state: FFStreakState)]
    /// Square at phone widths: seven cells and six 8pt gaps across a 353pt column.
    var cellHeight: CGFloat = 44
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: cellHeight)
                    .background(
                        fill(day.state),
                        in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                    )
                    .overlay {
                        Text(day.label)
                            .ffType(.label)
                            .foregroundStyle(ink(day.state))
                    }
                    .overlay {
                        if let (color, width) = edge(day.state) {
                            RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                                .strokeBorder(color, lineWidth: width)
                        }
                    }
            }
        }
    }

    private func fill(_ state: FFStreakState) -> Color {
        switch state {
        case .hit: return theme.mossFill
        case .miss: return theme.chip
        case .today: return theme.mossFill.opacity(0.20)
        case .future: return .clear
        }
    }

    private func ink(_ state: FFStreakState) -> Color {
        switch state {
        case .hit: return theme.mossOn
        case .miss: return theme.textFaint
        case .today: return theme.mossText
        case .future: return theme.disabledText
        }
    }

    private func edge(_ state: FFStreakState) -> (Color, CGFloat)? {
        switch state {
        case .today: return (theme.mossEdge, 2)
        case .future: return (theme.track, 1)
        default: return nil
        }
    }
}

// MARK: - Comparison

/// VS block — the head-to-head. You are always the left side and always moss.
struct FFVSBlock: View {
    let you: (monogram: String, name: String, value: String, progress: Double)
    let them: (monogram: String, name: String, value: String, progress: Double)
    let delta: String
    var ahead: Bool = true
    let footnote: String
    let timeLeft: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                side(you, highlighted: true)
                VStack(spacing: 6) {
                    Text("VS")
                        .font(.ff(15, 800))
                        .tracking(15 * 0.04)
                        .foregroundStyle(theme.textFaint)
                    FFTag(delta, tone: ahead ? .moss : .ember)
                }
                .padding(.top, 22)
                side(them, highlighted: false)
            }
            VStack(spacing: 5) {
                FFProgressBar(value: you.progress, height: 9, fill: theme.mossFill)
                FFProgressBar(value: them.progress, height: 9, fill: theme.textFaint)
            }
            .padding(.top, 18)
            HStack {
                Text(footnote)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
                Text(timeLeft)
                    .ffType(.caption)
                    .fontWeight(.heavy)
                    .foregroundStyle(theme.gold)
            }
            .padding(.top, 14)
        }
        .padding(20)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }

    private func side(
        _ person: (monogram: String, name: String, value: String, progress: Double),
        highlighted: Bool
    ) -> some View {
        VStack(spacing: 9) {
            FFAvatar(monogram: person.monogram, size: 64, selected: highlighted)
            Text(person.name)
                .ffType(.label)
                .foregroundStyle(highlighted ? theme.text : theme.textSecondary)
            Text(person.value)
                .font(.ff(26, 800))
                .tracking(26 * -0.03)
                .foregroundStyle(highlighted ? theme.mossText : theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The losing variant — one line, ember, no comparison bars.
struct FFBehindRow: View {
    let monogram: String
    let title: String
    let detail: String
    let value: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            FFAvatar(monogram: monogram, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                Text(detail)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.ff(22, 800))
                .tracking(22 * -0.025)
                .foregroundStyle(theme.emberText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }
}

enum FFMove {
    case up, down, same

    var glyph: String {
        switch self {
        case .up: return "▲"
        case .down: return "▼"
        case .same: return "—"
        }
    }
}

/// Leaderboard row — you are always highlighted, rank 1 takes gold ink.
/// The row never names its own metric; the screen header does.
struct FFLeaderboardRow: View {
    let rank: Int
    let monogram: String
    let name: String
    let value: String
    var move: FFMove = .same
    var isYou: Bool = false
    var caption: String? = nil
    var captionUrgent: Bool = false
    var captionAt: ((Date) -> String)? = nil
    /// Nested rows step down to `field`; canvas rows keep `card`.
    var radius: CGFloat? = nil

    @Environment(\.ffTheme) private var theme

    private var corner: CGFloat { radius ?? theme.radius.card }

    var body: some View {
        HStack(spacing: 13) {
            Text("\(rank)")
                .ffType(.button)
                .foregroundStyle(rank == 1 ? theme.gold : theme.textTertiary)
                .frame(width: 22)
            FFAvatar(monogram: monogram, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if let captionAt {
                    // NOTE: Only the freshness line belongs in TimelineView. Wrapping
                    // scores in a 30s schedule leaves standings stale after a sync.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        captionText(captionAt(context.date))
                    }
                } else {
                    captionText(caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(move.glyph)
                .ffType(.micro)
                .fontWeight(.heavy)
                .foregroundStyle(moveInk)
            Text(value)
                .font(.ff(17, 800))
                .tracking(17 * -0.02)
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(
            isYou ? theme.mossWash : theme.card,
            in: RoundedRectangle(cornerRadius: corner, style: .continuous)
        )
        .ffBorder(isYou ? theme.mossEdge : theme.hairline, radius: corner)
    }

    @ViewBuilder
    private func captionText(_ caption: String?) -> some View {
        if let caption, !caption.isEmpty {
            Text(caption)
                .ffType(.micro)
                .foregroundStyle(captionUrgent ? theme.emberText : theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var moveInk: Color {
        switch move {
        case .up: return theme.mossText
        case .down: return theme.emberText
        case .same: return theme.textFaint
        }
    }
}

// MARK: - History

/// Sparkline — filled area plus a moss line. No axis; the number lives above it.
struct FFSparkline: View {
    let values: [Double]
    var height: CGFloat = 88

    @Environment(\.ffTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let points = points(in: geo.size)
            ZStack {
                area(points, height: geo.size.height)
                    .fill(theme.mossFill.opacity(0.20))
                line(points)
                    .stroke(
                        theme.mossText,
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .frame(height: height)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, 0.0001)
        // Inset by the stroke width so the round caps are not clipped at the edges.
        let top: CGFloat = 1.2
        let bottom = size.height - 1.2
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) / CGFloat(values.count - 1) * size.width,
                y: bottom - CGFloat((value - low) / span) * (bottom - top)
            )
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func area(_ points: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: height))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.closeSubpath()
        }
    }
}

enum FFBarTone {
    case today, active, past
}

/// Bar chart — today is gold, days inside the current fight are moss, earlier days
/// drop to 42% moss. No gridlines, no axis.
struct FFBarChart: View {
    let bars: [(label: String, value: Double, tone: FFBarTone)]
    var height: CGFloat = 96

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let peak = max(bars.map(\.value).max() ?? 1, 0.0001)
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                        .fill(fill(bar.tone))
                        .frame(height: max(bar.value / peak * height, 4))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack(spacing: 9) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    Text(bar.label)
                        .ffType(.micro)
                        .foregroundStyle(theme.textFaint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func fill(_ tone: FFBarTone) -> Color {
        switch tone {
        case .today: return theme.gold
        case .active: return theme.mossFill
        case .past: return theme.mossFill.opacity(0.42)
        }
    }
}
