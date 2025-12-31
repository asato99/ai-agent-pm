// Sources/App/Features/Settings/SettingsView.swift
// 設定ビュー

import SwiftUI

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
        .frame(width: 500, height: 350)
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
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dbPath = appSupport
            .appendingPathComponent("AIAgentPM")
            .appendingPathComponent("pm.db")

        databasePath = dbPath.path

        if let attributes = try? FileManager.default.attributesOfItem(atPath: dbPath.path),
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
    @State private var mcpServerPath: String = ""
    @State private var isServerRunning = false

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

            Section("Configuration") {
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
