import SwiftUI
import Payhub

/// The pay-links list: a filter menu, a `List` of rows, pull-to-refresh, a
/// toolbar `+` to create one, and tap-through to the detail screen. Owns its
/// own `NavigationStack` so push-from-deep-link works.
struct PayLinksView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = PayLinksViewModel()

    @State private var showCreate = false
    @State private var path: [String] = []   // pay-link IDs on the navigation stack

    private var canCreate: Bool { isWriteRole(repository.me?.effectiveRole ?? "") }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Pay-links")
                .navigationDestination(for: String.self) { id in
                    PayLinkDetailView(payLinkID: id) { updated in vm.apply(updated) }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { filterMenu }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showCreate = true } label: { Image(systemName: "plus") }
                            .disabled(!canCreate)
                            .accessibilityLabel("Create pay-link")
                    }
                }
        }
        .sheet(isPresented: $showCreate) {
            CreatePayLinkView { _ in Task { await vm.refresh() } }
        }
        .onAppear {
            vm.bind(repository: repository)
            vm.onAppear()
        }
        .onChange(of: router.pendingPayLinkID) { id in
            if let id { path = [id]; router.pendingPayLinkID = nil }
        }
        .onChange(of: router.pendingPayLinkFilter) { f in
            if let f { vm.filter = f; router.pendingPayLinkFilter = nil }
        }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.links.isEmpty {
            LoadingView(caption: "Loading pay-links…")
        } else if let error = vm.error, vm.links.isEmpty {
            ErrorStateView(error: error) { Task { await vm.refresh() } }
        } else if vm.links.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(vm.links, id: \.id) { link in
                NavigationLink(value: link.id) {
                    PayLinkRow(link: link)
                }
                .task { await vm.loadMoreIfNeeded(currentItem: link) }
            }
            if vm.hasMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.refresh() }
    }

    private var emptyState: some View {
        EmptyStateView(
            title: vm.filter == .all ? "No pay-links yet" : "Nothing here",
            systemImage: vm.filter.systemImage,
            description: vm.filter == .all
                ? "Create a pay-link and share it — the customer picks how to pay."
                : "No pay-links match “\(vm.filter.label)”.",
            actionTitle: (vm.filter == .all && canCreate) ? "Create pay-link" : nil,
            action: (vm.filter == .all && canCreate) ? { showCreate = true } : nil
        )
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $vm.filter) {
                ForEach(PayLinkFilter.allCases) { f in
                    Label(f.label, systemImage: f.systemImage).tag(f)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: vm.filter.systemImage)
                Text(vm.filter.label)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.medium))
        }
    }
}
