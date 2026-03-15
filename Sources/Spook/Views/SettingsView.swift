import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("refreshInterval") private var refreshInterval = 1.0
    @AppStorage("showInDock") private var showInDock = false
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        setDockVisibility(newValue)
                    }
            } header: {
                Text("General")
            }

            Section {
                Picker("Refresh interval", selection: $refreshInterval) {
                    Text("0.5 seconds").tag(0.5)
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
            } header: {
                Text("Display")
            }

            Section {
                HStack {
                    Text("Data retention")
                    Spacer()
                    Text("30 days")
                        .foregroundColor(.secondary)
                }

                Button("Clear All History") {
                    showClearConfirmation = true
                }
                .foregroundColor(.red)
            } header: {
                Text("Data")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }

                Link("View on GitHub", destination: URL(string: "https://github.com/qaid/the-spook-sat-by-the-port")!)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 350)
        .confirmationDialog("Clear all traffic history?", isPresented: $showClearConfirmation) {
            Button("Clear All History", role: .destructive) {
                Task {
                    await HistoryStore.shared.clearAllHistory()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all recorded traffic data. This action cannot be undone.")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }

    private func setDockVisibility(_ visible: Bool) {
        if visible {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
