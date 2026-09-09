import SwiftUI
import UIKit

// Sections 02–05 of the kit: type, buttons, badges, avatars, cards.
// Geometry is lifted from docs/design/source/kit/FitFight Design System.dc.html.

// MARK: - Type

private struct FFTypeModifier: ViewModifier {
    let role: TypeRole
    @Environment(\.ffTheme) private var theme

    func body(content: Content) -> some View {
        content
            .font(theme.font(role))
            .tracking(theme.tracking(role))
            .textCase(theme.isUppercase(role) ? .uppercase : nil)
    }
}

extension View {
    func ffType(_ role: TypeRole) -> some View { modifier(FFTypeModifier(role: role)) }
}

extension View {
    /// The kit's card border — a 1px hairline is the whole depth system, there are no shadows.
    func ffBorder(_ color: Color, radius: CGFloat, width: CGFloat = 1) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width)
        }
    }
}

enum FFHaptics {
    private static let buttonImpact: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()

    static func button() {
        buttonImpact.impactOccurred(intensity: 0.72)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Same as `.plain`, with a tap tick. Use on controls that should not scale.
struct FFHapticPlainStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { FFHaptics.button() }
            }
    }
}

struct FFPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { FFHaptics.button() }
            }
    }
}

// MARK: - Section header

/// "01 · Colour" — moss eyebrow, then a rule to the right edge.
struct FFSectionHeader: View {
    let title: String
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .ffType(.sectionEyebrow)
                .foregroundStyle(theme.mossText)
                .lineLimit(1)
                // Never wrap (the rule takes the rest of the row) and never overflow —
                // "11 · Navigation, feed & pickers" is wider than a phone at full size.
                .minimumScaleFactor(0.7)
                // The rule is greedy; without this the title only gets a share of the
                // row and ellipsizes instead of taking the width it needs.
                .layoutPriority(1)
            Rectangle()
                .fill(theme.track)
                .frame(height: 1)
        }
    }
}

/// Header plus the views that belong to it. Uses the same gap `FFScreen` uses
/// between cards, so a screen cannot invent a tighter header-to-body stack.
struct FFSection<Content: View>: View {
    let title: String
    var extraTop: Bool = true
    @ViewBuilder var content: Content

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            FFSectionHeader(title: title)
            content
        }
        .padding(.top, extraTop ? theme.space.lg : 0)
    }
}

/// The uppercase label that sits above a group inside a card.
struct FFEyebrow: View {
    let text: String
    @Environment(\.ffTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .ffType(.eyebrow)
            .foregroundStyle(theme.textTertiary)
    }
}

// MARK: - Buttons

enum FFButtonKind {
    case primary, ember, secondary, outline, ghost
}

enum FFButtonSize {
    case small, medium, large

    var font: TypeRole {
        switch self {
        case .small: return .buttonSmall
        case .medium: return .button
        case .large: return .buttonLarge
        }
    }

    var padding: (x: CGFloat, y: CGFloat) {
        switch self {
        case .small: return (15, 8)
        case .medium: return (22, 13)
        case .large: return (28, 17)
        }
    }
}

struct FFButton: View {
    let title: String
    var kind: FFButtonKind = .primary
    var size: FFButtonSize = .medium
    var enabled: Bool = true
    var fullWidth: Bool = false
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .ffType(size.font)
                .foregroundStyle(foreground)
                .padding(.horizontal, size.padding.x)
                .padding(.vertical, size.padding.y)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(background, in: Capsule())
                .overlay { if let stroke { Capsule().strokeBorder(stroke, lineWidth: 1) } }
        }
        .buttonStyle(FFPressStyle())
        .disabled(!enabled)
    }

    private var foreground: Color {
        guard enabled else { return theme.disabledText }
        switch kind {
        case .primary: return theme.mossOn
        case .ember: return theme.emberOn
        case .secondary: return theme.text
        case .outline: return theme.mossText
        case .ghost: return theme.textSecondary
        }
    }

    private var background: Color {
        guard enabled else { return theme.disabledBg }
        switch kind {
        case .primary: return theme.mossFill
        case .ember: return theme.emberFill
        case .secondary: return theme.control
        case .outline, .ghost: return .clear
        }
    }

    private var stroke: Color? {
        guard enabled else { return theme.disabledLine }
        switch kind {
        case .secondary: return theme.line
        case .outline: return theme.mossText.opacity(0.35)
        default: return nil
        }
    }
}

