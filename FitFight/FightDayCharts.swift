import SwiftUI

enum FightDayChartKind: String, CaseIterable, Identifiable {
    case line
    case histogram
    case bars
    case pace
    case heat
    case track
    case oval
    case rings
    case stack
    case dots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return String(localized: "Line")
        case .histogram: return String(localized: "Histogram")
        case .bars: return String(localized: "Bars")
        case .pace: return String(localized: "Pace")
        case .heat: return String(localized: "Heat")
        case .track: return String(localized: "Track")
        case .oval: return String(localized: "Oval")
        case .rings: return String(localized: "Rings")
        case .stack: return String(localized: "Stack")
        case .dots: return String(localized: "Dots")
        }
    }
}

struct FightDayChartsView: View {
    let days: [FightDay]
    var initialKind: FightDayChartKind? = nil
    let formatScore: (Double) -> String

    @AppStorage("fight.dayChart.kind") private var kindRaw = FightDayChartKind.line.rawValue
    @State private var pickedKind: FightDayChartKind?
    @Environment(\.ffTheme) private var theme

    private var kind: FightDayChartKind {
        pickedKind ?? initialKind ?? FightDayChartKind(rawValue: kindRaw) ?? .line
    }

    var body: some View {
        let model = FightDayChartModel(days: days, theme: theme)
        VStack(alignment: .leading, spacing: 16) {
            FFFlow(spacing: 8) {
                ForEach(FightDayChartKind.allCases) { item in
                    badge(item)
                }
            }
            if !model.series.isEmpty {
                chart(model)
                if showsLegend {
                    legend(model)
                }
            }
        }
    }

