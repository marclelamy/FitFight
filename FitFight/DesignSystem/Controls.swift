import SwiftUI

// Sections 06, 07 and 11 of the kit: controls, overlays, navigation & pickers.

// MARK: - Slider

/// 12pt track, 26pt bone knob. The kit snaps to a step as you drag.
struct FFSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double = 1

    @Environment(\.ffTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            let fraction = fraction(of: value)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule()
                    .fill(theme.mossFill)
                    .frame(width: geo.size.width * fraction)
                Circle()
                    .fill(theme.text)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.6), radius: 5, y: 3)
                    .offset(x: (geo.size.width - 26) * fraction)
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let travel = max(geo.size.width - 26, 1)
                        let raw = min(max((drag.location.x - 13) / travel, 0), 1)
                        let span = range.upperBound - range.lowerBound
                        value = (range.lowerBound + (raw * span) / step).rounded() * step
                    }
            )
        }
        .frame(height: 26)
    }

    private func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }
}

// MARK: - Stepper

struct FFStepper: View {
    @Binding var value: Int
    var step: Int = 1000
    var minimum: Int = 0
    var unit: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            button("minus", filled: false) { value = max(minimum, value - step) }
            VStack(spacing: 4) {
                Text(value.formatted(.number))
                    .font(.ff(30, 800))
                    .tracking(30 * -0.03)
                    .foregroundStyle(theme.text)
                Text(unit)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            button("plus", filled: true) { value += step }
        }
    }

    private func button(_ symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(filled ? theme.mossOn : theme.text)
                .frame(width: 46, height: 46)
                .background(filled ? theme.mossFill : theme.control, in: Circle())
                .overlay {
                    if !filled { Circle().strokeBorder(theme.track, lineWidth: 1) }
                }
        }
        .buttonStyle(FFPressStyle())
    }
}

// MARK: - Switch & segmented

struct FFSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.mossFill : theme.switchOff)
                Circle().fill(theme.text).frame(width: 24, height: 24)
            }
            .frame(width: 50, height: 30)
            .padding(3)
            .frame(width: 50, height: 30)
        }
        .buttonStyle(FFHapticPlainStyle())
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.15), value: isOn)
    }
}

struct FFSegmented<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .ffType(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(on ? theme.mossOn : theme.textSecondary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 6)
                        .background(on ? theme.mossFill : .clear, in: Capsule())
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
        .padding(3)
        .background(theme.chip, in: Capsule())
    }
}

/// Filter chip with a count. Selection is instant — the kit never animates a filter.
struct FFChip: View {
    let title: String
    var count: Int?
    var selected: Bool = false
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .opacity(0.7)
                }
            }
            .ffType(.label)
            .foregroundStyle(selected ? theme.mossOn : theme.chipInk)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(selected ? theme.mossFill : theme.card, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    selected ? theme.chipEdgeOn : theme.chipEdge,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(FFHapticPlainStyle())
    }
}

// MARK: - Form field

enum FFFieldState {
    case normal, focused, error, disabled
}

/// Form field — label, box, help line. Every state comes from the kit.
struct FFField<Content: View>: View {
    let label: String
    var state: FFFieldState = .normal
    var help: String?
    var counter: String?
    var minHeight: CGFloat?
    @ViewBuilder var content: Content

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .ffType(.label)
                .foregroundStyle(labelInk)
                .padding(.bottom, 7)
            content
                .font(.ff(15, 700))
                .foregroundStyle(state == .disabled ? theme.disabledText : theme.text)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: minHeight == nil ? .leading : .topLeading)
                .background(fill, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(border, radius: theme.radius.field)
                .overlay {
                    // The focus ring is a 3pt halo outside the border, not a thicker border.
                    if state == .focused {
                        RoundedRectangle(cornerRadius: theme.radius.field + 3, style: .continuous)
                            .strokeBorder(theme.mossEdge.opacity(0.22), lineWidth: 3)
                            .padding(-3)
                    }
                }
            if let help {
                HStack(spacing: 7) {
                    if state == .error {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.emberText)
                    }
                    Text(help)
                        .ffType(.caption)
                        .fontWeight(state == .error ? .heavy : .bold)
                        .foregroundStyle(state == .error ? theme.emberText : theme.textTertiary)
                }
                .padding(.top, 7)
            }
            if let counter {
                Text(counter)
                    .ffType(.caption)
                    .foregroundStyle(theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 7)
            }
        }
    }

    private var labelInk: Color {
        switch state {
        case .error: return theme.emberText
        case .disabled: return theme.textTertiary
        default: return theme.text
        }
    }

    private var fill: Color {
        switch state {
        case .error: return theme.emberFill.opacity(0.12)
        case .disabled: return theme.disabledBg
        default: return theme.card
        }
    }

    private var border: Color {
        switch state {
        case .focused: return theme.mossEdge
        case .error: return theme.emberFill
        case .disabled: return theme.disabledLine
        case .normal: return theme.line
        }
    }
}