/// 44pt circle, control fill, hairline. The plain icon affordance.
struct FFIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.41, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: size, height: size)
                .background(theme.control, in: Circle())
                .overlay { Circle().strokeBorder(theme.line, lineWidth: 1) }
        }
        .buttonStyle(FFPressStyle())
    }
}

/// The signature: full width, 60pt tall, label left, filled circle chevron right.
/// One per screen, pinned above the tab bar.
struct FFScreenCTA: View {
    let title: String
    var kind: FFButtonKind = .primary
    var enabled: Bool = true
    var busy: Bool = false
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.mossOn)
                    }
                    Text(title)
                        .ffType(.buttonLarge)
                }
                .foregroundStyle(enabled ? theme.mossOn : theme.disabledText)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(enabled ? fill : theme.disabledText)
                    .frame(width: 44, height: 44)
                    .background(enabled ? theme.mossOn : theme.disabledBg, in: Circle())
            }
            .padding(.leading, 26)
            .padding(.trailing, 8)
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .background(enabled ? fill : theme.disabledBg, in: Capsule())
        }
        .buttonStyle(FFPressStyle(scale: 0.985))
        .disabled(!enabled || busy)
    }

    private var fill: Color { kind == .ember ? theme.emberFill : theme.mossFill }
}

/// Track with a knob on the left. Drag the knob across to confirm.
struct FFSlideToConfirm: View {
    let title: String
    var enabled: Bool = true
    var busy: Bool = false
    let action: () -> Bool

    @Environment(\.ffTheme) private var theme
    @State private var drag: CGFloat = 0
    @State private var completed = false
    @State private var slideHaptics = FFSlideHapticEngine()

    private let knobSize: CGFloat = 44
    private let inset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let travel = max(0, geo.size.width - inset * 2 - knobSize)
            let offset = completed ? travel : min(max(0, drag), travel)
            let progress = travel == 0 ? 0 : offset / travel

            ZStack {
                Capsule()
                    .fill(enabled ? theme.mossFill : theme.disabledBg)

                HStack(spacing: 8) {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.mossOn)
                    }
                    Text(title)
                        .ffType(.buttonLarge)
                }
                .foregroundStyle(enabled ? theme.mossOn : theme.disabledText)
                .opacity(busy ? 1 : 1 - progress)
                .allowsHitTesting(false)

                HStack {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(enabled ? theme.mossFill : theme.disabledText)
                        .frame(width: knobSize, height: knobSize)
                        .background(enabled ? theme.mossOn : theme.disabledBg, in: Circle())
                        .offset(x: offset)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, inset)
            }
            .frame(height: 60)
            .contentShape(Capsule())
            .gesture(slideGesture(travel: travel))
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double tap to confirm")
            .accessibilityAction {
                confirm()
            }
        }
        .frame(height: 60)
        .onChange(of: busy) { _, isBusy in
            if !isBusy {
                reset()
            }
        }
        .onChange(of: enabled) { _, isEnabled in
            if !isEnabled {
                reset()
            }
        }
    }

    private func slideGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard enabled, !busy, !completed else { return }
                drag = min(max(0, value.translation.width), travel)
                slideHaptics.drag(progress: travel == 0 ? 0 : drag / travel)
            }
            .onEnded { _ in
                slideHaptics.stop()
                guard enabled, !busy, !completed else { return }
                if travel > 0, drag >= travel * 0.85 {
                    confirm()
                } else {
                    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)) {
                        drag = 0
                    }
                }
            }
    }

    private func confirm() {
        guard enabled, !busy, !completed else { return }
        completed = true
        slideHaptics.stop()
        if action() {
            FFHaptics.success()
        } else {
            reset()
        }
    }

    private func reset() {
        completed = false
        slideHaptics.stop()
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)) {
            drag = 0
        }
    }
}

