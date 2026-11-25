import SwiftUI

struct DiarySyncControls: View {
    let sync: DiarySync
    let onDevices: () -> Void
    @State private var confirmation: Confirmation?

    private enum Confirmation { case restore, stop }

    private var isOn: Bool { sync.joined && !sync.pendingDisable }

    private var subtitle: String? {
        if sync.pendingDisable { return L.s(sync.busy ? "sync_deleting" : "sync_pending_delete") }
        if sync.busy { return L.s("sync_working") }
        if let lastSync = sync.lastSync, isOn {
            return L.s("sync_last", lastSync.formatted(date: .abbreviated, time: .shortened))
        }
        return isOn ? nil : L.s("sync_summary")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.s("sync_title")).font(AppFont.titleMedium).foregroundStyle(AppColors.ink)
                            if let subtitle { Text(subtitle).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if sync.busy {
                            ProgressView().frame(width: 51)
                        } else {
                            Toggle(L.s("sync_title"), isOn: Binding(get: { isOn }, set: setSync))
                                .labelsHidden().fixedSize().tint(AppColors.primary)
                                .disabled(sync.pendingDisable)
                        }
                    }
                    Divider()
                    Button(action: onDevices) {
                        Text(L.s("devices_title")).font(AppFont.titleMedium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.primary)
                }
            }
            if sync.conflicts && !sync.pendingDisable {
                Text(L.s("sync_conflict"))
                Group {
                    ActionRow(title: L.s("sync_keep_local")) { Task { await sync.resolve(useCloud: false) } }
                    ActionRow(title: L.s("sync_use_cloud")) { Task { await sync.resolve(useCloud: true) } }
                }.disabled(sync.busy)
            }
            if sync.failed && !sync.pendingDisable {
                Text(L.s("sync_failed"))
                if isOn && !sync.conflicts {
                    ActionRow(title: L.s("sync_refresh")) { Task { await sync.refresh() } }
                }
            }
        }
        .confirmationDialog(L.s(confirmation == .stop ? "sync_disable" : "sync_restore"),
                            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                            titleVisibility: .visible, presenting: confirmation) { choice in
            if choice == .stop {
                Button(L.s("delete"), role: .destructive) { Task { await sync.disable() } }
                    .disabled(sync.busy || !isOn)
            } else {
                Button(L.s("sync_continue")) { Task { await sync.enable() } }
                    .disabled(sync.busy || isOn)
            }
        } message: { choice in
            Text(L.s(choice == .stop ? "sync_delete_hint" : "sync_restore_hint"))
        }
        .task { await sync.refresh() }
    }

    private func setSync(_ value: Bool) {
        guard value != isOn, !sync.busy, !sync.pendingDisable else { return }
        if !value { confirmation = .stop }
        else if sync.enabled { confirmation = .restore }
        else { Task { await sync.enable() } }
    }
}

struct RestoreDiaryPrompt: ViewModifier {
    let sync: DiarySync
    @State private var dismissed = false

    func body(content: Content) -> some View {
        content.alert(L.s("sync_restore"), isPresented: Binding(
            get: { sync.enabled && !sync.joined && !sync.busy && !dismissed },
            set: { if !$0 { dismissed = true } }
        )) {
            Button(L.s("sync_continue")) { Task { await sync.enable() } }
            Button(L.s("cancel"), role: .cancel) {}
        } message: {
            Text(L.s("sync_restore_hint"))
        }
    }
}