// MARK: - Combo box

struct FFComboItem: Identifiable {
    let id = UUID()
    let name: String
    let source: String
}

struct FFCombo: View {
    let items: [FFComboItem]
    @Binding var selection: String
    @State private var open = false

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(selection)
                    .font(.ff(15, 700))
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .ffBorder(open ? theme.mossEdge : theme.line, radius: theme.radius.field)
        }
        .buttonStyle(FFHapticPlainStyle())
        .overlay(alignment: .topLeading) {
            if open { menu.offset(y: 60) }
        }
        .zIndex(open ? 1 : 0)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    selection = item.name
                    open = false
                } label: {
                    HStack(spacing: 10) {
                        Text(item.name)
                            .ffType(.button)
                            .foregroundStyle(item.name == selection ? theme.text : theme.textDim)
                        Spacer(minLength: 0)
                        Text(item.source)
                            .ffType(.micro)
                            .foregroundStyle(theme.textTertiary)
                        if item.name == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(theme.mossText)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        item.name == selection ? theme.mossWash : .clear,
                        in: RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                    )
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
        .padding(6)
        .background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
        .ffBorder(theme.overlayLine, radius: theme.radius.field)
        .shadow(color: .black.opacity(0.85), radius: 24, y: 16)
    }
}

// MARK: - Tabs

struct FFTabs<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .ffType(.label)
                        .foregroundStyle(on ? theme.mossOn : theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            on ? theme.mossFill : .clear,
                            in: RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                        )
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
        .padding(4)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
    }
}

// MARK: - Popover

struct FFPopover: View {
    let title: String
    let message: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .ffType(.button)
                .foregroundStyle(theme.text)
            Text(message)
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 268, alignment: .leading)
        .background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
        .ffBorder(theme.overlayLine, radius: theme.radius.field)
        .shadow(color: .black.opacity(0.85), radius: 24, y: 16)
    }
}

// MARK: - Carousel

struct FFCarouselCard: Identifiable {
    let id = UUID()
    let tag: String
    let tone: FFTone
    let name: String
    let value: String
    let unit: String
}

struct FFCarousel: View {
    let cards: [FFCarouselCard]
    @State private var index = 0

    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    /// Tag + name + value + unit at the kit's paddings.
    private let staticCardHeight: CGFloat = 132

    var body: some View {
        VStack(spacing: 16) {
            if staticRender {
                // A rigid HStack of 214pt cards will not compress, and .clipped() only
                // cuts drawing, not layout — so it is measured off a flexible container.
                Color.clear
                    .frame(height: staticCardHeight)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 12) {
                            ForEach(cards) { card in
                                cardView(card)
                            }
                        }
                        .fixedSize()
                    }
                    .clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(cards) { card in
                            cardView(card)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: Binding(
                    get: { cards.indices.contains(index) ? cards[index].id : cards.first?.id },
                    set: { id in
                        if let id, let found = cards.firstIndex(where: { $0.id == id }) { index = found }
                    }
                ))
            }
            HStack(spacing: 6) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { offset, _ in
                    Capsule()
                        .fill(offset == index ? theme.mossText : theme.dotIdle)
                        .frame(width: offset == index ? 22 : 6, height: 6)
                }
                Spacer(minLength: 0)
            }
            .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.24), value: index)
        }
    }

    private func cardView(_ card: FFCarouselCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FFTag(card.tag, tone: card.tone)
            Text(card.name)
                .ffType(.rowTitle)
                .foregroundStyle(theme.text)
                .padding(.top, 10)
            Text(card.value)
                .font(.ff(26, 800))
                .tracking(26 * -0.03)
                .foregroundStyle(theme.text)
                .padding(.top, 8)
            Text(card.unit)
                .ffType(.micro)
                .foregroundStyle(theme.textSecondary)
                .padding(.top, 3)
        }
        .padding(.horizontal, 17)
        .padding(.top, 16)
        .padding(.bottom, 17)
        .frame(width: 214, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }
}