/// Pulses without pausing while the thumb is down. Rate rises with progress.
@MainActor
private final class FFSlideHapticEngine {
    private let pulse = UIImpactFeedbackGenerator(style: .medium)
    private var progress: CGFloat = 0
    private var loop: Task<Void, Never>?

    func drag(progress: CGFloat) {
        self.progress = min(max(progress, 0), 1)
        guard loop == nil else { return }
        pulse.prepare()
        loop = Task { @MainActor [weak self] in
            var last = ContinuousClock.now
            self?.fire()
            while let engine = self, !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(8))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let now = ContinuousClock.now
                if now - last >= Duration.seconds(engine.interval) {
                    engine.fire()
                    last = now
                }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        progress = 0
    }

    private var interval: TimeInterval {
        let minRate = 8.0
        let maxRate = 42.0
        1 / (minRate * pow(maxRate / minRate, Double(progress)))
    }

    private func fire() {
        pulse.impactOccurred(intensity: 0.64)
        pulse.prepare()
    }
}

/// Dashed affordance — empty slots and "start something" rows.
struct FFAddRow: View {
    let title: String
    var subtitle: String?
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.mossText)
                    .frame(width: 38, height: 38)
                    .background(theme.mossFill.opacity(0.24), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    if let subtitle {
                        Text(subtitle)
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                    .strokeBorder(theme.dash, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            }
        }
        .buttonStyle(FFPressStyle())
    }
}

// MARK: - Badges

enum FFTone {
    case moss, ember, gold, neutral
}

/// Mode tag — caps, 10pt, sits on a card. 1V1 / GROUP / GOAL / STREAK.
struct FFTag: View {
    let text: String
    var tone: FFTone = .moss

    @Environment(\.ffTheme) private var theme

    init(_ text: String, tone: FFTone = .moss) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .ffType(.tag)
            .foregroundStyle(ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
    }

    private var fill: Color {
        switch tone {
        case .moss: return theme.mossFill.opacity(0.24)
        case .ember: return theme.emberFill.opacity(0.22)
        case .gold: return theme.gold.opacity(0.20)
        case .neutral: return theme.chip
        }
    }

    private var ink: Color {
        switch tone {
        case .moss: return theme.mossText
        case .ember: return theme.emberText
        case .gold: return theme.gold
        case .neutral: return theme.textSecondary
        }
    }
}

enum FFPillStyle {
    case softMoss, solidMoss, softEmber, gold, neutral
}

/// Status pill — sentence case, 11–13pt. On / Connect / 2 days left / Ended.
struct FFPill: View {
    let text: String
    var style: FFPillStyle = .softMoss

    @Environment(\.ffTheme) private var theme

    init(_ text: String, style: FFPillStyle = .softMoss) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .ffType(solid ? .caption : .micro)
            .fontWeight(.heavy)
            .foregroundStyle(ink)
            .padding(.horizontal, solid ? 13 : 11)
            .padding(.vertical, style == .gold ? 7 : (solid ? 6 : 5))
            .background(fill, in: Capsule())
    }

    private var solid: Bool { style == .solidMoss || style == .gold }

    private var fill: Color {
        switch style {
        case .softMoss: return theme.mossFill.opacity(0.26)
        case .solidMoss: return theme.mossFill
        case .softEmber: return theme.emberFill.opacity(0.22)
        case .gold: return theme.gold
        case .neutral: return theme.hairline
        }
    }

    private var ink: Color {
        switch style {
        case .softMoss: return theme.mossText
        case .solidMoss: return theme.mossOn
        case .softEmber: return theme.emberText
        case .gold: return theme.goldInk
        case .neutral: return theme.textSecondary
        }
    }
}

