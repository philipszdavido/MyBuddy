//
//  EditAccountView.swift
//  MyBuddy
//
//  Edit profile on the MyBuddy API backend: photo (with upload progress), name, username (checked as
//  you type), bio, location, website and account privacy.
//

import PhotosUI
import SwiftUI

@MainActor
final class EditAccountViewModel: ObservableObject {
    @Published private(set) var profile: AccountProfile?
    @Published var displayName = ""
    @Published var username = ""
    @Published var bio = ""
    @Published var location = ""
    @Published var website = ""
    @Published var isPrivate = false
    @Published private(set) var usernameStatus: UsernameStatus?
    @Published private(set) var checkingUsername = false
    @Published private(set) var saving = false
    @Published private(set) var avatarProgress: Double?
    @Published var errorMessage: String?

    static let bioLimit = 160
    let repository: AccountRepository

    init(repository: AccountRepository) { self.repository = repository }

    func load() async {
        do { apply(try await repository.me()) } catch { errorMessage = AppError.wrap(error).userMessage }
    }

    private func apply(_ p: AccountProfile) {
        profile = p
        displayName = p.displayName
        username = p.username ?? ""
        bio = p.bio ?? ""
        location = p.location ?? ""
        website = p.website ?? ""
        isPrivate = p.visibility == .private
    }

    var hasChanges: Bool {
        guard let p = profile else { return false }
        return displayName != p.displayName || username.lowercased() != (p.username ?? "") || bio != (p.bio ?? "")
            || location != (p.location ?? "") || website != (p.website ?? "") || isPrivate != (p.visibility == .private)
    }

    var canSave: Bool {
        guard hasChanges, !saving, !displayName.trimmingCharacters(in: .whitespaces).isEmpty, bio.count <= Self.bioLimit else { return false }
        let usernameChanged = username.lowercased() != (profile?.username ?? "")
        return !usernameChanged || username.isEmpty == false && usernameStatus == .available
    }

    /// Debounced availability check, cancelled by the caller's `.task(id:)` when the text changes.
    func checkUsername() async {
        let candidate = username.lowercased()
        guard candidate != (profile?.username ?? ""), !candidate.isEmpty else { usernameStatus = nil; return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        checkingUsername = true
        defer { checkingUsername = false }
        usernameStatus = try? await repository.usernameStatus(candidate)
    }

    func save() async -> Bool {
        guard let p = profile else { return false }
        saving = true
        defer { saving = false }
        var c = ProfileChanges()
        if displayName != p.displayName { c.displayName = displayName.trimmingCharacters(in: .whitespaces) }
        if username.lowercased() != (p.username ?? "") { c.username = username.lowercased() }
        if bio != (p.bio ?? "") { c.bio = bio }
        if location != (p.location ?? "") { c.location = location }
        if website != (p.website ?? "") { c.website = website }
        if isPrivate != (p.visibility == .private) { c.visibility = isPrivate ? .private : .public }
        do {
            apply(try await repository.update(c))
            return true
        } catch {
            errorMessage = AppError.wrap(error).userMessage
            return false
        }
    }

    func setAvatar(_ image: UIImage) async {
        guard let prepared = await ImageProcessor.prepare(image, maxDimension: ImageProcessor.avatarMaxDimension) else { return }
        avatarProgress = 0
        defer { avatarProgress = nil }
        do {
            let updated = try await repository.setAvatar(prepared.data) { [weak self] p in
                Task { @MainActor in self?.avatarProgress = p }
            }
            profile?.avatarURL = updated.avatarURL
        } catch {
            errorMessage = AppError.wrap(error).userMessage
        }
    }

    func removeAvatar() async {
        do { profile?.avatarURL = try await repository.removeAvatar().avatarURL }
        catch { errorMessage = AppError.wrap(error).userMessage }
    }
}

struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: EditAccountViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var confirmPrivate = false