    private func badge(_ item: FightDayChartKind) -> some View {
        let selected = item == kind
        return Button {
            pickedKind = item
            kindRaw = item.rawValue
        } label: {
            Text(item.title)
                .ffType(.micro)
                .fontWeight(.heavy)
                .foregroundStyle(selected ? theme.mossOn : theme.chipInk)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(selected ? theme.mossFill : theme.chip, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        selected ? theme.chipEdgeOn : theme.chipEdge,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func chart(_ model: FightDayChartModel) -> some View {
        switch kind {
        case .line:
            FightDayLineChart(model: model, cumulative: false)
        case .histogram:
            FightDayHistogramChart(model: model)
        case .bars:
            FightDayBarsChart(model: model, formatScore: formatScore)
        case .pace:
            FightDayLineChart(model: model, cumulative: true)
        case .heat:
            FightDayHeatChart(model: model)
        case .track:
            FightDayTrackChart(model: model, formatScore: formatScore)
        case .oval:
            FightDayOvalChart(model: model, formatScore: formatScore)
        case .rings:
            FightDayRingsChart(model: model, formatScore: formatScore)
        case .stack:
            FightDayStackChart(model: model)
        case .dots:
            FightDayDotsChart(model: model)
        }
    }

    private var showsLegend: Bool {
        switch kind {
        case .bars, .heat, .track, .rings:
            return false
        case .line, .histogram, .pace, .oval, .stack, .dots:
            return true
        }
    }

    private func legend(_ model: FightDayChartModel) -> some View {
        FFFlow(spacing: 10) {
            ForEach(model.series) { series in
                HStack(spacing: 6) {
                    Circle()
                        .fill(series.color)
                        .frame(width: 8, height: 8)
                    Text(series.person.isYou ? String(localized: "You") : series.person.name)
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct FightDayChartSeries: Identifiable {
    var person: Person
    var color: Color
    var daily: [Double]
    var cumulative: [Double]
    var total: Double

    var id: String { person.id }
}

private struct FightDayChartModel {
    var labels: [String]
    var series: [FightDayChartSeries]
    var peakDaily: Double
    var peakTotal: Double

    var peakCumulative: Double { peakTotal }
    var dayCount: Int { labels.count }

    init(days: [FightDay], theme: Theme) {
        labels = days.map(\.label)
        var totals: [String: Double] = [:]
        var people: [String: Person] = [:]
        for day in days {
            for score in day.scores {
                people[score.person.id] = score.person
                totals[score.person.id, default: 0] += score.value
            }
        }
        let ordered = people.values.sorted { lhs, rhs in
            let left = totals[lhs.id] ?? 0
            let right = totals[rhs.id] ?? 0
            if left != right { return left > right }
            return lhs.name < rhs.name
        }
        var otherIndex = 0
        series = ordered.map { person in
            let daily = days.map { day in
                day.scores.first { $0.person.id == person.id }?.value ?? 0
            }
            var running = 0.0
            let cumulative = daily.map { value -> Double in
                running += value
                return running
            }
            let color: Color
            if person.isYou {
                color = theme.mossFill
            } else {
                color = FightDayChartModel.otherColor(otherIndex, theme: theme)
                otherIndex += 1
            }
            return FightDayChartSeries(
                person: person,
                color: color,
                daily: daily,
                cumulative: cumulative,
                total: totals[person.id] ?? 0
            )
        }
        peakDaily = max(series.flatMap(\.daily).max() ?? 0, 0)
        peakTotal = max(series.map(\.total).max() ?? 0, 0)
    }

    private static func otherColor(_ index: Int, theme: Theme) -> Color {
        switch index {
        case 0: return theme.gold
        case 1: return theme.emberFill
        case 2: return theme.mossEdge
        case 3: return theme.emberText
        default: return theme.textSecondary
        }
    }

    func values(_ series: FightDayChartSeries, cumulative: Bool) -> [Double] {
        cumulative ? series.cumulative : series.daily
    }

    func peak(cumulative: Bool) -> Double {
        cumulative ? peakCumulative : peakDaily
    }
}

private func fightDayTickIndices(count: Int) -> [Int] {
    guard count > 0 else { return [] }
    if count <= 7 { return Array(0..<count) }
    var ticks = Set([0, count / 2, count - 1])
    if count >= 14 {
        ticks.insert(count / 4)
        ticks.insert((count * 3) / 4)
    }
    return ticks.sorted()
}

private func fightDayPlotY(value: Double, peak: Double, height: CGFloat) -> CGFloat {
    guard peak > 0 else { return height }
    return height - CGFloat(min(max(value / peak, 0), 1)) * height
}

private func fightDayPolyline(values: [Double], peak: Double, in size: CGSize) -> [CGPoint] {
    guard !values.isEmpty else { return [] }
    if values.count == 1 {
        let y = fightDayPlotY(value: values[0], peak: peak, height: size.height)
        return [CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y)]
    }
    return values.enumerated().map { index, value in
        CGPoint(
            x: CGFloat(index) / CGFloat(values.count - 1) * size.width,
            y: fightDayPlotY(value: value, peak: peak, height: size.height)
        )
    }
}

private struct FightDayLineChart: View {
    let model: FightDayChartModel
    var cumulative: Bool
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let peak = max(model.peak(cumulative: cumulative), 0.0001)
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    }
                    .stroke(theme.line, lineWidth: 1)
                    ForEach(model.series) { series in
                        let points = fightDayPolyline(
                            values: model.values(series, cumulative: cumulative),
                            peak: peak,
                            in: geo.size
                        )
                        if series.person.isYou, let first = points.first, let last = points.last {
                            Path { path in
                                path.move(to: CGPoint(x: first.x, y: geo.size.height))
                                for point in points { path.addLine(to: point) }
                                path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                                path.closeSubpath()
                            }
                            .fill(series.color.opacity(0.20))
                        }
                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                        }
                        .stroke(
                            series.color,
                            style: StrokeStyle(lineWidth: series.person.isYou ? 2.6 : 2.2, lineCap: .round, lineJoin: .round)
                        )
                        if let last = points.last {
                            Circle()
                                .fill(series.color)
                                .frame(width: 7, height: 7)
                                .position(last)
                        }
                    }
                }
            }
            .frame(height: 156)
            FightDayAxisLabels(labels: model.labels)
        }
    }
}

private struct FightDayHistogramChart: View {
    let model: FightDayChartModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let people = max(model.series.count, 1)
                let minGroup = CGFloat(people) * 9 + 10
                let gap: CGFloat = 8
                let natural = CGFloat(model.dayCount) * minGroup + CGFloat(max(model.dayCount - 1, 0)) * gap
                let contentWidth = max(geo.size.width, natural)
                let groupWidth = (contentWidth - CGFloat(max(model.dayCount - 1, 0)) * gap) / CGFloat(max(model.dayCount, 1))
                let barWidth = max((groupWidth - CGFloat(people - 1) * 2) / CGFloat(people), 3)
                ScrollView(.horizontal, showsIndicators: contentWidth > geo.size.width + 1) {
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(0..<model.dayCount, id: \.self) { day in
                            VStack(spacing: 8) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    ForEach(model.series) { series in
                                        let value = series.daily[day]
                                        let height = model.peakDaily == 0
                                            ? 4
                                            : max(CGFloat(value / model.peakDaily) * 140, value > 0 ? 4 : 3)
                                        RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                                            .fill(series.color)
                                            .frame(width: barWidth, height: height)
                                    }
                                }
                                .frame(height: 140, alignment: .bottom)
                                Text(model.labels[day])
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textFaint)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(width: groupWidth)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                }
            }
            .frame(height: 168)
        }
    }
}