// MARK: - Toast

struct FFToast: View {
    let glyph: String
    let title: String
    let message: String
    var tone: FFTone = .moss
    var onClose: (() -> Void)?
    /// Floating overlays keep the kit drop shadow; in-flow banners do not.
    var raised: Bool = true

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(glyph)
                .ffType(.label)
                .foregroundStyle(tone == .moss ? theme.mossOn : theme.emberOn)
                .frame(width: 32, height: 32)
                .background(tone == .moss ? theme.mossFill : theme.emberFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .ffType(.button)
                    .foregroundStyle(theme.text)
                Text(message)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(theme.textDim)
                        .frame(width: 28, height: 28)
                        .background(theme.hairline, in: Circle())
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(wash, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(edge, radius: theme.radius.card)
        .shadow(color: .black.opacity(raised ? 0.8 : 0), radius: raised ? 20 : 0, y: raised ? 14 : 0)
    }

    private var wash: Color {
        (tone == .moss ? theme.mossFill : theme.emberFill).opacity(tone == .moss ? 0.20 : 0.18)
    }

    private var edge: Color {
        (tone == .moss ? theme.mossText : theme.emberText).opacity(tone == .moss ? 0.24 : 0.26)
    }
}

// MARK: - Overlays

/// Drawer — the default overlay, because it reaches the thumb. Native sheet with the
/// kit's shell radius and fills, so the system keeps the drag and dismiss behaviour.
extension View {
    func ffDrawer<Body: View>(
        isPresented: Binding<Bool>,
        theme: Theme,
        @ViewBuilder content: @escaping () -> Body
    ) -> some View {
        sheet(isPresented: isPresented) {
            content()
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .presentationBackground(theme.overlay)
                .presentationCornerRadius(theme.radius.shell)
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium])
                .fitFightTheme(theme)
        }
    }
}

/// Dialog — for decisions that can destroy something. Custom rather than a system
/// alert because the kit specifies the fill, radius and button pair.
struct FFDialog: View {
    let title: String
    let message: String
    var cancelTitle: String = "Stay"
    var confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        ZStack {
            theme.scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.ff(18, 800))
                    .tracking(18 * -0.015)
                    .foregroundStyle(theme.text)
                Text(message)
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
                HStack(spacing: 9) {
                    FFButton(title: cancelTitle, kind: .secondary, fullWidth: true, action: onCancel)
                    FFButton(title: confirmTitle, kind: .ember, fullWidth: true, action: onConfirm)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(theme.overlayLine, radius: theme.radius.card)
            .shadow(color: .black.opacity(0.9), radius: 30, y: 20)
            .padding(24)
        }
    }
}

struct FFEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(theme.mossText)
                .frame(width: 64, height: 64)
                .background(theme.mossFill.opacity(0.20), in: Circle())
            Text(title)
                .font(.ff(19, 800))
                .tracking(19 * -0.02)
                .foregroundStyle(theme.text)
                .padding(.top, 18)
            Text(message)
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 7)
            if let actionTitle, let action {
                FFButton(title: actionTitle, action: action)
                    .padding(.top, 20)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Navigation

/// Nav header, shape one: big title, subtitle, one round action.
struct FFNavTitle: View {
    let title: String
    var subtitle: String?
    var actionSymbol: String?
    var action: (() -> Void)?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.ff(22, 800))
                    .tracking(22 * -0.025)
                    .foregroundStyle(theme.text)
                if let subtitle {
                    Text(subtitle)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if let actionSymbol, let action {
                FFNavGlyph(systemName: actionSymbol, action: action)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.field)
    }
}

