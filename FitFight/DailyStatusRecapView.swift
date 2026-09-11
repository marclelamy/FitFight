import SwiftUI

struct DailyStatusRecap: Identifiable, Equatable {
    let fightID: String
    let body: String

    var id: String { fightID }
}

struct DailyStatusRecapView: View {
    let recap: DailyStatusRecap
    let onDismiss: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today's check-in")
                .font(.ff(22, 800))
                .tracking(22 * -0.015)
                .foregroundStyle(theme.text)
            Text(recap.body)
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            FFButton(title: String(localized: "Got it"), kind: .primary, fullWidth: true) {
                onDismiss()
            }
            .padding(.top, 24)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
    }
}