    init(repository: AccountRepository) {
        _model = StateObject(wrappedValue: EditAccountViewModel(repository: repository))
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: DS.Space.s) {
                    avatar
                    HStack(spacing: DS.Space.l) {
                        PhotosPicker(selection: $photoItem, matching: .images) { Text("Change photo").fontWeight(.medium) }
                        if model.profile?.avatarURL != nil {
                            Button("Remove", role: .destructive) { Task { await model.removeAvatar() } }
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .disabled(model.avatarProgress != nil)
                    if let progress = model.avatarProgress { UploadProgressView(progress: progress).frame(maxWidth: 200) }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Name") {
                    TextField("Your name", text: $model.displayName).multilineTextAlignment(.trailing)
                }
                LabeledContent("Username") {
                    HStack(spacing: DS.Space.xxs) {
                        Text("@").foregroundStyle(DS.Palette.tertiaryText)
                        TextField("username", text: $model.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                usernameFooter
            }

            Section {
                TextField("Bio", text: $model.bio, axis: .vertical).lineLimit(3...6)
            } header: {
                Text("Bio")
            } footer: {
                Text("\(model.bio.count)/\(EditAccountViewModel.bioLimit)")
                    .foregroundStyle(model.bio.count > EditAccountViewModel.bioLimit ? DS.Palette.danger : DS.Palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .monospacedDigit()
            }

            Section {
                LabeledContent("Location") { TextField("City, country", text: $model.location).multilineTextAlignment(.trailing) }
                LabeledContent("Website") {
                    TextField("https://", text: $model.website)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Toggle("Private account", isOn: Binding(get: { model.isPrivate }, set: { newValue in
                    if newValue { model.isPrivate = true } else { confirmPrivate = true }
                }))
            } footer: {
                Text(model.isPrivate
                     ? "Only approved followers and your contacts can see your posts. New followers need your approval."
                     : "Anyone can follow you and see your public posts.")
            }

            if let p = model.profile {
                Section("Private information") {
                    LabeledContent("Email", value: p.email ?? "–")
                    LabeledContent("Phone") {
                        HStack(spacing: DS.Space.xxs) {
                            Text(p.phoneNumber ?? "–")
                            if p.phoneVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(DS.Palette.success).accessibilityLabel("Verified") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if model.saving { ProgressView() } else {
                    Button("Save") { Task { if await model.save() { dismiss() } } }
                        .fontWeight(.semibold)
                        .disabled(!model.canSave)
                }
            }
        }
        .confirmationDialog("Make your account public?", isPresented: $confirmPrivate, titleVisibility: .visible) {
            Button("Make public") { model.isPrivate = false }
        } message: {
            Text("Pending follow requests will be approved automatically and anyone will be able to follow you.")
        }
        .task { await model.load() }
        .task(id: model.username) { await model.checkUsername() }
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { await model.setAvatar(image) }
            }
        }
        .errorAlert($model.errorMessage)
    }

    private var avatar: some View {
        let user = model.profile.map { UserSummary(id: $0.id, username: $0.username, displayName: $0.displayName, avatarURL: $0.avatarURL, isVerified: false) }
        return AvatarView(user: user, size: 96)
            .overlay { if model.avatarProgress != nil { Circle().fill(.black.opacity(0.35)); ProgressView().tint(.white) } }
            .accessibilityLabel("Profile photo")
    }

    @ViewBuilder
    private var usernameFooter: some View {
        if model.checkingUsername {
            Text("Checking…")
        } else {
            switch model.usernameStatus {
            case .available?: Label("Available", systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.success)
            case .taken?: Label("That username is taken", systemImage: "xmark.circle.fill").foregroundStyle(DS.Palette.danger)
            case .invalid?: Text("3–30 characters: letters, numbers, underscores and periods.").foregroundStyle(DS.Palette.danger)
            case nil: Text("People can find you by your username.")
            }
        }
    }
}

#Preview {
    NavigationStack { EditAccountView(repository: MockAccountRepository()) }
}