private struct FightDayBarsChart: View {
    let model: FightDayChartModel
    let formatScore: (Double) -> String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.labels.enumerated()), id: \.offset) { day, label in
                if day > 0 { Color.clear.frame(height: 20) }
                FFEyebrow(label)
                    .padding(.bottom, 12)
                VStack(spacing: 10) {
                    ForEach(model.series) { series in
                        let value = series.daily[day]
                        HStack(spacing: 10) {
                            Text(series.person.isYou ? String(localized: "You") : series.person.name)
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: 56, alignment: .leading)
                            FFProgressBar(
                                value: model.peakDaily == 0 ? 0 : value / model.peakDaily,
                                fill: series.color
                            )
                            Text(formatScore(value))
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

private struct FightDayHeatChart: View {
    let model: FightDayChartModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let cell: CGFloat = 22
        ScrollView(.horizontal, showsIndicators: model.dayCount > 10) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.series) { series in
                    HStack(spacing: 4) {
                        FFAvatar(series.person, size: 22, selected: series.person.isYou)
                        ForEach(0..<model.dayCount, id: \.self) { day in
                            let value = series.daily[day]
                            let tone = model.peakDaily == 0 ? 0 : value / model.peakDaily
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(value == 0 ? theme.track : series.color.opacity(0.18 + 0.82 * tone))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }
}

private struct FightDayTrackChart: View {
    let model: FightDayChartModel
    let formatScore: (Double) -> String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                let inset: CGFloat = 18
                let usable = max(geo.size.width - inset * 2, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.track)
                    Capsule()
                        .fill(theme.gold)
                        .frame(width: 4, height: 22)
                        .offset(x: inset + usable - 2)
                    ForEach(Array(model.series.enumerated()), id: \.element.id) { index, series in
                        let progress = model.peakTotal == 0 ? 0 : series.total / model.peakTotal
                        FFAvatar(series.person, size: 28, selected: series.person.isYou)
                            .overlay { Circle().strokeBorder(series.color, lineWidth: 2) }
                            .offset(
                                x: inset + usable * progress - 14,
                                y: overlapOffset(index: index, progress: progress)
                            )
                            .zIndex(progress)
                    }
                }
            }
            .frame(height: 52)
            HStack {
                Text(String(localized: "Start"))
                Spacer(minLength: 0)
                Text(String(localized: "Lead"))
            }
            .ffType(.micro)
            .foregroundStyle(theme.textFaint)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.series) { series in
                    HStack {
                        Circle().fill(series.color).frame(width: 7, height: 7)
                        Text(series.person.isYou ? String(localized: "You") : series.person.name)
                            .ffType(.caption)
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(formatScore(series.total))
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }

    private func overlapOffset(index: Int, progress: Double) -> CGFloat {
        let close = model.series.enumerated().filter { other in
            other.offset != index
                && abs((model.peakTotal == 0 ? 0 : other.element.total / model.peakTotal) - progress) < 0.08
        }
        guard !close.isEmpty else { return 0 }
        return index.isMultiple(of: 2) ? -11 : 11
    }
}

private struct FightDayOvalChart: View {
    let model: FightDayChartModel
    let formatScore: (Double) -> String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let rect = geo.frame(in: .local).insetBy(dx: 22, dy: 22)
            let corner = theme.radius.shell
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(theme.track, lineWidth: 14)
                    .padding(22)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
                    .padding(22)
                Path { path in
                    let start = pointOnCircuit(progress: 0, in: rect, corner: corner)
                    path.move(to: CGPoint(x: start.x, y: start.y - 12))
                    path.addLine(to: CGPoint(x: start.x, y: start.y + 12))
                }
                .stroke(theme.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                VStack(spacing: 4) {
                    if let leader = model.series.first {
                        Text(leader.person.isYou ? String(localized: "You") : leader.person.name)
                            .ffType(.label)
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        Text(formatScore(leader.total))
                            .font(.ff(22, 800))
                            .foregroundStyle(leader.color)
                    }
                }
                ForEach(model.series) { series in
                    let progress = model.peakTotal == 0
                        ? 0.02
                        : 0.04 + 0.90 * (series.total / model.peakTotal)
                    let point = pointOnCircuit(progress: progress, in: rect, corner: corner)
                    FFAvatar(series.person, size: 30, selected: series.person.isYou)
                        .overlay { Circle().strokeBorder(series.color, lineWidth: 2) }
                        .position(point)
                        .zIndex(series.total)
                }
            }
        }
        .frame(height: 220)
    }
}

