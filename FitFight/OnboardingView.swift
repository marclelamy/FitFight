import PhotosUI
import SwiftUI

/// First-run handle after Apple sign-in. People challenge you with this name.
struct OnboardingView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

    @State private var handle = ""
    @State private var error = ""
    @State private var isSaving = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text("Pick a username")
                .ffType(.title)
                .foregroundStyle(theme.text)
            Text("People challenge you with this. Letters, numbers, underscore. 2–30 characters.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .padding(.top, 10)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 14) {
                    Group {
                        if let photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 68, height: 68)
                                .clipShape(Circle())
                                .overlay {
                                    Circle().strokeBorder(theme.mossEdge, lineWidth: 3)
                                }
                        } else {
                            FFAvatar(monogram: previewInitials, size: 68, selected: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Add a photo")
                            .ffType(.rowTitle)
                            .foregroundStyle(theme.text)
                        Text("Optional. You can change it later on You.")
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 24)
            }
            .buttonStyle(FFHapticPlainStyle())
            FFField(
                label: String(localized: "Username"),
                state: fieldState,
                help: error.isEmpty ? nil : error
            ) {
                TextField("username", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focused)
            }
            .padding(.top, 28)
            FFScreenCTA(
                title: isSaving ? String(localized: "Saving…") : String(localized: "Continue"),
                enabled: canSave
            ) {
                Task { await save() }
            }
            .padding(.top, 20)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
        .onChange(of: pickerItem) { _, item in
            Task { await loadPhoto(item) }
        }
    }

    private var previewInitials: String {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "FF" : String(trimmed.prefix(2)).uppercased()
    }

    private var fieldState: FFFieldState {
        if !error.isEmpty { return .error }
        return focused ? .focused : .normal
    }

    private var canSave: Bool {
        !isSaving && SessionStore.isValidHandle(handle)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photo = image
    }

    private func save() async {
        error = ""
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.setHandle(handle)
            if let photo {
                let media = try await MediaUploader.upload(photo, purpose: "profile", session: session)
                try await session.setAvatar(media)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
