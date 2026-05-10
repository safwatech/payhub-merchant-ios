import SwiftUI
import Payhub

/// Detail screen for one pay-link: its fields, share/extend/clone/cancel actions
/// (gated on a write role), and a snackbar for action feedback.
struct PayLinkDetailView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm: PayLinkDetailViewModel
    private let onUpdate: (PayLink) -> Void

    @State private var showExtendDialog = false
    @State private var showCustomExtend = false
    @State private var customDays = 7
    @State private var showCancelAlert = false

    init(payLinkID: String, onUpdate: @escaping (PayLink) -> Void = { _ in }) {
        _vm = StateObject(wrappedValue: PayLinkDetailViewModel(payLinkID: payLinkID))
        self.onUpdate = onUpdate
    }

    var body: some View {
        Group {
            if let link = vm.link {
                detail(link)
            } else if vm.isLoading {
                LoadingView(caption: "Loading…")
            } else if let error = vm.error {
                ErrorStateView(error: error) { Task { await vm.reload() } }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Pay-link")
        .navigationBarTitleDisplayMode(.inline)
        .toast($vm.toast)
        .alert(item: $vm.error) { err in
            Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
        }
        .navigationDestination(isPresented: clonedNavBinding) {
            if let id = vm.clonedLinkID { PayLinkDetailView(payLinkID: id, onUpdate: onUpdate) }
        }
        .onAppear { vm.bind(repository: repository, onUpdate: onUpdate) }
        .task { await vm.load() }
    }

    private var clonedNavBinding: Binding<Bool> {
        Binding(get: { vm.clonedLinkID != nil }, set: { if !$0 { vm.clonedLinkID = nil } })
    }

    // MARK: - Detail body

    private func detail(_ link: PayLink) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(Money.format(minor: link.amountMinor, currency: link.currency))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                        Spacer()
                        StatusBadge(rawStatus: link.status)
                    }
                    Text(link.merchantOrderRef)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let desc = link.description, !desc.isEmpty {
                        Text(desc).font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Link") {
                LabeledContent("URL") {
                    Text(link.url)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Button {
                    UIPasteboard.general.string = link.url
                    vm.toast = Toast(message: "Link copied", systemImage: "doc.on.doc")
                } label: { Label("Copy link", systemImage: "doc.on.doc") }
                LabeledContent("Short token", value: link.shortToken)
            }

            Section("Status") {
                LabeledContent("Attempts", value: "\(link.attempts) / 5")
                if let expiry = link.expiresAt, let date = ISO.date(from: expiry) {
                    LabeledContent("Expires") {
                        VStack(alignment: .trailing) {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                            Text(RelativeTime.string(for: date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if link.extendCount > 0 {
                    LabeledContent("Extended", value: "\(link.extendCount)×")
                }
                if link.resharedCount > 0 {
                    LabeledContent("Re-shared", value: "\(link.resharedCount)×")
                }
                if let created = link.createdAt, let date = ISO.date(from: created) {
                    LabeledContent("Created", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if let from = link.clonedFromId {
                    LabeledContent("Cloned from") {
                        NavigationLink("Open original") { PayLinkDetailView(payLinkID: from, onUpdate: onUpdate) }
                            .font(.footnote)
                    }
                }
            }

            if let psps = link.allowedPSPs, !psps.isEmpty {
                Section("Payment methods") {
                    ForEach(psps, id: \.self) { code in
                        Label(PSP.label(code), systemImage: PSP.all.first { $0.code == code.lowercased() }?.symbol ?? "creditcard")
                    }
                }
            }

            actionsSection(link)
        }
        .refreshable { await vm.reload() }
        .confirmationDialog("Extend expiry", isPresented: $showExtendDialog, titleVisibility: .visible) {
            Button("+ 1 day") { vm.extend(seconds: 86_400) }
            Button("+ 1 week") { vm.extend(seconds: 7 * 86_400) }
            Button("Custom…") { showCustomExtend = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Cancel this pay-link?", isPresented: $showCancelAlert) {
            Button("Cancel pay-link", role: .destructive) { vm.cancel() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Customers won't be able to pay with this link anymore. This can't be undone.")
        }
        .sheet(isPresented: $showCustomExtend) {
            customExtendSheet
        }
    }

    @ViewBuilder
    private func actionsSection(_ link: PayLink) -> some View {
        if vm.canWrite {
            Section {
                if let url = URL(string: link.url), vm.canReshare {
                    ShareLink(item: url) {
                        Label("Re-share link", systemImage: "square.and.arrow.up")
                    }
                    .simultaneousGesture(TapGesture().onEnded { vm.markShared() })
                }
                if vm.canExtend {
                    Button {
                        showExtendDialog = true
                    } label: { Label("Extend expiry", systemImage: "calendar.badge.plus") }
                }
                if vm.canClone {
                    Button {
                        vm.clone()
                    } label: { Label("Clone", systemImage: "doc.on.doc") }
                }
            } header: {
                Text("Actions")
            } footer: {
                if !vm.isActive {
                    Text("This pay-link isn't active, so it can't be extended or cancelled — but you can clone it into a fresh one.")
                }
            }

            if vm.canCancel {
                Section {
                    Button(role: .destructive) {
                        showCancelAlert = true
                    } label: { Label("Cancel pay-link", systemImage: "xmark.circle") }
                }
            }
        } else {
            Section {
                InfoBanner(text: "Your role can view pay-links but not change them. Ask an owner if you need to share, extend, clone, or cancel.",
                           systemImage: "lock")
            }
        }

        if vm.isMutating {
            Section { HStack { Spacer(); ProgressView(); Spacer() } }
        }
    }

    private var customExtendSheet: some View {
        NavigationStack {
            Form {
                Stepper(value: $customDays, in: 1...30) {
                    Text("Extend by \(customDays) day\(customDays == 1 ? "" : "s")")
                }
            }
            .navigationTitle("Custom extension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCustomExtend = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Extend") {
                        vm.extend(seconds: customDays * 86_400)
                        showCustomExtend = false
                    }
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}