private struct FightDayRingsChart: View {
    let model: FightDayChartModel
    let formatScore: (Double) -> String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFFlow(spacing: 16) {
            ForEach(model.series) { series in
                VStack(spacing: 8) {
                    FFRing(
                        value: model.peakTotal == 0 ? 0 : series.total / model.peakTotal,
                        size: 76,
                        lineWidth: 8,
                        fill: series.color
                    ) {
                        FFAvatar(series.person, size: 32, selected: series.person.isYou)
                    }
                    Text(series.person.isYou ? String(localized: "You") : series.person.name)
                        .ffType(.micro)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(formatScore(series.total))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(minWidth: 88)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct FightDayStackChart: View {
    let model: FightDayChartModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let peaks = (0..<model.dayCount).map { day in
            model.series.reduce(0) { $0 + $1.daily[day] }
        }
        let peak = max(peaks.max() ?? 0, 0.0001)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let minGroup: CGFloat = 18
                let gap: CGFloat = 6
                let natural = CGFloat(model.dayCount) * minGroup + CGFloat(max(model.dayCount - 1, 0)) * gap
                let contentWidth = max(geo.size.width, natural)
                let groupWidth = (contentWidth - CGFloat(max(model.dayCount - 1, 0)) * gap) / CGFloat(max(model.dayCount, 1))
                ScrollView(.horizontal, showsIndicators: contentWidth > geo.size.width + 1) {
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(0..<model.dayCount, id: \.self) { day in
                            VStack(spacing: 8) {
                                VStack(spacing: 1) {
                                    Spacer(minLength: 0)
                                    ForEach(Array(model.series.reversed())) { series in
                                        let value = series.daily[day]
                                        if value > 0 {
                                            Rectangle()
                                                .fill(series.color)
                                                .frame(height: max(CGFloat(value / peak) * 140, 3))
                                        }
                                    }
                                }
                                .frame(width: groupWidth, height: 140, alignment: .bottom)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous))
                                Text(model.labels[day])
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textFaint)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(width: groupWidth)
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                }
            }
            .frame(height: 168)
        }
    }
}

