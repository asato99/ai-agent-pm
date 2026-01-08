// Sources/App/Features/MCPServer/MCPServerView.swift
// MCP Server管理画面

import SwiftUI

/// MCP Server管理画面
public struct MCPServerView: View {

    // MARK: - Properties

    @ObservedObject var daemonManager: MCPDaemonManager
    @State private var showingLogs = false
    @State private var isStarting = false
    @State private var isStopping = false

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                statusSection
                controlsSection
                pathsSection
                infoSection
            }
            .padding()
        }
        .navigationTitle("MCP Server")
        .accessibilityIdentifier("MCPServerView")
        .sheet(isPresented: $showingLogs) {
            MCPLogView(daemonManager: daemonManager)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            statusIndicator
            Spacer()
            Button {
                showingLogs = true
            } label: {
                Label("View Logs", systemImage: "doc.text.magnifyingglass")
            }
            .accessibilityIdentifier("ViewLogsButton")
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(statusText)
                .font(.headline)

            if daemonManager.status == .running {
                Text("(\(formattedUptime))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityIdentifier("DaemonStatusIndicator")
    }

    private var statusColor: Color {
        switch daemonManager.status {
        case .stopped:
            return .gray
        case .starting, .stopping:
            return .orange
        case .running:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch daemonManager.status {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting..."
        case .running:
            return "Running"
        case .stopping:
            return "Stopping..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    private var formattedUptime: String {
        let hours = Int(daemonManager.uptime) / 3600
        let minutes = (Int(daemonManager.uptime) % 3600) / 60
        let seconds = Int(daemonManager.uptime) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Status")
                        .font(.headline)
                    Spacer()
                }

                Divider()

                infoRow(label: "Process", value: processStatusText)
                infoRow(label: "Socket", value: socketStatusText)
            }
            .padding(.vertical, 4)
        } label: {
            Label("Daemon Status", systemImage: "server.rack")
        }
    }

    private var processStatusText: String {
        switch daemonManager.status {
        case .running:
            return "Active"
        case .stopped:
            return "Not running"
        case .starting:
            return "Starting..."
        case .stopping:
            return "Stopping..."
        case .error:
            return "Error"
        }
    }

    private var socketStatusText: String {
        let socketExists = FileManager.default.fileExists(atPath: daemonManager.socketPath)
        return socketExists ? "Connected" : "Not available"
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Controls")
                        .font(.headline)
                    Spacer()
                }

                Divider()

                HStack(spacing: 12) {
                    Button {
                        startDaemon()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(daemonManager.status != .stopped && !daemonManager.status.isError || isStarting)
                    .accessibilityIdentifier("StartDaemonButton")

                    Button {
                        stopDaemon()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(daemonManager.status != .running || isStopping)
                    .accessibilityIdentifier("StopDaemonButton")

                    Button {
                        restartDaemon()
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(daemonManager.status != .running || isStarting || isStopping)
                    .accessibilityIdentifier("RestartDaemonButton")
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Actions", systemImage: "gearshape.2")
        }
    }

    // MARK: - Paths Section

    private var pathsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("File Paths")
                        .font(.headline)
                    Spacer()
                }

                Divider()

                pathRow(label: "Socket", path: daemonManager.socketPath)
                pathRow(label: "PID File", path: daemonManager.pidPath)
                pathRow(label: "Log File", path: daemonManager.logPath)
            }
            .padding(.vertical, 4)
        } label: {
            Label("Configuration", systemImage: "folder")
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("The MCP Server daemon provides a Unix socket interface for AI agents to interact with the task management system.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                Text("Agents connect via the socket to authenticate, receive tasks, and report execution results.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } label: {
            Label("About MCP Server", systemImage: "info.circle")
        }
    }

    // MARK: - Helper Views

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func pathRow(label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    // MARK: - Actions

    private func startDaemon() {
        isStarting = true
        Task {
            do {
                try await daemonManager.start()
            } catch {
                NSLog("[MCPServerView] Failed to start daemon: \(error)")
            }
            isStarting = false
        }
    }

    private func stopDaemon() {
        isStopping = true
        Task {
            await daemonManager.stop()
            isStopping = false
        }
    }

    private func restartDaemon() {
        isStarting = true
        isStopping = true
        Task {
            do {
                try await daemonManager.restart()
            } catch {
                NSLog("[MCPServerView] Failed to restart daemon: \(error)")
            }
            isStarting = false
            isStopping = false
        }
    }
}

// MARK: - Preview

#Preview {
    MCPServerView(daemonManager: MCPDaemonManager())
}
