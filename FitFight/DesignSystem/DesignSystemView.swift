import SwiftUI

/// Every token and component the app is built from, in the kit's own order.
/// Internal reference rendered only by the screenshot workflow.
struct DesignSystemView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    // Live state for the interactive pieces, seeded with the kit's values.
    @State private var slider: Double = 12_000
    @State private var stepper = 10_000
    @State private var notifications = true
    @State private var units = "km"
    @State private var filter = "Live"
    @State private var metric = "Steps"
    @State private var tab = "Standings"
    @State private var duration = "1 week"
    @State private var toast: FFTone?
    @State private var showDrawer = false
    @State private var showDialog = false

    var body: some View {
        Group {
            if staticRender {
                // A scroll view only lays out its viewport off-screen, so the export
                // renders the sections directly onto the tall canvas instead.
                sections.frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView { sections }
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let toast {
                FFToast(
                    glyph: toast == .moss ? "W" : "!",
                    title: toast == .moss ? "You won Sleep Streak" : "Nina passed you",
                    message: toast == .moss
                        ? "7 of 7 nights. Sam owes you a coffee."
                        : "She climbed 280 m more. Three days left.",
                    tone: toast,
                    onClose: { self.toast = nil }
                )
                .padding(theme.space.screenPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if showDialog {
                FFDialog(
                    title: "Leave Sunday Climb?",
                    message: "Nina takes the win and your 12 day streak resets. This can't be undone.",
                    confirmTitle: "Leave",
                    onCancel: { showDialog = false },
                    onConfirm: { showDialog = false }
                )
            }
        }
        .ffDrawer(isPresented: $showDrawer, theme: theme) {
            drawerBody
        }
        .animation(theme.motion.sheet.animation, value: toast == nil)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: theme.space.sectionGap) {
            header
            colour
            typeAndShape
            buttons
            badgesAndAvatars
            cards
            controls
            overlays
            progress
            comparison
            history
            navigation
            motion
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 60)
    }

    // MARK: 00 — header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Design system")
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
                FFSegmented(items: Mode.allCases, selection: $themeStore.mode) { $0.label }
            }
            Text("Every token and component the app is built from. Night is the primary theme; each colour carries its day-mode counterpart so a screen can be built either way from the same names.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: 01 — colour

    private var colour: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "01 · Colour")
            Text("Four families. Ink is every surface, Moss is you and winning, Ember is urgency and losing, Gold is progress only. Nothing else gets to be a colour.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ThemeCatalog.swatches, id: \.title) { group in
                swatchGroup(group)
            }
        }
    }

    private func swatchGroup(_ group: SwatchGroup) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: 14) {
                FFEyebrow(group.title)
                ForEach(group.items, id: \.name) { item in
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: theme.radius.glyph, style: .continuous)
                            .fill(Color(token: item.value))
                            .frame(width: 52, height: 38)
                            .ffBorder(theme.line, radius: theme.radius.glyph)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .ffType(.label)
                                    .foregroundStyle(theme.text)
                                Text(item.value)
                                    .ffType(.micro)
                                    .foregroundStyle(theme.textFaint)
                            }
                            Text(item.use)
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: 02 — type & shape

    private var typeAndShape: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "02 · Type & shape")
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Nunito · 600 / 700 / 800")
                    specimen("26,410", .metric, "Metric hero — 34/800/−0.03em · tabular")
                    specimen("Screen title", .title, "Title — 26/800/−0.025em")
                    specimen("Card heading", .heading, "Heading — 16/800/−0.01em")
                    specimen("Supporting line under a heading", .body, "Body — 13/700 · ash")
                    specimen("Section eyebrow", .eyebrow, "Eyebrow — 12/800/0.06em/uppercase")
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 12) {
                    FFEyebrow("Radius")
                    radiusRow("pill · 999", theme.radius.pill, "Buttons, chips, badges, avatars, switches")
                    radiusRow("card · 22", theme.radius.card, "Every card, row, panel, notice and tile")
                    radiusRow("field · 14", theme.radius.field, "Form fields, tab bodies, drawer rows")
                    radiusRow("glyph · 9", theme.radius.glyph, "Result glyphs, icon tiles, menu items")
                    radiusRow("shell · 28", theme.radius.shell, "Drawer lip and device frame only")
                }
            }
        }
    }

    private func specimen(_ text: String, _ role: TypeRole, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .ffType(role)
                .foregroundStyle(role == .body || role == .eyebrow ? theme.textSecondary : theme.text)
            Text(note)
                .ffType(.micro)
                .foregroundStyle(theme.textFaint)
        }
    }

    private func radiusRow(_ name: String, _ radius: CGFloat, _ use: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: min(radius, 19), style: .continuous)
                .fill(theme.control)
                .frame(width: 52, height: 38)
                .ffBorder(theme.track, radius: min(radius, 19))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).ffType(.label).foregroundStyle(theme.text)
                Text(use).ffType(.micro).foregroundStyle(theme.textFaint)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 03 — buttons

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "03 · Buttons")
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Variants")
                    FFFlow(spacing: 10) {
                        FFButton(title: "Primary") {}
                        FFButton(title: "Ember", kind: .ember) {}
                        FFButton(title: "Secondary", kind: .secondary) {}
                        FFButton(title: "Outline", kind: .outline) {}
                        FFButton(title: "Ghost", kind: .ghost) {}
                        FFButton(title: "Disabled", enabled: false) {}
                    }
                    FFEyebrow("Sizes")
                    FFFlow(spacing: 10) {
                        FFButton(title: "Small", size: .small) {}
                        FFButton(title: "Medium", size: .medium) {}
                        FFButton(title: "Large", size: .large) {}
                        FFIconButton(systemName: "plus") {}
                    }
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 12) {
                    FFEyebrow("Screen CTA — the signature")
                    Text("Full-width, 60pt tall, label left and a filled circle chevron right. One per screen, pinned above the tab bar.")
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    FFScreenCTA(title: "Challenge Marc") {}
                    FFScreenCTA(title: "Send it", kind: .ember) {}
                    FFAddRow(title: "Add — dashed affordance", subtitle: "Empty slots and \"start something\" rows") {}
                }
            }
        }
    }

    // MARK: 04 — badges & avatars

    private var badgesAndAvatars: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "04 · Badges & avatars")
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Mode tags — caps, 10pt, on cards")
                    FFFlow(spacing: 8) {
                        FFTag("1v1")
                        FFTag("Group")
                        FFTag("Goal", tone: .ember)
                        FFTag("Streak", tone: .gold)
                    }
                    FFEyebrow("Status pills — sentence case, 11–13pt")
                    FFFlow(spacing: 8) {
                        FFPill("On")
                        FFPill("Connect", style: .solidMoss)
                        FFPill("2 days left", style: .softEmber)
                        FFPill("75% win rate", style: .gold)
                        FFPill("Ended", style: .neutral)
                    }
                    FFEyebrow("Result glyphs — 24pt square, in dense rows")
                    HStack(spacing: 8) {
                        FFResultGlyph(.win)
                        FFResultGlyph(.loss)
                        FFResultGlyph(.draw)
                        FFResultGlyph(.pending)
                        Spacer(minLength: 0)
                    }
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Avatar — monogram until a photo exists")
                    Text("Always a circle, always the control fill with a hairline. Sizes are fixed so photos drop in with no layout change.")
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .bottom, spacing: 16) {
                        avatarSample("MB", 32, "32")
                        avatarSample("NK", 38, "38")
                        avatarSample("MR", 44, "44")
                        avatarSample("TD", 54, "selected", selected: true)
                        Spacer(minLength: 0)
                    }
                    FFEyebrow("Stacked group")
                    HStack(spacing: 10) {
                        FFAvatarStack(monograms: ["MB", "NK", "MR", "TD", "AM"], ring: theme.card)
                        Text("5 in this fight")
                            .ffType(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }

    private func avatarSample(_ monogram: String, _ size: CGFloat, _ label: String, selected: Bool = false) -> some View {
        VStack(spacing: 8) {
            FFAvatar(monogram: monogram, size: size, selected: selected)
            Text(label)
                .font(.ff(10, 700))
                .foregroundStyle(selected ? theme.mossText : theme.textFaint)
        }
    }

    // MARK: 05 — cards

    private var cards: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "05 · Cards")
            FFEyebrow("Hero — moss fill, one per screen")
            FFHeroCard(
                eyebrow: "Ends in 3 days",
                tag: "Head to head",
                title: "Step Derby vs Marc",
                metric: "26,410",
                caption: "steps · you lead by 4,310",
                monogram: "MB",
                progress: 0.54
            )
            FFEyebrow("Stat tile — grid of two")
            HStack(spacing: 12) {
                FFStatTile(
                    tag: "Goal", tone: .ember, note: "day 5",
                    title: "10K a day", metric: "7,240",
                    caption: "of 10,000 steps", progress: 0.72
                )
                FFStatTile(
                    tag: "Streak", tone: .gold, note: "12 days",
                    title: "Sleep by 11", metric: "7h 20m",
                    caption: "last night", progress: 0.9
                )
            }
            FFEyebrow("List row — selected state")
            FFListRow(
                monogram: "MB", title: "Step Derby", subtitle: "Head to head · steps",
                metric: "26,410", delta: "up 4,310", ahead: true, selected: true
            )
            FFListRow(
                monogram: "NK", title: "Sunday Climb", subtitle: "Head to head · elevation",
                metric: "840", delta: "280 m back", ahead: false
            )
            FFEyebrow("Notice — ember wash")
            FFNotice(text: "2 invites expire in 2 days", tone: .ember, systemImage: "clock")
            FFNotice(text: "You won Sleep Streak", tone: .moss, actionTitle: "See", action: {})
            FFEyebrow("Grouped rows — settings pattern")
            FFGroupedRows {
                FFGroupedRow(
                    title: "Apple Watch", subtitle: "Steps · active minutes",
                    systemImage: "applewatch",
                    trailing: AnyView(FFPill("On"))
                )
                FFDivider()
                FFGroupedRow(
                    title: "Whoop", subtitle: "Sleep · recovery",
                    systemImage: "waveform.path.ecg", enabled: false,
                    trailing: AnyView(FFPill("Connect", style: .solidMoss))
                )
            }
            FFEyebrow("Ring card — progress as a dial")
            FFRingCard(
                progress: 0.54, title: "Step Derby", subtitle: "vs Marc · steps",
                metric: "26,410", delta: "up 4,310"
            )
        }
    }

    // MARK: 06 — controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "06 · Controls")
            FFCard {
                VStack(alignment: .leading, spacing: 16) {
                    FFEyebrow("Slider — drag it")
                    HStack(alignment: .firstTextBaseline) {
                        Text("Daily target").ffType(.button).foregroundStyle(theme.text)
                        Spacer(minLength: 0)
                        Text(Int(slider).formatted(.number))
                            .font(.ff(22, 800))
                            .tracking(22 * -0.025)
                            .foregroundStyle(theme.text)
                    }
                    FFSlider(value: $slider, range: 2000...25000, step: 500)
                    HStack {
                        Text("2,000").ffType(.micro).foregroundStyle(theme.textFaint)
                        Spacer(minLength: 0)
                        Text("25,000 steps").ffType(.micro).foregroundStyle(theme.textFaint)
                    }
                    FFEyebrow("Stepper")
                    FFStepper(value: $stepper, step: 1000, minimum: 1000, unit: "steps a day")
                    FFEyebrow("Switch & segmented")
                    HStack(spacing: 12) {
                        Text("Notifications").ffType(.rowTitle).foregroundStyle(theme.text)
                        Spacer(minLength: 0)
                        FFSwitch(isOn: $notifications)
                    }
                    HStack(spacing: 12) {
                        Text("Units").ffType(.rowTitle).foregroundStyle(theme.text)
                        Spacer(minLength: 0)
                        FFSegmented(items: ["km", "mi"], selection: $units) { $0 }
                    }
                    FFEyebrow("Filter chips")
                    HStack(spacing: 8) {
                        ForEach([("Live", 4), ("Invites", 2), ("Done", 12)], id: \.0) { name, count in
                            FFChip(title: name, count: count, selected: filter == name) { filter = name }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Form field — every state")
                    FFField(label: "Challenge name", help: "Everyone invited sees this name.") {
                        Text("Step Derby")
                    }
                    FFField(label: "Empty & focused", state: .focused) {
                        Text("Name your fight").foregroundStyle(theme.textFaint)
                    }
                    FFField(label: "Daily target", state: .error, help: "Pick a number above zero.") {
                        Text("0")
                    }
                    FFField(label: "Metric source", state: .disabled) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock").font(.system(size: 12, weight: .semibold))
                            Text("Apple Watch — locked to steps")
                        }
                    }
                    FFField(label: "Trash talk", counter: "17 / 140", minHeight: 88) {
                        Text("Easy week for me.")
                    }
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 18) {
                    FFEyebrow("Combo box — open it")
                    FFCombo(items: Self.metrics, selection: $metric)
                    FFEyebrow("Tabs")
                    FFTabs(items: Self.tabOrder, selection: $tab) { $0 }
                    FFCard(padding: 16, fill: theme.card) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Self.tabs[tab]?.0 ?? "")
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Text(Self.tabs[tab]?.1 ?? "")
                                .ffType(.body)
                                .foregroundStyle(theme.textSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    FFEyebrow("Popover")
                    FFPopover(
                        title: "Nina climbed 1,120 m",
                        message: "Two hill runs on Saturday. You have three days to make up 280 m."
                    )
                    FFEyebrow("Carousel — swipe it")
                    FFCarousel(cards: Self.carousel)
                    FFEyebrow("Toast — fire it")
                    HStack(spacing: 10) {
                        FFButton(title: "Win toast", size: .small) { fire(.moss) }
                        FFButton(title: "Ember toast", kind: .ember, size: .small) { fire(.ember) }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func fire(_ tone: FFTone) {
        toast = tone
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toast == tone { toast = nil }
        }
    }

    // MARK: 07 — overlays

    private var overlays: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "07 · Overlays")
            Text("The drawer is the default — it reaches the thumb. Dialogs are for decisions that can destroy something.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                FFButton(title: "Open drawer", kind: .secondary) { showDrawer = true }
                FFButton(title: "Leave this fight", kind: .outline) { showDialog = true }
                Spacer(minLength: 0)
            }
            FFEyebrow("Empty state")
            FFCard {
                FFEmptyState(
                    systemImage: "trophy",
                    title: "No fights yet",
                    message: "Pick a friend and a metric. Steps is the easy first one.",
                    actionTitle: "Start one",
                    action: {}
                )
            }
        }
    }

    private var drawerBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Log a walk")
                .font(.ff(18, 800))
                .tracking(18 * -0.015)
                .foregroundStyle(theme.text)
            Text("Counts toward Step Derby.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .padding(.top, 4)
            VStack(spacing: 8) {
                drawerRow("Distance", "3.2 km")
                drawerRow("Steps", "4,180")
            }
            .padding(.top, 16)
            FFButton(title: "Add it", size: .large, fullWidth: true) { showDrawer = false }
                .padding(.top, 16)
            Spacer(minLength: 0)
        }
    }

    private func drawerRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(title).ffType(.button).foregroundStyle(theme.text)
            Spacer(minLength: 0)
            Text(value).ffType(.button).foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.field)
    }

    // MARK: 08 — progress

    private var progress: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "08 · Progress")
            Text("One component, four contexts. Gold on a moss fill, ember or moss on a card, ring when the number matters more than the trend. Track is always the same 9% white.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            FFCard {
                VStack(alignment: .leading, spacing: 20) {
                    FFEyebrow("Bars")
                    bar("On a card, ahead · 7pt", "72%", theme.mossText, 0.72, theme.mossFill)
                    bar("On a card, behind · 7pt", "38%", theme.emberText, 0.38, theme.emberFill)
                    bar("Complete", "Done", theme.mossText, 1, theme.mossFill)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Two-up · you vs them").ffType(.caption).fontWeight(.heavy).foregroundStyle(theme.text)
                            Spacer(minLength: 0)
                            Text("26,410 / 22,100").ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                        FFProgressBar(value: 1, fill: theme.mossFill)
                        FFProgressBar(value: 0.84, fill: theme.textFaint)
                    }
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 20) {
                    FFEyebrow("Rings — 76 / 56 / 40pt")
                    HStack(spacing: 22) {
                        FFRing(value: 0.54, size: 76, lineWidth: 9) {
                            Text("54%").font(.ff(15, 800)).foregroundStyle(theme.text)
                        }
                        FFRing(value: 0.38, size: 56, lineWidth: 7, fill: theme.emberFill) {
                            Text("38%").font(.ff(12, 800)).foregroundStyle(theme.text)
                        }
                        FFRing(value: 1, size: 40, lineWidth: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(theme.mossText)
                        }
                        Spacer(minLength: 0)
                    }
                    FFEyebrow("Streak strip — 7 day")
                    FFStreakStrip(days: [
                        ("M", .hit), ("T", .hit), ("W", .hit), ("T", .miss),
                        ("F", .hit), ("S", .today), ("S", .future)
                    ])
                    HStack(spacing: 12) {
                        Text("Hit · missed · today · not yet")
                            .ffType(.body)
                            .foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 0)
                        FFPill("12 day streak", style: .gold)
                    }
                }
            }
        }
    }

    private func bar(_ label: String, _ value: String, _ ink: Color, _ progress: Double, _ fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(label).ffType(.caption).fontWeight(.heavy).foregroundStyle(theme.text)
                Spacer(minLength: 0)
                Text(value).ffType(.caption).fontWeight(.heavy).foregroundStyle(ink)
            }
            FFProgressBar(value: progress, fill: fill)
        }
    }

    // MARK: 09 — comparison

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "09 · Comparison & ranking")
            FFEyebrow("VS block — the head-to-head")
            FFVSBlock(
                you: ("AM", "You", "26,410", 1),
                them: ("MB", "Marc", "22,100", 0.84),
                delta: "+4,310",
                footnote: "Steps · 7 day fight",
                timeLeft: "3 days left"
            )
            FFEyebrow("Losing variant")
            FFBehindRow(monogram: "AM", title: "Sunday Climb", detail: "280 m behind Nina", value: "840")
            FFEyebrow("Leaderboard row — you always highlighted")
            VStack(spacing: 8) {
                FFLeaderboardRow(rank: 1, monogram: "NK", name: "Nina", value: "412", move: .up)
                FFLeaderboardRow(rank: 2, monogram: "MB", name: "Marc", value: "388", move: .same)
                FFLeaderboardRow(rank: 3, monogram: "MR", name: "Maya", value: "341", move: .up)
                FFLeaderboardRow(rank: 4, monogram: "AM", name: "You", value: "312", move: .down, isYou: true, caption: "Synced 3 Sep, 12:41")
                FFLeaderboardRow(rank: 5, monogram: "TD", name: "Theo", value: "204", move: .same)
            }
            Text("Rank 1 takes gold ink. Movement arrows are moss up, ember down, ash-faint dash for no change. The row never names its own metric — the screen header does.")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 10 — history

    private var history: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "10 · History")
            FFCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            FFEyebrow("Sparkline · 12 weeks")
                            Text("18,420")
                                .font(.ff(26, 800))
                                .tracking(26 * -0.03)
                                .foregroundStyle(theme.text)
                                .padding(.top, 5)
                            Text("up 31% since May")
                                .ffType(.caption)
                                .foregroundStyle(theme.mossText)
                        }
                        Spacer(minLength: 0)
                        FFPill("Steps")
                    }
                    FFSparkline(values: Self.spark)
                        .padding(.top, 18)
                    HStack {
                        ForEach(["May", "Jun", "Jul", "Aug"], id: \.self) { month in
                            Text(month).ffType(.micro).foregroundStyle(theme.textFaint)
                            if month != "Aug" { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.top, 10)
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 14) {
                    FFEyebrow("Bar chart · this week")
                    FFBarChart(bars: Self.weekBars)
                    Text("Today is gold, days inside the current fight are moss, earlier days drop to 42% moss. No gridlines, no axis — the number lives above the chart.")
                        .ffType(.caption)
                        .foregroundStyle(theme.textFaint)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 11 — navigation, feed & pickers

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "11 · Navigation, feed & pickers")
            FFEyebrow("Nav header — three shapes")
            FFNavTitle(title: "Fights", subtitle: "4 live · 2 waiting", actionSymbol: "plus", action: {})
            FFNavDetail(title: "Step Derby", subtitle: "3 days left", onBack: {}, onMore: {})
            FFNavFlow(title: "New challenge", step: "Step 1 of 3", onClose: {}, skipTitle: "Skip", onSkip: {})
            FFEyebrow("Activity feed row")
            FFFeedRow(glyph: "W", tone: .moss, title: "You won Sleep Streak", message: "7 of 7 nights · Sam owes you a coffee", time: "2h")
            FFFeedRow(glyph: "!", tone: .ember, title: "Nina passed you", message: "Sunday Climb · she leads by 280 m", time: "5h")
            FFFeedRow(glyph: "+", tone: .neutral, title: "Theo invited you", message: "Coffee Run · most km in a week", time: "1d")
            FFEyebrow("Duration picker")
            FFDurationPicker(options: ["3 days", "1 week", "1 month", "Custom"], selection: $duration)
            FFEyebrow("Date range — start and end are filled, middle is wash")
            FFDateRange(days: [22, 23, 24, 25, 26, 27, 28], start: 23, end: 27)
            Text("Sep 23 – 27 · 5 days")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
            FFEyebrow("Skeletons — while a connector fetches")
            FFSkeletonRow()
            Text("Skeletons mirror the real card's geometry exactly. Never a spinner on a card — a spinner only for a full-screen first load.")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 12 — motion

    private var motion: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSectionHeader(title: "12 · Motion")
            FFGroupedRows {
                ForEach(Array(Self.motionTokens.enumerated()), id: \.offset) { index, token in
                    if index > 0 { FFDivider() }
                    HStack(alignment: .top, spacing: 16) {
                        Text(token.0)
                            .ffType(.button)
                            .foregroundStyle(theme.mossText)
                            .frame(width: 78, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(token.1).ffType(.caption).foregroundStyle(theme.textDim)
                            Text(token.2).ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            Text("Reduced motion is a global kill switch — every duration collapses to near-zero, nothing loops. Wins may celebrate; losses never animate.")
                .ffType(.body)
                .foregroundStyle(theme.textFaint)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Kit sample data

    private static let metrics = [
        FFComboItem(name: "Steps", source: "Apple Watch"),
        FFComboItem(name: "Distance", source: "Strava"),
        FFComboItem(name: "Active minutes", source: "Whoop"),
        FFComboItem(name: "Sleep", source: "Whoop")
    ]

    private static let tabOrder = ["Standings", "Activity", "Rules"]

    private static let tabs: [String: (String, String)] = [
        "Standings": ("You lead by 4,310", "Three days left. Marc has never closed a gap this big."),
        "Activity": ("Marc walked 8.2 km", "Two hours ago · counted 11,400 steps toward the fight."),
        "Rules": ("Most steps in 7 days", "Apple Watch and Strava both count. Manual entries are capped at 5,000 a day.")
    ]

    private static let carousel = [
        FFCarouselCard(tag: "1v1", tone: .moss, name: "Steps", value: "26,410", unit: "this week"),
        FFCarouselCard(tag: "1v1", tone: .ember, name: "Elevation", value: "840", unit: "metres climbed"),
        FFCarouselCard(tag: "Goal", tone: .gold, name: "Sleep", value: "7h 20m", unit: "last night")
    ]

    private static let spark: [Double] = [8, 11, 9, 14, 12, 17, 15, 19, 16, 21, 24, 22]

    private static let weekBars: [(label: String, value: Double, tone: FFBarTone)] = [
        ("M", 17, .past), ("T", 15, .past), ("W", 19, .past), ("T", 16, .past),
        ("F", 21, .active), ("S", 24, .active), ("S", 22, .today)
    ]

    private static let motionTokens: [(String, String, String)] = [
        ("instant", "0ms", "Selection, chip and tab state — never animate a filter"),
        ("quick", "150ms expo-out", "Popovers, dropdowns, toggles"),
        ("sheet", "320ms expo-out", "Drawers, dialogs, carousel travel"),
        ("count", "600ms ease-out", "A metric number ticking up after a sync"),
        ("celebrate", "900ms ease-out, once", "Win state only. Never on a loss."),
        ("shimmer", "1400ms linear, infinite", "Skeletons while a connector is fetching")
    ]
}

/// Wrapping horizontal stack — the kit lays button and badge rows out with flex-wrap.
struct FFFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var height: CGFloat = 0
        var width: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, x + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
                x = 0
            }
            row.indices.append(index)
            row.height = max(row.height, size.height)
            x += size.width + spacing
            row.width = x - spacing
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

#Preview {
    let store = ThemeStore()
    return DesignSystemView()
        .environmentObject(store)
        .fitFightTheme(store.theme)
}
