// Sources/App/Features/Settings/MCPSettingsView.swift
// MCPサーバー設定タブ

import SwiftUI
import AppKit
import Domain
import Infrastructure
import UseCase

// Swift.Task と Domain.Task の名前衝突を解決
private typealias AsyncTask = _Concurrency.Task

struct MCPSettingsView: View {
    @EnvironmentObject var container: DependencyContainer

    @State private var mcpServerPath: String = ""
    @State private var isServerRunning = false
    @State private var coordinatorToken: String = ""
    @State private var isTokenVisible = false
    @State private var isLoading = false
    @State private var showCopiedToast = false
    @State private var pendingPurposeTTLSeconds: Int = 300
    @State private var showExportSheet = false

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
                    showExportSheet = true
                }
                .help("Export coordinator.yaml for the Runner/Coordinator")

                Text("Exports a YAML configuration file for the Coordinator with all agent passkeys and settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showExportSheet) {
                CoordinatorExportSheet()
                    .environmentObject(container)
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
}
