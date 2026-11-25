import SwiftUI
import FirstSpoonCore

private struct AccountDevice: Decodable, Identifiable {
    let id: String
    let deviceName: String?
    let createdAt: String?
    let current: Bool

    var title: String { deviceName ?? L.s("device_unknown") }
    var detail: String? {
        if current { return L.s("device_current") }
        guard let createdAt,
              let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(createdAt) else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct DeviceList: Decodable { let devices: [AccountDevice] }
private struct RevokeDevice: Encodable { let id: String }
private struct RevokeReply: Decodable { let revoked: Bool? }

struct DevicesView: View {
    @Environment(AppContainer.self) private var app
    @State private var devices: [AccountDevice] = []
    @State private var selected: AccountDevice?
    @State private var working = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(devices) { device in
                    if device.current {
                        ActionRow(title: device.title, value: device.detail)
                    } else {
                        ActionRow(title: device.title, value: device.detail) { selected = device }
                    }
                }
                if devices.count == 1 && devices[0].current && !working && !failed {
                    Text(L.s("devices_empty")).font(AppFont.bodyMedium)
                }
                if failed {
                    Text(L.s("devices_error")).font(AppFont.bodyMedium).foregroundStyle(AppColors.alert)
                    ActionRow(title: L.s("assistant_retry")) { Task { await load() } }
                }
                if working { ProgressView() }
            }
            .padding(.horizontal, screenPadding)
        }
        .appScreen()
        .navigationTitle(L.s("devices_title"))
        .disabled(working)
        .task { await load() }
        .alert(item: $selected) { device in
            Alert(title: Text(L.s("device_end")), message: Text(L.s("device_end_hint")),
                  primaryButton: .destructive(Text(L.s("device_end"))) { Task { await end(device) } },
                  secondaryButton: .cancel(Text(L.s("cancel"))))
        }
    }

    private func load() async {
        guard let owner = app.tokens.userId else { return }
        working = true
        defer { working = false }
        switch await app.api.call("GET", "user/sessions", authorized: true, as: DeviceList.self, expectedOwner: owner) {
        case .success(let reply): devices = reply.devices; failed = false
        case .failure:
            failed = true
            Analytics.track(.deviceSessionsFailed(operation: .list))
        }
    }

    private func end(_ device: AccountDevice) async {
        guard let owner = app.tokens.userId else { return }
        working = true
        defer { working = false }
        switch await app.api.call("POST", "user/sessions", body: RevokeDevice(id: device.id),
                                  authorized: true, as: RevokeReply.self, expectedOwner: owner) {
        case .success(let reply):
            devices.removeAll { $0.id == device.id }
            failed = false
            if reply.revoked == true { Analytics.track(.deviceSessionRevoked) }
        case .failure:
            failed = true
            Analytics.track(.deviceSessionsFailed(operation: .revoke))
        }
    }
}
