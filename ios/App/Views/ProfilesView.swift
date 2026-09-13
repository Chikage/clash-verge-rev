import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @Environment(AppStore.self) private var store
    @State private var showsSubscription = false
    @State private var showsFileImporter = false
    @State private var profileToDelete: ClashProfile?

    var body: some View {
        Group {
            if store.profiles.profiles.isEmpty {
                ContentUnavailableView {
                    Label("Add your first profile", systemImage: "doc.badge.plus")
                } description: {
                    Text("Import a Clash YAML subscription or choose a configuration from Files.")
                        .foregroundStyle(AppTheme.secondaryText)
                } actions: {
                    Button("Add subscription") { showsSubscription = true }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.action)
                        .foregroundStyle(.white)
                        .disabled(store.isBusy)
                    Button("Import file") { showsFileImporter = true }
                        .disabled(store.isBusy)
                }
            } else {
                List {
                    ForEach(store.profiles.profiles) { profile in
                        ProfileRow(profile: profile) { profileToDelete = profile }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Profiles")
        .overlay {
            if store.isBusy {
                ProgressView("Working…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add subscription", systemImage: "link") { showsSubscription = true }
                    Button("Import file", systemImage: "folder") { showsFileImporter = true }
                } label: {
                    Label("Add profile", systemImage: "plus")
                }
                .disabled(store.isBusy)
            }
        }
        .sheet(isPresented: $showsSubscription) { SubscriptionImportView() }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [
            UTType(filenameExtension: "yaml") ?? .text,
            UTType(filenameExtension: "yml") ?? .text,
        ]) { result in
            switch result {
            case .success(let url):
                Task { _ = await store.runFileImport(url) }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .alert("Delete profile?", isPresented: Binding(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        ), presenting: profileToDelete) { profile in
            Button("Delete", role: .destructive) {
                Task { await store.deleteProfile(profile) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("\(profile.name) and its saved configuration will be removed from this device.")
        }
    }
}

private struct ProfileRow: View {
    @Environment(AppStore.self) private var store
    let profile: ClashProfile
    let delete: () -> Void

    private var isSelected: Bool { store.profiles.selectedID == profile.id }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await store.selectProfile(profile) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryText)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profile.name)
                            .font(.headline)
                            .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
                        Text(profile.sourceURL?.host ?? String(localized: "Local file"))
                            .font(.subheadline)
                        Text("Updated \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        if let usage = profile.usage {
                            Text("Used \(ByteCountFormatter.string(fromByteCount: usage.usedBytes, countStyle: .binary)) of \(ByteCountFormatter.string(fromByteCount: usage.total, countStyle: .binary))")
                            if let expiration = usage.expiresAt {
                                Text("Expires \(expiration.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(store.isBusy)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            Menu {
                if profile.sourceURL != nil {
                    Button("Update subscription", systemImage: "arrow.clockwise") {
                        Task { await store.updateProfile(profile) }
                    }
                }
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(AppTheme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(store.isBusy)
            .accessibilityLabel("Actions for \(profile.name)")
        }
        .listRowBackground(isSelected ? AppTheme.accent.opacity(0.08) : Color(uiColor: .secondarySystemGroupedBackground))
    }
}

private struct SubscriptionImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name, prompt:
                        Text("Name (optional)").foregroundStyle(AppTheme.secondaryText)
                    )
                    TextField("Subscription URL", text: $url, prompt:
                        Text("Subscription URL").foregroundStyle(AppTheme.secondaryText), axis: .vertical
                    )
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                } footer: {
                    Text("Use a subscription URL that returns a complete Clash YAML configuration.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineSpacing(3)
                }
                if let message = store.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(AppTheme.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                if isImporting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Downloading and validating profile…")
                    }
                }
            }
            .navigationTitle("Add subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        isImporting = true
                        Task {
                            let imported = await store.runImport(url: url, name: name)
                            isImporting = false
                            if imported { dismiss() }
                        }
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                }
            }
        }
        .interactiveDismissDisabled(isImporting)
        .onAppear { store.errorMessage = nil }
    }
}
