// Sources/App/Features/Settings/CoordinatorExport.swift
// Coordinator設定エクスポート
// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ3.2

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Domain
import Infrastructure
import UseCase

// MARK: - Coordinator Export Sheet

/// Coordinator設定エクスポートシート
struct CoordinatorExportSheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var humanAgents: [Agent] = []
    @State private var selectedAgentId: AgentID?
    @State private var managedAgents: [Agent] = []
    @State private var isExporting = false
    @State private var exportAll = true

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Coordinator Configuration")
                .font(.headline)

            Form {
                Section("Export Scope") {
                    Picker("Scope", selection: $exportAll) {
                        Text("All Agents").tag(true)
                        Text("Specific Human Agent's Scope").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: exportAll) { _, newValue in
                        if newValue {
                            selectedAgentId = nil
                            managedAgents = []
                        }
                    }

                    if !exportAll {
                        Picker("Root Agent", selection: $selectedAgentId) {
                            Text("Select a human agent...").tag(nil as AgentID?)
                            ForEach(humanAgents, id: \.id) { agent in
                                Text("\(agent.name) (\(agent.id.value))").tag(agent.id as AgentID?)
                            }
                        }
                        .onChange(of: selectedAgentId) { _, newValue in
                            loadManagedAgents(for: newValue)
                        }

                        if !managedAgents.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Managed AI Agents:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                ForEach(managedAgents, id: \.id) { agent in
                                    HStack {
                                        Circle()
                                            .fill(.blue)
                                            .frame(width: 6, height: 6)
                                        Text(agent.name)
                                            .font(.caption)
                                        Text("(\(agent.id.value))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        } else if selectedAgentId != nil {
                            Text("No managed AI agents found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export...") {
                    exportConfig()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!exportAll && selectedAgentId == nil)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
        .padding()
        .task {
            loadHumanAgents()
        }
    }

    private func loadHumanAgents() {
        do {
            let allAgents = try container.agentRepository.findByType(.human)
            humanAgents = allAgents.sorted { $0.name < $1.name }
        } catch {
            NSLog("[CoordinatorExportSheet] Failed to load human agents: \(error)")
        }
    }

    private func loadManagedAgents(for agentId: AgentID?) {
        guard let agentId = agentId else {
            managedAgents = []
            return
        }

        do {
            let useCase = GetManagedAgentsUseCase(agentRepository: container.agentRepository)
            managedAgents = try useCase.execute(rootAgentId: agentId)
        } catch {
            NSLog("[CoordinatorExportSheet] Failed to load managed agents: \(error)")
            managedAgents = []
        }
    }

    private func exportConfig() {
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
                try exporter.exportToFile(
                    url: url,
                    rootAgentId: exportAll ? nil : selectedAgentId,
                    managedAgents: exportAll ? nil : managedAgents
                )
                NSWorkspace.shared.activateFileViewerSelecting([url])
                dismiss()
            } catch {
                NSLog("[CoordinatorExportSheet] Failed to export coordinator config: \(error)")
            }
        }
    }
}

// MARK: - Coordinator Config Exporter

/// Coordinator設定ファイルをエクスポートするサービス
/// Phase 3.2: root_agent_id対応
private struct CoordinatorConfigExporter {
    let agentRepository: AgentRepositoryProtocol
    let agentCredentialRepository: AgentCredentialRepositoryProtocol
    let appSettingsRepository: AppSettingsRepository

    /// ローカルIPアドレスを取得
    private var localIPAddress: String {
        var address = "localhost"
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

    /// 設定ファイルの内容を生成
    /// - Parameters:
    ///   - rootAgentId: 起点となるhumanエージェントのID（nilの場合は全エージェント）
    ///   - managedAgents: 管轄AIエージェント（rootAgentIdが指定されている場合に使用）
    func generateConfig(rootAgentId: AgentID? = nil, managedAgents: [Agent]? = nil) throws -> String {
        // 設定を取得
        let settings = try appSettingsRepository.get()
        let coordinatorToken = settings.coordinatorToken ?? ""

        // エクスポート対象のエージェントを決定
        let targetAgents: [Agent]
        if let managedAgents = managedAgents {
            targetAgents = managedAgents
        } else {
            targetAgents = try agentRepository.findAll()
        }

        // エージェントとパスキーの情報を取得 (AgentCredential.rawPasskey)
        var agentCredentials: [(AgentID, String?)] = []
        for agent in targetAgents {
            let credential = try? agentCredentialRepository.findByAgentId(agent.id)
            agentCredentials.append((agent.id, credential?.rawPasskey))
        }

        // MCPソケットパス/URL
        // rootAgentIdが指定されている場合（humanエージェント起点のマルチデバイス運用）はHTTP URLを使用
        // そうでない場合はUnixソケットを使用
        let mcpConnectionPath: String
        if rootAgentId != nil {
            // マルチデバイス運用: HTTP経由でRESTサーバーに接続
            let port = AppConfig.WebServer.port
            mcpConnectionPath = "http://\(localIPAddress):\(port)/mcp"
        } else {
            // ローカル運用: Unixソケット経由でMCPデーモンに接続
            mcpConnectionPath = "~/Library/Application Support/AIAgentPM/mcp.sock"
        }

        // YAML生成
        var yaml = """
        # Coordinator Configuration
        # Generated by AI Agent PM
        # Date: \(ISO8601DateFormatter().string(from: Date()))

        polling_interval: 2
        max_concurrent: 3

        """

        // Phase 3.2: Root Agent ID（指定されている場合）
        if let rootAgentId = rootAgentId {
            yaml += """
            # Root agent for multi-device operation
            root_agent_id: \(rootAgentId.value)

            """
        }

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

        // MCP Socket Path / URL
        yaml += """
        # MCP server connection path
        # - Unix socket: ~/Library/Application Support/AIAgentPM/mcp.sock (local)
        # - HTTP URL: http://<hostname>:<port>/mcp (remote/multi-device)
        mcp_socket_path: \(mcpConnectionPath)

        # AI providers configuration
        ai_providers:
          claude:
            cli_command: claude
            cli_args:
              - "--dangerously-skip-permissions"
              - "--max-turns"
              - "50"
              - "--verbose"

          gemini:
            cli_command: gemini
            cli_args:
              - "-y"
              - "-d"

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
    func exportToFile(url: URL, rootAgentId: AgentID? = nil, managedAgents: [Agent]? = nil) throws {
        let content = try generateConfig(rootAgentId: rootAgentId, managedAgents: managedAgents)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