private struct FightDayDotsChart: View {
    let model: FightDayChartModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let people = max(model.series.count, 1)
            let minGroup = CGFloat(people) * 12 + 8
            let gap: CGFloat = 10
            let natural = CGFloat(model.dayCount) * minGroup + CGFloat(max(model.dayCount - 1, 0)) * gap
            let contentWidth = max(geo.size.width, natural)
            let groupWidth = (contentWidth - CGFloat(max(model.dayCount - 1, 0)) * gap) / CGFloat(max(model.dayCount, 1))
            ScrollView(.horizontal, showsIndicators: contentWidth > geo.size.width + 1) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(0..<model.dayCount, id: \.self) { day in
                        VStack(spacing: 8) {
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(model.series) { series in
                                    let value = series.daily[day]
                                    let height = model.peakDaily == 0
                                        ? 4
                                        : max(CGFloat(value / model.peakDaily) * 140, value > 0 ? 8 : 4)
                                    ZStack(alignment: .bottom) {
                                        Capsule()
                                            .fill(series.color.opacity(0.35))
                                            .frame(width: 2, height: height)
                                        Circle()
                                            .fill(series.color)
                                            .frame(width: 9, height: 9)
                                    }
                                    .frame(height: 140, alignment: .bottom)
                                }
                            }
                            .frame(height: 140, alignment: .bottom)
                            Text(model.labels[day])
                                .ffType(.micro)
                                .foregroundStyle(theme.textFaint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: groupWidth)
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
            }
        }
        .frame(height: 168)
    }
}

private struct FightDayAxisLabels: View {
    let labels: [String]
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let ticks = Set(fightDayTickIndices(count: labels.count))
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(ticks.contains(index) ? label : "")
                    .ffType(.micro)
                    .foregroundStyle(theme.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private func pointOnCircuit(progress: CGFloat, in rect: CGRect, corner: CGFloat) -> CGPoint {
    let radius = min(corner, rect.width / 2, rect.height / 2)
    let left = rect.minX + radius
    let right = rect.maxX - radius
    let top = rect.minY + radius
    let bottom = rect.maxY - radius
    let horiz = max(right - left, 0)
    let vert = max(bottom - top, 0)
    let arc = .pi / 2 * radius
    let half = horiz / 2
    let lengths = [half, arc, vert, arc, horiz, arc, vert, arc, half]
    let total = max(lengths.reduce(0, +), 0.0001)
    var distance = min(max(progress, 0), 0.999) * total

    func take(_ length: CGFloat, _ point: (CGFloat) -> CGPoint) -> CGPoint? {
        if distance <= length {
            return point(length == 0 ? 0 : distance / length)
        }
        distance -= length
        return nil
    }

    if let point = take(half, { t in CGPoint(x: rect.midX + half * t, y: rect.maxY) }) {
        return point
    }
    if let point = take(arc, { t in
        let angle = .pi / 2 * (1 - t)
        return CGPoint(x: right + cos(angle) * radius, y: bottom + sin(angle) * radius)
    }) {
        return point
    }
    if let point = take(vert, { t in CGPoint(x: rect.maxX, y: bottom - vert * t) }) {
        return point
    }
    if let point = take(arc, { t in
        let angle = -.pi / 2 * t
        return CGPoint(x: right + cos(angle) * radius, y: top + sin(angle) * radius)
    }) {
        return point
    }
    if let point = take(horiz, { t in CGPoint(x: right - horiz * t, y: rect.minY) }) {
        return point
    }
    if let point = take(arc, { t in
        let angle = -.pi / 2 - .pi / 2 * t
        return CGPoint(x: left + cos(angle) * radius, y: top + sin(angle) * radius)
    }) {
        return point
    }
    if let point = take(vert, { t in CGPoint(x: rect.minX, y: top + vert * t) }) {
        return point
    }
    if let point = take(arc, { t in
        let angle = -.pi - .pi / 2 * t
        return CGPoint(x: left + cos(angle) * radius, y: bottom + sin(angle) * radius)
    }) {
        return point
    }
    return CGPoint(x: left + half * min(max(distance / max(half, 0.0001), 0), 1), y: rect.maxY)
}
