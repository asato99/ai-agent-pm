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

        // エージェントとパスキーの情報を取得
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