enum FFResult: String {
    case win = "W"
    case loss = "L"
    case draw = "–"
}

/// 24pt square, glyph radius, for dense rows of past results.
struct FFResultGlyph: View {
    let result: FFResult
    @Environment(\.ffTheme) private var theme

    init(_ result: FFResult) { self.result = result }

    var body: some View {
        Text(result.rawValue)
            .ffType(.micro)
            .fontWeight(.heavy)
            .foregroundStyle(ink)
            .frame(width: 24, height: 24)
            .background(fill, in: RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous))
    }

    private var fill: Color {
        switch result {
        case .win: return theme.mossFill.opacity(0.24)
        case .loss: return theme.emberFill.opacity(0.22)
        case .draw: return theme.hairline
        }
    }

    private var ink: Color {
        switch result {
        case .win: return theme.mossText
        case .loss: return theme.emberText
        case .draw: return theme.textTertiary
        }
    }
}

// MARK: - Avatars

/// Monogram until a photo exists. Always a circle, always the control fill with a
/// hairline. Sizes are fixed so photos drop in with no layout change.
struct FFAvatar: View {
    let monogram: String
    var size: CGFloat = 44
    var selected: Bool = false
    /// Asset name, cut from the design mocks. Falls back to the monogram.
    var photo: String?
    var dimmed: Bool = false

    @Environment(\.ffTheme) private var theme

    var body: some View {
        face
            .frame(width: size, height: size)
            .background(theme.control, in: Circle())
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(
                    selected ? theme.mossEdge : theme.line,
                    lineWidth: selected ? 3 : 1
                )
            }
            .opacity(dimmed ? 0.5 : 1)
    }

    @ViewBuilder
    private var face: some View {
        if let photo, UIImage(named: photo) != nil {
            Image(photo)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            Text(monogram)
                .font(.ff(fontSize, 800))
                .foregroundStyle(size >= 54 ? theme.monogram : theme.textDim)
        }
    }

    /// The kit's five fixed steps: 32/11, 38/13, 44/14, 54/16, 68/20.
    private var fontSize: CGFloat {
        switch size {
        case ..<35: return 11
        case ..<41: return 13
        case ..<49: return 14
        case ..<61: return 16
        default: return 20
        }
    }
}

/// Overlapping monograms with a ring in the background colour, then an overflow chip.
struct FFAvatarStack: View {
    let monograms: [String]
    var visible: Int = 3
    var size: CGFloat = 36
    var ring: Color?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let shown = Array(monograms.prefix(visible))
        let overflow = monograms.count - shown.count
        HStack(spacing: -12) {
            ForEach(Array(shown.enumerated()), id: \.offset) { offset, monogram in
                plate(
                    monogram,
                    fill: offset % 2 == 1 ? theme.plateAlt : theme.control,
                    ink: theme.textDim,
                    size: 12
                )
                .zIndex(Double(shown.count - offset))
            }
            if overflow > 0 {
                plate("+\(overflow)", fill: theme.chip, ink: theme.textTertiary, size: 11)
            }
        }
    }

    private func plate(_ text: String, fill: Color, ink: Color, size fontSize: CGFloat) -> some View {
        Text(text)
            .font(.ff(fontSize, 800))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .overlay { Circle().strokeBorder(ring ?? theme.bg, lineWidth: 2) }
    }
}

// MARK: - Cards

/// Every card, row, panel, notice and tile: card fill, hairline, 22pt radius.
struct FFCard<Content: View>: View {
    var padding: CGFloat?
    var fill: Color?
    var stroke: Color?
    @ViewBuilder var content: Content

    @Environment(\.ffTheme) private var theme