/// Nav header, shape two: back, centred title pair, overflow.
struct FFNavDetail: View {
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?
    var onMore: (() -> Void)?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            if let onBack { FFNavGlyph(systemName: "chevron.left", action: onBack) }
            VStack(spacing: 0) {
                Text(title)
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                if let subtitle {
                    Text(subtitle)
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            if let onMore { FFNavGlyph(systemName: "ellipsis", action: onMore) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }
}

/// Nav header, shape three: close, step counter, skip.
struct FFNavFlow: View {
    let title: String
    var step: String?
    var onClose: (() -> Void)?
    var skipTitle: String?
    var onSkip: (() -> Void)?

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            if let onClose { FFNavGlyph(systemName: "xmark", action: onClose) }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                if let step {
                    Text(step)
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if let skipTitle, let onSkip {
                Button(action: onSkip) {
                    Text(skipTitle)
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.field)
    }
}

struct FFNavGlyph: View {
    let systemName: String
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: 38, height: 38)
                .background(theme.control, in: Circle())
                .overlay { Circle().strokeBorder(theme.track, lineWidth: 1) }
        }
        .buttonStyle(FFPressStyle())
    }
}

struct FFFeedRow: View {
    let glyph: String
    var tone: FFTone = .moss
    let title: String
    let message: String
    let time: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(glyph)
                .ffType(.button)
                .foregroundStyle(tone == .neutral ? theme.textDim : .white)
                .frame(width: 34, height: 34)
                .background(iconFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .ffType(.button)
                    .foregroundStyle(theme.text)
                Text(message)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
            Text(time)
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }

    private var iconFill: Color {
        switch tone {
        case .moss: return theme.mossFill
        case .ember: return theme.emberFill
        case .gold: return theme.gold
        case .neutral: return theme.control
        }
    }
}

// MARK: - Pickers

struct FFDurationPicker: View {
    let options: [String]
    @Binding var selection: String

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option)
                        .ffType(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(on ? theme.mossOn : theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            on ? theme.mossFill : theme.card,
                            in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                        )
                        .ffBorder(on ? theme.mossEdge : theme.hairline, radius: theme.radius.field)
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
    }
}

/// Date range — start and end are filled, the middle is wash.
struct FFDateRange: View {
    let days: [Int]
    let start: Int
    let end: Int
    /// Square at phone widths: seven cells and six 6pt gaps across a 353pt column.
    var cellHeight: CGFloat = 45

    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let edge = day == start || day == end
                let inside = day > start && day < end
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: cellHeight)
                    .background(
                        edge ? theme.mossFill : (inside ? theme.mossFill.opacity(0.20) : .clear),
                        in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                    )
                    .overlay {
                        Text("\(day)")
                            .font(.ff(13, edge ? 800 : 700))
                            .foregroundStyle(edge ? theme.mossOn : (inside ? theme.mossText : theme.textTertiary))
                    }
            }
        }
    }
}

// MARK: - Skeletons

/// Skeletons mirror the real card's geometry exactly. Never a spinner on a card —
/// a spinner is only for a full-screen first load.
struct FFSkeleton: View {
    var width: CGFloat?
    var height: CGFloat = 13
    var radius: CGFloat?

    @Environment(\.ffTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shift: CGFloat = -1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? height / 2, style: .continuous)
        shape
            .fill(theme.skeleton)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .overlay {
                GeometryReader { geo in
                    if !reduceMotion {
                        LinearGradient(
                            colors: [.clear, theme.skeletonHi, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: shift * geo.size.width)
                    }
                }
            }
            .clipShape(shape)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    shift = 1.6
                }
            }
    }
}

/// The list-row skeleton — same geometry as FFListRow.
struct FFSkeletonRow: View {
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(theme.skeleton)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                FFSkeleton(width: 120, height: 13)
                FFSkeleton(width: 70, height: 10)
            }
            Spacer(minLength: 0)
            FFSkeleton(width: 56, height: 22)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }
}
