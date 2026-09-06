import SwiftUI

enum NewFightOpening {
    case choose
    case create
    case join
}

struct NewFightView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    @State private var opening: NewFightOpening
    @State private var step = 0
    @State private var username = ""
    @State private var inviteHandles: [String] = []
    @State private var usernameError: String?
    @State private var durationDays = 7
    @State private var fightTitle = ""
    @State private var actionText = ""
    @State private var visibilityJoinable = false
    @State private var recurring = false
    @State private var joinCode = ""
    @State private var joinable: [FitFightJoinableFight] = []
    @State private var lookingUp = false
    @FocusState private var usernameFocused: Bool
    @FocusState private var titleFocused: Bool
    @FocusState private var actionFocused: Bool
    @FocusState private var joinCodeFocused: Bool

    init(opening: NewFightOpening = .choose) {
        _opening = State(initialValue: opening)
    }

    private var duration: String {
        switch durationDays {
        case 3: return String(localized: "3 days")
        case 14: return String(localized: "2 weeks")
        case 30: return String(localized: "1 month")
        default: return String(localized: "1 week")
        }
    }

    private var canStart: Bool {
        let title = fightTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let peopleReady = visibilityJoinable || !inviteHandles.isEmpty
        return session.isSignedIn
            && steps.hasAsked
            && peopleReady
            && title.count <= 120
            && action.count <= 120
            && !model.isCreatingFight
    }

    private var canContinue: Bool {
        switch step {
        case 2: return visibilityJoinable || !inviteHandles.isEmpty
        default: return true
        }
    }

    var body: some View {
        GeometryReader { proxy in
            FFScreen(clearance: false) {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    flowProgress
                    currentScreen
                    Spacer(minLength: theme.space.lg)
                    flowAction
                }
                .frame(
                    minHeight: max(0, proxy.size.height - theme.space.base - theme.space.lg),
                    alignment: .top
                )
            }
        }
        .task(id: opening) {
            guard opening == .join, !staticRender else { return }
            joinable = await model.listJoinableFights(session: session)
        }
    }

    @ViewBuilder
    private var flowAction: some View {
        if opening == .choose {
            EmptyView()
        } else if opening == .join {
            FFButton(
                title: lookingUp ? String(localized: "Looking up…") : String(localized: "Open fight"),
                size: .large,
                enabled: joinCode.count == 4 && !lookingUp,
                fullWidth: true
            ) {
                lookupCode()
            }
            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        } else if step == 4 {
            FFSlideToConfirm(
                title: model.isCreatingFight
                    ? String(localized: "Starting…")
                    : String(localized: "Slide to start"),
                enabled: canStart,
                busy: model.isCreatingFight
            ) {
                startFight()
            }

            if !steps.hasAsked {
                Text("Connect Apple Health above to start this fight.")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let error = model.createError, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        } else {
            FFButton(title: String(localized: "Next"), size: .large, enabled: canContinue, fullWidth: true) {
                step += 1
            }
        }
    }

    private var flowProgress: some View {
        VStack(spacing: 10) {
            HStack {
                if opening == .choose {
                    Text("New fight")
                        .ffType(.title)
                        .foregroundStyle(theme.text)
                        .frame(minHeight: 44)
                } else {
                    Button {
                        goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .ffType(.buttonSmall)
                            .foregroundStyle(theme.text)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if opening == .create {
                    Text(
                        String(
                            localized: "fight.step-progress",
                            defaultValue: "Step \(step + 1) of 5"
                        )
                    )
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .frame(minHeight: 44)
                }
            }

            if opening == .create {
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? theme.mossFill : theme.disabledBg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    String(
                        localized: "fight.step-progress",
                        defaultValue: "Step \(step + 1) of 5"
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch opening {
        case .choose:
            chooseStep
        case .join:
            joinStep
        case .create:
            currentStep
        }
    }

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create or join?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Start a new fight, or join one with a short code.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            FFGroupedRows {
                FFGroupedRow(
                    title: String(localized: "Create"),
                    subtitle: String(localized: "Invite people or share a code"),
                    systemImage: "plus",
                    subtitleTone: .moss,
                    action: { opening = .create }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Join"),
                    subtitle: String(localized: "Enter a 4-character code or pick a live fight"),
                    systemImage: "person.badge.plus",
                    subtitleTone: .neutral,
                    action: {
                        opening = .join
                        Task { joinable = await model.listJoinableFights(session: session) }
                    }
                )
            }
        }
    }

    private var joinStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Join a fight")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Enter the 4-character code, or pick a live joinable fight. Scores stay inside the fight.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Code")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                Group {
                    if staticRender {
                        Text(verbatim: joinCode.isEmpty ? "K7M2" : joinCode)
                            .foregroundStyle(joinCode.isEmpty ? theme.textFaint : theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("K7M2", text: $joinCode)
                            .focused($joinCodeFocused)
                            .foregroundStyle(theme.text)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { lookupCode() }
                            .onChange(of: joinCode) { _, value in
                                let allowed = CharacterSet(charactersIn: "23456789ABCDEFGHJKMNPQRSTVWXYZ")
                                let cleaned = value.uppercased().unicodeScalars
                                    .filter { allowed.contains($0) }
                                joinCode = String(String.UnicodeScalarView(cleaned).prefix(4))
                            }
                    }
                }
                .font(.ff(15, 700))
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(theme.line, radius: theme.radius.field)
            }

            FFSectionHeader(title: String(localized: "Live joinable fights"))
            let rows = staticRender ? Self.screenshotJoinable : joinable
            if rows.isEmpty {
                Text("No live joinable fights right now. Ask for a code.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
            } else {
                FFGroupedRows {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { FFDivider() }
                        FFGroupedRow(
                            title: Fight.displayTitle(name: item.name, actionText: item.actionText),
                            subtitle: item.recurring
                                ? String(
                                    localized: "fight.joinable-row-repeats",
                                    defaultValue: "@\(item.ownerHandle) · \(item.memberCount) in · repeats"
                                )
                                : String(
                                    localized: "fight.joinable-row",
                                    defaultValue: "@\(item.ownerHandle) · \(item.memberCount) in"
                                ),
                            systemImage: "figure.walk",
                            subtitleTone: .neutral,
                            trailing: AnyView(Text(item.joinCode).ffType(.caption).foregroundStyle(theme.textSecondary)),
                            action: {
                                Task { await model.openJoinable(item, session: session) }
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case 0: metricStep
        case 1: durationStep
        case 2: peopleStep
        case 3: actionStep
        default: reviewStep
        }
    }

    private var metricStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What are you competing on?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Every fight tracks one metric. Steps is the only metric available right now.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            FFGroupedRows {
                FFGroupedRow(
                    title: String(localized: "Steps"),
                    subtitle: String(localized: "Highest total wins · Apple Health"),
                    systemImage: "figure.walk",
                    subtitleTone: .moss,
                    trailing: AnyView(Image(systemName: "checkmark").foregroundStyle(theme.mossText))
                )
            }
        }
    }

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who can join?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text(
                    visibilityJoinable
                        ? String(localized: "Anyone with the code can join. Usernames are optional.")
                        : String(localized: "Add at least one exact username and press Return. They must already have a FitFight account.")
                )
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            FFGroupedRows {
                FFGroupedRow(
                    title: String(localized: "Invite-only"),
                    subtitle: String(localized: "People you add by username"),
                    systemImage: "lock",
                    subtitleTone: visibilityJoinable ? .neutral : .moss,
                    trailing: visibilityJoinable
                        ? nil
                        : AnyView(Image(systemName: "checkmark").foregroundStyle(theme.mossText)),
                    action: { visibilityJoinable = false }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Joinable"),
                    subtitle: String(localized: "Short code plus the live join list"),
                    systemImage: "link",
                    subtitleTone: visibilityJoinable ? .moss : .neutral,
                    trailing: visibilityJoinable
                        ? AnyView(Image(systemName: "checkmark").foregroundStyle(theme.mossText))
                        : nil,
                    action: { visibilityJoinable = true }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)

                Group {
                    if staticRender {
                        Text(verbatim: username.isEmpty ? String(localized: "@username") : username)
                            .foregroundStyle(username.isEmpty ? theme.textFaint : theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("@username", text: $username)
                            .focused($usernameFocused)
                            .foregroundStyle(theme.text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                addUsername()
                                usernameFocused = false
                            }
                    }
                }
                .font(.ff(15, 700))
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .ffBorder(usernameError == nil ? theme.line : theme.emberText, radius: theme.radius.field)

                if let usernameError {
                    Text(usernameError)
                        .ffType(.caption)
                        .foregroundStyle(theme.emberText)
                }
            }

            if !inviteHandles.isEmpty {
                FFGroupedRows {
                    ForEach(Array(inviteHandles.enumerated()), id: \.element) { index, handle in
                        if index > 0 { FFDivider() }
                        HStack(spacing: 12) {
                            FFAvatar(monogram: String(handle.prefix(2)).uppercased(), size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: "@\(handle)")
                                    .ffType(.rowTitle)
                                    .foregroundStyle(theme.text)
                                Text("Added to this fight")
                                    .ffType(.caption)
                                    .foregroundStyle(theme.mossText)
                            }
                            Spacer(minLength: 8)
                            Button {
                                inviteHandles.removeAll { $0 == handle }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(theme.textSecondary)
                                    .frame(width: 44, height: 44)
                                    .background(theme.control, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                String(
                                    localized: "fight.remove-handle",
                                    defaultValue: "Remove @\(handle)"
                                )
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private var durationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How long will the fight last?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("It starts immediately. Steps after the exact end time do not count.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Duration")
                    .ffType(.rowTitle)
                    .foregroundStyle(theme.text)
                FFDurationPicker(
                    options: [
                        String(localized: "3 days"),
                        String(localized: "1 week"),
                        String(localized: "2 weeks"),
                        String(localized: "1 month"),
                    ],
                    selection: Binding(
                        get: { duration },
                        set: { selection in
                            if selection == String(localized: "3 days") { durationDays = 3 }
                            else if selection == String(localized: "2 weeks") { durationDays = 14 }
                            else if selection == String(localized: "1 month") { durationDays = 30 }
                            else { durationDays = 7 }
                        }
                    )
                )
            }

            FFGroupedRows {
                FFGroupedRow(
                    title: String(localized: "Repeat when it ends"),
                    subtitle: String(localized: "The next window starts when this one ends"),
                    systemImage: "arrow.clockwise",
                    subtitleTone: recurring ? .moss : .neutral,
                    trailing: AnyView(
                        Toggle("", isOn: $recurring)
                            .labelsHidden()
                            .tint(theme.mossFill)
                    )
                )
            }
        }
    }

    private var actionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Title and action")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Both are optional. If you skip a title, the action is the name of the fight.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(2)
            }

            limitedField(
                label: String(localized: "Title"),
                placeholder: String(localized: "Weekend walk-off"),
                text: $fightTitle,
                focus: $titleFocused,
                submitLabel: .next,
                onSubmit: { actionFocused = true }
            )
            limitedField(
                label: String(localized: "Loser action"),
                placeholder: String(localized: "Cook dinner"),
                text: $actionText,
                focus: $actionFocused,
                submitLabel: .done,
                onSubmit: { actionFocused = false }
            )
        }
    }

    private func limitedField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .ffType(.rowTitle)
                .foregroundStyle(theme.text)
            Group {
                if staticRender {
                    Text(verbatim: text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                        .foregroundStyle(text.wrappedValue.isEmpty ? theme.textFaint : theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: text)
                        .focused(focus)
                        .foregroundStyle(theme.text)
                        .submitLabel(submitLabel)
                        .onSubmit(onSubmit)
                        .onChange(of: text.wrappedValue) { _, value in
                            if value.count > 120 {
                                text.wrappedValue = String(value.prefix(120))
                            }
                        }
                }
            }
            .font(.ff(15, 700))
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .ffBorder(theme.line, radius: theme.radius.field)

            Text(verbatim: "\(text.wrappedValue.count)/120")
                .ffType(.caption)
                .foregroundStyle(theme.textFaint)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var reviewStep: some View {
        let title = fightTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let opponents = inviteHandles.isEmpty
            ? String(localized: "Anyone with the code")
            : inviteHandles.map { "@\($0)" }.formatted(.list(type: .and))

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ready to fight?")
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text("Check the agreement before you start.")
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
            }

            FFGroupedRows {
                FFGroupedRow(
                    title: String(localized: "Metric"),
                    subtitle: String(localized: "Steps · highest total wins"),
                    systemImage: "figure.walk",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 0 }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Duration"),
                    subtitle: String(
                        localized: "fight.duration-end",
                        defaultValue: "\(duration)\(recurring ? " · repeats" : "") · ends \(endDate(from: Date()).formatted(date: .abbreviated, time: .shortened))"
                    ),
                    systemImage: "calendar",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 1 }
                )
                FFDivider()
                FFGroupedRow(
                    title: visibilityJoinable ? String(localized: "Joinable") : String(localized: "Invite-only"),
                    subtitle: opponents,
                    systemImage: visibilityJoinable ? "link" : "person.2",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 2 }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Title"),
                    subtitle: title.isEmpty
                        ? (action.isEmpty ? String(localized: "None") : String(localized: "Uses the action"))
                        : title,
                    systemImage: "textformat",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 3 }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Loser action"),
                    subtitle: action.isEmpty ? String(localized: "None") : action,
                    systemImage: "flag",
                    subtitleTone: .neutral,
                    trailing: AnyView(Text("Change").ffType(.caption).foregroundStyle(theme.mossText)),
                    action: { step = 3 }
                )
                FFDivider()
                FFGroupedRow(
                    title: String(localized: "Apple Health Steps"),
                    subtitle: steps.hasAsked
                        ? String(localized: "Ready to score this fight")
                        : String(localized: "Connect to score this fight"),
                    systemImage: "heart",
                    enabled: !model.isRefreshingFights,
                    subtitleTone: steps.hasAsked ? .moss : .ember,
                    trailing: AnyView(
                        FFPill(
                            steps.hasAsked ? String(localized: "Connected") : String(localized: "Connect"),
                            style: steps.hasAsked ? .softMoss : .solidMoss
                        )
                    ),
                    action: steps.hasAsked ? nil : connectAppleHealth
                )
                .disabled(model.isRefreshingFights)
            }

            FFCard(fill: theme.mossWash, stroke: theme.mossText.opacity(0.18)) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        String(
                            localized: "fight.you-versus",
                            defaultValue: "You vs \(opponents)"
                        )
                    )
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    Text(
                        String(
                            localized: "fight.winner-after-duration",
                            defaultValue: "Most Steps wins after \(duration.lowercased())."
                        )
                    )
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                    if recurring {
                        Text("When it ends, the next window starts automatically.")
                            .ffType(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                    if !action.isEmpty {
                        Text(
                            String(
                                localized: "fight.loser-will",
                                defaultValue: "The loser will \(action)."
                            )
                        )
                            .ffType(.body)
                            .foregroundStyle(theme.text)
                    }
                }
            }
        }
    }

    private func goBack() {
        if opening == .join || (opening == .create && step == 0) {
            opening = .choose
            model.createError = nil
            return
        }
        if opening == .create {
            step -= 1
        }
    }

    private func lookupCode() {
        guard joinCode.count == 4, !lookingUp else { return }
        lookingUp = true
        Task {
            await model.openJoinCode(joinCode, session: session)
            lookingUp = false
        }
    }

    private func addUsername() {
        let handle = SessionStore.strippedHandle(username)
        usernameError = nil

        guard SessionStore.isValidHandle(handle) else {
            usernameError = String(localized: "Use 2–30 letters, numbers, or underscores.")
            return
        }
        if handle == session.profile?.handle {
            usernameError = String(localized: "Add someone else’s username.")
            return
        }
        guard !inviteHandles.contains(handle) else {
            usernameError = String(
                localized: "fight.handle-already-added",
                defaultValue: "@\(handle) is already in this fight."
            )
            return
        }

        inviteHandles.append(handle)
        username = ""
    }

    private func endDate(from startsAt: Date) -> Date {
        return Calendar.current.date(
            byAdding: .day,
            value: durationDays,
            to: startsAt
        ) ?? startsAt.addingTimeInterval(TimeInterval(durationDays * 86_400))
    }

    private func startFight() -> Bool {
        guard canStart else { return false }
        guard model.beginCreateFight() else { return false }

        let startsAt = Date()
        let title = fightTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await model.createAndStartFight(
                name: title,
                startsAt: startsAt,
                endsAt: endDate(from: startsAt),
                actionText: action,
                inviteHandles: inviteHandles,
                visibility: visibilityJoinable ? "joinable" : "invite_only",
                recurring: recurring
            )
            if (model.createError ?? "").isEmpty {
                opening = .choose
                step = 0
                model.tab = .fights
            }
        }
        return true
    }

    private func connectAppleHealth() {
        Task {
            await model.refreshFights(session: session, steps: steps, trigger: .manual, requestAccess: true)
        }
    }

    private static var screenshotJoinable: [FitFightJoinableFight] {
        [
            FitFightJoinableFight(
                fightId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                seriesId: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
                name: "Office steps",
                joinCode: "K7M2",
                ownerHandle: "maya",
                actionText: "Cook dinner",
                startsAt: "2026-09-04T12:00:00Z",
                endsAt: "2026-09-11T12:00:00Z",
                memberCount: 8,
                recurring: true,
                alreadyMember: false,
                canJoinNext: true
            ),
        ]
    }
}