    var body: some View {
        content
            .padding(padding ?? theme.space.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill ?? theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(stroke ?? theme.hairline, radius: theme.radius.card)
    }
}

/// Hero — moss fill, one per screen. The only card that is not ink.
struct FFHeroCard: View {
    let eyebrow: String
    let tag: String
    let title: String
    let metric: String
    let caption: String
    var monogram: String?
    var progress: Double?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(eyebrow)
                    .font(.ff(12, 800))
                    .tracking(12 * 0.1)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.mossSoft)
                Spacer(minLength: 0)
                Text(tag)
                    .ffType(.micro)
                    .fontWeight(.heavy)
                    .foregroundStyle(theme.mossOn)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.heroTagFill, in: Capsule())
            }
            Text(title)
                .font(.ff(21, 800))
                .tracking(21 * -0.015)
                .foregroundStyle(theme.mossOn)
                .padding(.top, 9)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric)
                        .ffType(.metric)
                        .foregroundStyle(theme.mossOn)
                    Text(caption)
                        .ffType(.caption)
                        .foregroundStyle(theme.mossSoft)
                }
                Spacer(minLength: 0)
                if let monogram {
                    Text(monogram)
                        .font(.ff(16, 800))
                        .foregroundStyle(theme.mossOn)
                        .frame(width: 52, height: 52)
                        .background(theme.heroAvatarPlate, in: Circle())
                        .overlay { Circle().strokeBorder(theme.heroAvatarLine, lineWidth: 3) }
                }
            }
            .padding(.top, 14)
            if let progress {
                FFProgressBar(value: progress, height: 10, fill: theme.gold, track: theme.heroProgressTrack)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 19)
        .padding(.top, 17)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.mossFill, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
    }
}

/// Stat tile — designed for a grid of two.
struct FFStatTile: View {
    let tag: String
    var tone: FFTone = .moss
    var note: String?
    let title: String
    let metric: String
    let caption: String
    var progress: Double?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                FFTag(tag, tone: tone)
                Spacer(minLength: 0)
                if let note {
                    Text(note)
                        .ffType(.micro)
                        .fontWeight(.heavy)
                        .foregroundStyle(toneInk)
                }
            }
            Text(title)
                .ffType(.rowTitle)
                .foregroundStyle(theme.text)
                .padding(.top, 9)
            Text(metric)
                .font(.ff(26, 800))
                .tracking(26 * -0.03)
                .foregroundStyle(theme.text)
                .padding(.top, 8)
            Text(caption)
                .ffType(.micro)
                .foregroundStyle(theme.textSecondary)
                .padding(.top, 3)
            if let progress {
                FFProgressBar(value: progress, height: 7, fill: toneFill, track: theme.track)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 14)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }

    private var toneInk: Color {
        switch tone {
        case .moss: return theme.mossText
        case .ember: return theme.emberText
        case .gold: return theme.gold
        case .neutral: return theme.textSecondary
        }
    }

    private var toneFill: Color {
        switch tone {
        case .moss: return theme.mossFill
        case .ember: return theme.emberFill
        case .gold: return theme.gold
        case .neutral: return theme.textTertiary
        }
    }
}

