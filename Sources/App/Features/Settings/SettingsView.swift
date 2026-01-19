// Sources/App/Features/Settings/SettingsView.swift
// 設定ビュー

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Domain
import Infrastructure

// Swift.Task と Domain.Task の名前衝突を解決
private typealias AsyncTask = _Concurrency.Task

struct SettingsView: View {
    @EnvironmentObject var container: DependencyContainer

    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("showCompletedTasks") private var showCompletedTasks = true
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval = 30

    var body: some View {
        TabView {
            GeneralSettingsView(
                appearance: $appearance,
                showCompletedTasks: $showCompletedTasks,
                autoRefreshInterval: $autoRefreshInterval
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            DatabaseSettingsView()
            .tabItem {
                Label("Database", systemImage: "internaldrive")
            }

            WebServerSettingsView()
            .tabItem {
                Label("Web Server", systemImage: "network")
            }

            MCPSettingsView()
            .tabItem {
                Label("MCP Server", systemImage: "server.rack")
            }

            AboutView()
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 500, height: 450)
    }
}

// MARK: - Appearance Enum

enum AppAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Binding var appearance: AppAppearance
    @Binding var showCompletedTasks: Bool
    @Binding var autoRefreshInterval: Int

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Task Board") {
                Toggle("Show completed tasks", isOn: $showCompletedTasks)

