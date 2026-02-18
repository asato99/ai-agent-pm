// Sources/App/Features/Settings/SettingsView.swift
// 設定ビュー（タブコンテナ）
// 各タブの実装: DatabaseSettingsView, WebServerSettingsView, MCPSettingsView, CoordinatorExport

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

            WebServerSettingsView()
            .tabItem {
                Label("Web Server", systemImage: "network")
            }

            MCPSettingsView()
            .tabItem {
                Label("MCP Server", systemImage: "server.rack")
            }

            SkillManagementView()
            .tabItem {
                Label("Skills", systemImage: "wand.and.stars")
            }

            AboutView()
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 550, height: 500)
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
    @EnvironmentObject var container: DependencyContainer
    @Binding var appearance: AppAppearance
    @Binding var showCompletedTasks: Bool
    @Binding var autoRefreshInterval: Int

    @State private var basePromptText: String = ""
    @State private var savedBasePromptText: String = ""
    @State private var isSaving = false

    private var hasChanges: Bool {
        basePromptText != savedBasePromptText
    }

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

            Section("Agent Base Prompt") {
                TextEditor(text: $basePromptText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                HStack {
                    Button("Save") {
                        Task { await saveBasePrompt() }
                    }
                    .disabled(!hasChanges || isSaving)

                    if !savedBasePromptText.isEmpty {
                        Button("Clear", role: .destructive) {
                            Task { await clearBasePrompt() }
                        }
                        .disabled(isSaving)
                    }

                    Spacer()

                    Text("\(basePromptText.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("A base prompt applied to all agents when started by the Coordinator. Use this to define shared instructions, policies, or behavioral guidelines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await loadBasePrompt()
        }
    }

    @MainActor
    private func loadBasePrompt() async {
        let repo = container.appSettingsRepository
        do {
            let settings = try repo.get()
            let prompt = settings.agentBasePrompt ?? ""
            basePromptText = prompt
            savedBasePromptText = prompt
        } catch {
            NSLog("[GeneralSettingsView] Failed to load base prompt: \(error)")
        }
    }

    @MainActor
    private func saveBasePrompt() async {
        isSaving = true
        defer { isSaving = false }

        let repo = container.appSettingsRepository
        do {
            var settings = try repo.get()
            let prompt = basePromptText.isEmpty ? nil : basePromptText
            settings = settings.withAgentBasePrompt(prompt)
            try repo.save(settings)
            savedBasePromptText = basePromptText
            NSLog("[GeneralSettingsView] Base prompt saved (\(basePromptText.count) chars)")
        } catch {
            NSLog("[GeneralSettingsView] Failed to save base prompt: \(error)")
        }
    }

    @MainActor
    private func clearBasePrompt() async {
        isSaving = true
        defer { isSaving = false }

        let repo = container.appSettingsRepository
        do {
            var settings = try repo.get()
            settings = settings.withAgentBasePrompt(nil)
            try repo.save(settings)
            basePromptText = ""
            savedBasePromptText = ""
            NSLog("[GeneralSettingsView] Base prompt cleared")
        } catch {
            NSLog("[GeneralSettingsView] Failed to clear base prompt: \(error)")
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
