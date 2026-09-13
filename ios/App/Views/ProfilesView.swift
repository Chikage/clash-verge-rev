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
                } actions: {
                    Button("Add subscription") { showsSubscription = true }
                        .buttonStyle(.borderedProminent)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await store.selectProfile(profile) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: store.profiles.selectedID == profile.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.profiles.selectedID == profile.id ? Color.purple : Color.secondary)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.name).font(.headline).foregroundStyle(.primary)
                        Text(profile.sourceURL?.host ?? String(localized: "Local file"))
                        Text("Updated \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        if let usage = profile.usage {
                            Text("Used \(ByteCountFormatter.string(fromByteCount: usage.usedBytes, countStyle: .binary)) of \(ByteCountFormatter.string(fromByteCount: usage.total, countStyle: .binary))")
                            if let expiration = usage.expiresAt {
                                Text("Expires \(expiration.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(store.isBusy)
            .accessibilityAddTraits(store.profiles.selectedID == profile.id ? .isSelected : [])
            Menu {
                if profile.sourceURL != nil {
                    Button("Update subscription", systemImage: "arrow.clockwise") {
                        Task { await store.updateProfile(profile) }
                    }
                }
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(store.isBusy)
            .accessibilityLabel("Actions for \(profile.name)")
        }
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
                    TextField("Name (optional)", text: $name)
                    TextField("Subscription URL", text: $url, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                } footer: {
                    Text("Use a subscription URL that returns a complete Clash YAML configuration.")
                }
                if let message = store.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
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