                Picker("Auto-refresh interval", selection: $autoRefreshInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("Never").tag(0)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Database Settings

struct DatabaseSettingsView: View {
    @State private var databasePath: String = ""
    @State private var databaseSize: String = "Unknown"

    var body: some View {
        Form {
            Section("Database Location") {
                LabeledContent("Path") {
                    Text(databasePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Size") {
                    Text(databaseSize)
                }

                Button("Reveal in Finder") {
                    revealInFinder()
                }
            }

            Section("Maintenance") {
                Button("Optimize Database") {
                    optimizeDatabase()
                }

                Button("Export Data...") {
                    exportData()
                }

                Button("Import Data...") {
                    importData()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            loadDatabaseInfo()
        }
    }

    private func loadDatabaseInfo() {
        // AppConfigから統一されたDBパスを取得
        databasePath = AppConfig.databasePath

        if let attributes = try? FileManager.default.attributesOfItem(atPath: databasePath),
           let size = attributes[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            databaseSize = formatter.string(fromByteCount: size)
        }
    }

    private func revealInFinder() {
        if let url = URL(string: "file://\(databasePath)") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func optimizeDatabase() {
        // TODO: Implement database optimization (VACUUM)
    }

    private func exportData() {
        // TODO: Implement data export
    }

    private func importData() {
        // TODO: Implement data import
    }
}

// MARK: - Web Server Settings

struct WebServerSettingsView: View {
    @EnvironmentObject var container: DependencyContainer

    @State private var portText: String = ""
    @State private var currentPort: Int = AppConfig.WebServer.defaultPort
    @State private var isServerRunning = false
    @State private var isRestarting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var portChanged = false

    private var enteredPort: Int? {
        Int(portText)
    }

    private var isValidPort: Bool {
        guard let port = enteredPort else { return false }
        return AppConfig.WebServer.isValidPort(port)
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
                        Link("http://127.0.0.1:\(currentPort)",
                             destination: URL(string: "http://127.0.0.1:\(currentPort)")!)
                            .font(.caption)
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
}

// MARK: - MCP Settings

struct MCPSettingsView: View {
    @EnvironmentObject var container: DependencyContainer

    @State private var mcpServerPath: String = ""
    @State private var isServerRunning = false
    @State private var coordinatorToken: String = ""
    @State private var isTokenVisible = false
    @State private var isLoading = false
    @State private var showCopiedToast = false
    @State private var pendingPurposeTTLSeconds: Int = 300

    var body: some View {
        Form {
            Section("MCP Server") {
                LabeledContent("Executable") {
                    Text(mcpServerPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Status") {
                    HStack {
                        Circle()
                            .fill(isServerRunning ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(isServerRunning ? "Running" : "Stopped")
                    }
                }
            }

            Section("Coordinator Token") {
                coordinatorTokenSection
            }

            Section("Agent Startup Timeout") {
                agentStartupTimeoutSection
            }

            Section("Coordinator Configuration") {
                Button("Export Coordinator Config...") {
                    exportCoordinatorConfig()
                }
                .help("Export coordinator.yaml for the Runner/Coordinator")

                Text("Exports a YAML configuration file for the Coordinator with all agent passkeys and settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude Code Configuration") {
                Button("Copy Claude Code Config") {
                    copyClaudeCodeConfig()
                }
                .help("Copy the configuration to add this MCP server to Claude Code")

                Button("Open Documentation") {
                    openDocumentation()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            loadMCPInfo()
            await loadCoordinatorToken()
        }
        .overlay {
            if showCopiedToast {
                VStack {
                    Spacer()
                    Text("Copied to clipboard")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                }
            }
        }
    }

    @ViewBuilder
    private var coordinatorTokenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if coordinatorToken.isEmpty {
                Text("No token configured")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                HStack {
                    if isTokenVisible {
                        Text(coordinatorToken)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text(String(repeating: "•", count: min(coordinatorToken.count, 32)))
                            .font(.system(.caption, design: .monospaced))
                    }

                    Spacer()

                    Button {
                        isTokenVisible.toggle()
                    } label: {
                        Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(isTokenVisible ? "Hide token" : "Show token")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(coordinatorToken, forType: .string)
                        showCopiedToast = true
                        AsyncTask {
                            try? await AsyncTask.sleep(nanoseconds: 2_000_000_000)
                            showCopiedToast = false
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy token to clipboard")
                }
            }

            HStack {
                Button(coordinatorToken.isEmpty ? "Generate Token" : "Regenerate Token") {
                    AsyncTask { await regenerateToken() }
                }
                .disabled(isLoading)

                if !coordinatorToken.isEmpty {
                    Button("Clear Token", role: .destructive) {
                        AsyncTask { await clearToken() }
                    }
                    .disabled(isLoading)
                }
            }

            Text("This token authenticates the Coordinator with the MCP daemon. Regenerating will require updating the Coordinator configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var agentStartupTimeoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Timeout", selection: $pendingPurposeTTLSeconds) {
                Text("1 minute").tag(60)
                Text("2 minutes").tag(120)
                Text("5 minutes (default)").tag(300)
                Text("10 minutes").tag(600)
                Text("30 minutes").tag(1800)
            }
            .onChange(of: pendingPurposeTTLSeconds) { _, newValue in
                AsyncTask { await saveTTLSetting(newValue) }
            }

            Text("Time to wait for an agent to complete authentication after receiving a chat message. If the agent doesn't authenticate within this time, the pending request expires.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadMCPInfo() {
        // Get the path to the MCP server executable
        let bundle = Bundle.main
        if let executableURL = bundle.executableURL {
            let mcpPath = executableURL
                .deletingLastPathComponent()
                .appendingPathComponent("mcp-server-pm")
            mcpServerPath = mcpPath.path
        }
        isServerRunning = container.mcpDaemonManager.status == .running
    }

    @MainActor
    private func loadCoordinatorToken() async {
        let repo = container.appSettingsRepository
        do {
            let settings = try repo.get()
            coordinatorToken = settings.coordinatorToken ?? ""
            pendingPurposeTTLSeconds = settings.pendingPurposeTTLSeconds
        } catch {
            NSLog("[MCPSettingsView] Failed to load settings: \(error)")
        }
    }

    @MainActor
    private func saveTTLSetting(_ ttlSeconds: Int) async {
        let repo = container.appSettingsRepository
        do {
            var settings = try repo.get()
            settings = settings.withPendingPurposeTTL(ttlSeconds)
            try repo.save(settings)
            NSLog("[MCPSettingsView] TTL setting saved: \(ttlSeconds) seconds")
        } catch {
            NSLog("[MCPSettingsView] Failed to save TTL setting: \(error)")
        }
    }

    @MainActor
    private func regenerateToken() async {
        isLoading = true
        defer { isLoading = false }

        let repo = container.appSettingsRepository
        do {
            var settings = try repo.get()
            settings = settings.regenerateCoordinatorToken()
            try repo.save(settings)
            coordinatorToken = settings.coordinatorToken ?? ""
        } catch {
            NSLog("[MCPSettingsView] Failed to regenerate token: \(error)")
        }
    }

    @MainActor
    private func clearToken() async {
        isLoading = true
        defer { isLoading = false }

        let repo = container.appSettingsRepository
        do {
            var settings = try repo.get()
            settings = settings.clearCoordinatorToken()
            try repo.save(settings)
            coordinatorToken = ""
        } catch {
            NSLog("[MCPSettingsView] Failed to clear token: \(error)")
        }
    }

    private func copyClaudeCodeConfig() {
        let config = """
        {
          "mcpServers": {
            "pm": {
              "command": "\(mcpServerPath)",
              "args": ["--project-id", "<PROJECT_ID>", "--agent-id", "<AGENT_ID>"]
            }
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }

    private func openDocumentation() {
        if let url = URL(string: "https://github.com/anthropics/claude-code") {
            NSWorkspace.shared.open(url)
        }
    }

    private func exportCoordinatorConfig() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Coordinator Configuration"
        savePanel.nameFieldStringValue = "coordinator.yaml"
        savePanel.allowedContentTypes = [.yaml]
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            let exporter = CoordinatorConfigExporter(
                agentRepository: container.agentRepository,
                agentCredentialRepository: container.agentCredentialRepository,
                appSettingsRepository: container.appSettingsRepository
            )

            do {
                try exporter.exportToFile(url: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSLog("[MCPSettingsView] Failed to export coordinator config: \(error)")
            }
        }
    }
}

// MARK: - Coordinator Config Exporter

/// Coordinator設定ファイルをエクスポートするサービス
private struct CoordinatorConfigExporter {
    let agentRepository: AgentRepositoryProtocol
    let agentCredentialRepository: AgentCredentialRepositoryProtocol
    let appSettingsRepository: AppSettingsRepository

    /// 設定ファイルの内容を生成
    func generateConfig() throws -> String {
        // 設定を取得
        let settings = try appSettingsRepository.get()
        let coordinatorToken = settings.coordinatorToken ?? ""

        // 全エージェントを取得
        let agents = try agentRepository.findAll()

        // エージェントとパスキーの情報を取得 (AgentCredential.rawPasskey)
        var agentCredentials: [(AgentID, String?)] = []
        for agent in agents {
            let credential = try? agentCredentialRepository.findByAgentId(agent.id)
            agentCredentials.append((agent.id, credential?.rawPasskey))
        }

        // MCPソケットパス
        let socketPath = "~/Library/Application Support/AIAgentPM/mcp.sock"

        // YAML生成
        var yaml = """
        # Coordinator Configuration
        # Generated by AI Agent PM
        # Date: \(ISO8601DateFormatter().string(from: Date()))

        polling_interval: 2
        max_concurrent: 3

        """

        // Coordinator Token
        if !coordinatorToken.isEmpty {
            yaml += """
            # Coordinator authentication token
            coordinator_token: \(coordinatorToken)

            """
        } else {
            yaml += """
            # Coordinator authentication token (not configured)
            # coordinator_token: <GENERATE_IN_SETTINGS>

            """
        }

        // MCP Socket Path
        yaml += """
        # MCP server socket path
        mcp_socket_path: \(socketPath)

        # AI providers configuration
        ai_providers:
          claude:
            cli_command: claude
            cli_args:
              - "--dangerously-skip-permissions"
              - "--max-turns"
              - "50"

          gemini:
            cli_command: gemini
            cli_args:
              - "-y"

        # Agent credentials
        agents:

        """

        if agentCredentials.isEmpty {
            yaml += "  # No agents configured\n"
        } else {
            for (agentId, rawPasskey) in agentCredentials {
                if let passkey = rawPasskey {
                    yaml += "  \(agentId.value):\n"
                    yaml += "    passkey: \(passkey)\n"
                } else {
                    yaml += "  # \(agentId.value): (no passkey configured)\n"
                }
            }
        }

        yaml += """

        # Log directory
        log_directory: ~/Library/Logs/AIAgentPM/coordinator

        """

        return yaml
    }

    /// 設定ファイルを指定パスに保存
    func exportToFile(url: URL) throws {
        let content = try generateConfig()
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("AI Agent PM")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 0.2.0")
                .foregroundStyle(.secondary)

            Text("Project management for AI agents with MCP integration")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            Link("GitHub Repository", destination: URL(string: "https://github.com/example/ai-agent-pm")!)

            Text("© 2024 AI Agent PM")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}