/// List row — avatar, two lines, right-aligned metric and delta. Selected gets the
/// moss wash and a moss edge.
struct FFListRow: View {
    let monogram: String
    let title: String
    let subtitle: String
    let metric: String
    var delta: String?
    var ahead: Bool = true
    /// When the metric is itself the gap, it carries the moss or ember of `ahead`
    /// instead of the neutral ink the kit gives a plain total.
    var metricIsGap: Bool = false
    var selected: Bool = false
    var action: (() -> Void)?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let row = HStack(spacing: 13) {
            FFAvatar(monogram: monogram, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text(subtitle)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(metric)
                    .font(.ff(18, 800))
                    .tracking(18 * -0.02)
                    .foregroundStyle(metricIsGap ? (ahead ? theme.mossText : theme.emberText) : theme.text)
                if let delta {
                    Text(delta)
                        .ffType(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(ahead ? theme.mossText : theme.emberText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selected ? theme.mossWash : theme.card,
            in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        )
        .ffBorder(selected ? theme.mossEdge : theme.hairline, radius: theme.radius.card)

        if let action {
            Button(action: action) { row }.buttonStyle(FFPressStyle())
        } else {
            row
        }
    }
}

/// Notice — a wash panel. Ember for urgency, moss for a win.
struct FFNotice: View {
    let text: String
    var tone: FFTone = .ember
    var systemImage: String?
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 32, height: 32)
                    .background(fillStrong, in: Circle())
            }
            Text(text)
                .ffType(.label)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(action: action) {
                    FFPill(actionTitle, style: .solidMoss)
                }
                .buttonStyle(FFPressStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(wash, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(edge, radius: theme.radius.card)
    }

    private var wash: Color { tone == .moss ? theme.mossWash : theme.emberWash }
    private var edge: Color {
        (tone == .moss ? theme.mossText : theme.emberText).opacity(tone == .moss ? 0.18 : 0.22)
    }
    private var ink: Color { tone == .moss ? theme.mossText : theme.emberText }
    private var fillStrong: Color {
        (tone == .moss ? theme.mossFill : theme.emberFill).opacity(0.30)
    }
}

/// Grouped rows — the settings pattern. One card, hairline dividers inset by 16.
struct FFGroupedRows<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 0) { content }
            // Match the selected row's 5pt side inset so an edge row can use
            // concentric corners against the 22pt group.
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(theme.card)
            // Clip every row to the group's outer boundary as a final guard at
            // large accessibility sizes.
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(theme.hairline, radius: theme.radius.card)
    }
}

struct FFGroupedRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var enabled: Bool = true
    var subtitleTone: FFTone = .moss
    var trailing: AnyView?
    var action: (() -> Void)?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        let row = HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(enabled ? theme.textDim : theme.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(
                        enabled ? theme.control : theme.chip,
                        in: RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                    )
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .ffType(.rowTitle)
                    .foregroundStyle(enabled ? theme.text : theme.textSecondary)
                if let subtitle {
                    Text(subtitle)
                        .ffType(.caption)
                        .foregroundStyle(enabled ? subtitleInk : theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { row }.buttonStyle(FFPressStyle(scale: 0.99))
        } else {
            row
        }
    }

    private var subtitleInk: Color {
        switch subtitleTone {
        case .moss: return theme.mossText
        case .ember: return theme.emberText
        case .gold: return theme.gold
        case .neutral: return theme.textSecondary
        }
    }
}

extension View {
    /// A selected row inside a grouped card gets a fill concentric with the card:
    /// inner radius = outer radius - inset.
    func ffRowSelection(
        _ on: Bool,
        outerRadius: CGFloat,
        inset: CGFloat = 5,
        fill: Color
    ) -> some View {
        background {
            if on {
                RoundedRectangle(
                    cornerRadius: max(0, outerRadius - inset),
                    style: .continuous
                )
                    .fill(fill)
                    .padding(.horizontal, inset)
            }
        }
    }
}

struct FFDivider: View {
    var inset: CGFloat = 16
    var visible = true
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(height: 1)
            .padding(.horizontal, inset)
            // Keep the one-point slot so selecting a row never shifts the form.
            .opacity(visible ? 1 : 0)
    }
}

/// Ring card — progress as a dial, when the number matters more than the trend.
struct FFRingCard: View {
    let progress: Double
    let title: String
    let subtitle: String
    let metric: String
    var delta: String?
    var ahead: Bool = true

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 16) {
            FFRing(value: progress, size: 76, lineWidth: 9) {
                Text("\(Int(progress * 100))%")
                    .font(.ff(15, 800))
                    .tracking(15 * -0.02)
                    .foregroundStyle(theme.text)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ff(17, 800))
                    .tracking(17 * -0.015)
                    .foregroundStyle(theme.text)
                Text(subtitle)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(metric)
                        .font(.ff(22, 800))
                        .tracking(22 * -0.025)
                        .foregroundStyle(theme.text)
                    if let delta {
                        Text(delta)
                            .ffType(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(ahead ? theme.mossText : theme.emberText)
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }
}
