// Sources/App/Features/Settings/WebServerSettingsView.swift
// Webサーバー設定タブ

import SwiftUI
import Infrastructure

// Swift.Task と Domain.Task の名前衝突を解決
private typealias AsyncTask = _Concurrency.Task

struct WebServerSettingsView: View {
    @EnvironmentObject var container: DependencyContainer

    @State private var portText: String = ""
    @State private var currentPort: Int = AppConfig.WebServer.defaultPort
    @State private var isServerRunning = false
    @State private var isRestarting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var portChanged = false
    @State private var allowRemoteAccess = false
    @State private var remoteAccessChanged = false

    private var enteredPort: Int? {
        Int(portText)
    }

    private var isValidPort: Bool {
        guard let port = enteredPort else { return false }
        return AppConfig.WebServer.isValidPort(port)
    }

    private var localIPAddress: String {
        // Get local IP address for display
        var address = "unknown"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return address
        }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            guard (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING),
                  addr.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                          &hostname, socklen_t(hostname.count),
                          nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: hostname)
                break
            }
        }
        return address
    }

    var body: some View {
        Form {
            Section("Server Status") {
                LabeledContent("Status") {
                    HStack {
                        Circle()
                            .fill(isServerRunning ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(isServerRunning ? "Running" : "Stopped")
                    }
                }

                LabeledContent("URL") {
                    if isServerRunning {
                        VStack(alignment: .trailing, spacing: 4) {
                            Link("http://127.0.0.1:\(currentPort)",
                                 destination: URL(string: "http://127.0.0.1:\(currentPort)")!)
                                .font(.caption)
                            if allowRemoteAccess {
                                Link("http://\(localIPAddress):\(currentPort)",
                                     destination: URL(string: "http://\(localIPAddress):\(currentPort)")!)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Port Configuration") {
                HStack {
                    TextField("Port", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: portText) { _, newValue in
                            // Only allow numeric input
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue {
                                portText = filtered
                            }
                            checkPortChanged()
                        }

                    if !isValidPort && !portText.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help("Port must be between 1024 and 65535")
                    } else if portChanged && isValidPort {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.blue)
                            .help("Restart required to apply changes")
                    }
                }

                Text("Valid range: 1024 - 65535 (default: \(AppConfig.WebServer.defaultPort))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Save & Restart") {
                        saveAndRestart()
                    }
                    .disabled(!isValidPort || !portChanged || isRestarting)

                    Button("Reset to Default") {
                        resetToDefault()
                    }
                    .disabled(currentPort == AppConfig.WebServer.defaultPort && !portChanged)

                    if isRestarting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.leading, 8)
                    }
                }
            }

            Section("Remote Access") {
                Toggle("Allow Remote Access", isOn: $allowRemoteAccess)
                    .onChange(of: allowRemoteAccess) { _, newValue in
                        checkRemoteAccessChanged(newValue)
                    }

                if allowRemoteAccess {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Server will be accessible from other devices on the local network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if remoteAccessChanged {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.blue)
                        Text("Restart required to apply changes")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    Button("Save & Restart") {
                        saveRemoteAccessAndRestart()
                    }
                    .disabled(isRestarting)
                }

                Text("When enabled, the REST API binds to 0.0.0.0, allowing access from other devices. When disabled, it binds to 127.0.0.1 (localhost only).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Server Control") {
                HStack {
                    Button(isServerRunning ? "Stop Server" : "Start Server") {
                        toggleServer()
                    }
                    .disabled(isRestarting)

                    Button("Restart Server") {
                        restartServer()
                    }
                    .disabled(!isServerRunning || isRestarting)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            loadSettings()
            await loadRemoteAccessSetting()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func loadSettings() {
        currentPort = AppConfig.WebServer.port
        portText = "\(currentPort)"
        isServerRunning = container.webServerManager.status == .running
        portChanged = false
    }

    private func checkPortChanged() {
        guard let port = enteredPort else {
            portChanged = false
            return
        }
        portChanged = port != currentPort
    }

    private func saveAndRestart() {
        guard let port = enteredPort, isValidPort else { return }

        isRestarting = true

        // Save to UserDefaults
        AppConfig.WebServer.setPort(port)
        currentPort = port
        portChanged = false

        // Restart server
        AsyncTask {
            do {
                await container.webServerManager.stop()
                try await AsyncTask.sleep(nanoseconds: 500_000_000)
                try await container.webServerManager.start()
                await MainActor.run {
                    isServerRunning = container.webServerManager.status == .running
                    isRestarting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to restart server: \(error.localizedDescription)"
                    showError = true
                    isRestarting = false
                    isServerRunning = container.webServerManager.status == .running
                }
            }
        }
    }

    private func resetToDefault() {
        AppConfig.WebServer.resetPort()
        currentPort = AppConfig.WebServer.defaultPort
        portText = "\(currentPort)"
        portChanged = false

        // Restart if running
        if isServerRunning {
            restartServer()
        }
    }

    private func toggleServer() {
        isRestarting = true

        AsyncTask {
            do {
                if isServerRunning {
                    await container.webServerManager.stop()
                } else {
                    try await container.webServerManager.start()
                }
                await MainActor.run {
                    isServerRunning = container.webServerManager.status == .running
                    isRestarting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to \(isServerRunning ? "stop" : "start") server: \(error.localizedDescription)"
                    showError = true
                    isRestarting = false
                }
            }
        }
    }

    private func restartServer() {
        isRestarting = true

        AsyncTask {
            do {
                try await container.webServerManager.restart()
                await MainActor.run {
                    isServerRunning = container.webServerManager.status == .running
                    isRestarting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to restart server: \(error.localizedDescription)"
                    showError = true
                    isRestarting = false
                    isServerRunning = container.webServerManager.status == .running
                }
            }
        }
    }

    // MARK: - Remote Access Settings

    @MainActor
    private func loadRemoteAccessSetting() async {
        do {
            let settings = try container.appSettingsRepository.get()
            allowRemoteAccess = settings.allowRemoteAccess
            remoteAccessChanged = false
        } catch {
            NSLog("[WebServerSettingsView] Failed to load remote access setting: \(error)")
        }
    }

    private func checkRemoteAccessChanged(_ newValue: Bool) {
        AsyncTask {
            do {
                let settings = try container.appSettingsRepository.get()
                await MainActor.run {
                    remoteAccessChanged = newValue != settings.allowRemoteAccess
                }
            } catch {
                NSLog("[WebServerSettingsView] Failed to check remote access setting: \(error)")
            }
        }
    }

    private func saveRemoteAccessAndRestart() {
        isRestarting = true

        AsyncTask {
            do {
                // Save the setting
                var settings = try container.appSettingsRepository.get()
                settings = settings.withAllowRemoteAccess(allowRemoteAccess)
                try container.appSettingsRepository.save(settings)

                // Restart server
                await container.webServerManager.stop()
                try await AsyncTask.sleep(nanoseconds: 500_000_000)
                try await container.webServerManager.start()

                await MainActor.run {
                    isServerRunning = container.webServerManager.status == .running
                    isRestarting = false
                    remoteAccessChanged = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save and restart: \(error.localizedDescription)"
                    showError = true
                    isRestarting = false
                    isServerRunning = container.webServerManager.status == .running
                }
            }
        }
    }
}
