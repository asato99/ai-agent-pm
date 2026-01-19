// Sources/App/Features/WebServer/WebServerView.swift
// Web Server管理画面

import SwiftUI

/// Web Server管理画面
public struct WebServerView: View {

    // MARK: - Properties

    @ObservedObject var serverManager: WebServerManager
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
        .navigationTitle("Web Server")
        .accessibilityIdentifier("WebServerView")
        .sheet(isPresented: $showingLogs) {
            WebLogView(serverManager: serverManager)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            statusIndicator
            Spacer()
            if serverManager.status == .running {
                Button {
                    openInBrowser()
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .accessibilityIdentifier("OpenInBrowserButton")
            }
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

            if serverManager.status == .running {
                Text("(\(formattedUptime))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityIdentifier("ServerStatusIndicator")
    }

    private var statusColor: Color {
        switch serverManager.status {
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
        switch serverManager.status {
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
        let hours = Int(serverManager.uptime) / 3600
        let minutes = (Int(serverManager.uptime) % 3600) / 60
        let seconds = Int(serverManager.uptime) % 60

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
                infoRow(label: "HTTP Port", value: "\(serverManager.port)")
                if serverManager.status == .running {
                    HStack {
                        Text("URL")
                            .foregroundColor(.secondary)
                        Spacer()
                        Link(serverManager.serverURL, destination: URL(string: serverManager.serverURL)!)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Server Status", systemImage: "globe")
        }
    }

    private var processStatusText: String {
        switch serverManager.status {
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
                        startServer()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(serverManager.status != .stopped && !serverManager.status.isError || isStarting)
                    .accessibilityIdentifier("StartServerButton")

                    Button {
                        stopServer()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(serverManager.status != .running || isStopping)
                    .accessibilityIdentifier("StopServerButton")

                    Button {
                        restartServer()
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(serverManager.status != .running || isStarting || isStopping)
                    .accessibilityIdentifier("RestartServerButton")
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

                pathRow(label: "PID File", path: serverManager.pidPath)
                pathRow(label: "Log File", path: serverManager.logPath)
                pathRow(label: "Web UI Files", path: serverManager.webUIPath)
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
                Text("The Web Server provides a REST API and serves the web-ui dashboard.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                Text("Access the web interface at \(serverManager.serverURL) when the server is running.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } label: {
            Label("About Web Server", systemImage: "info.circle")
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

    private func startServer() {
        isStarting = true
        Task {
            do {
                try await serverManager.start()
            } catch {
                NSLog("[WebServerView] Failed to start server: \(error)")
            }
            isStarting = false
        }
    }

    private func stopServer() {
        isStopping = true
        Task {
            await serverManager.stop()
            isStopping = false
        }
    }

    private func restartServer() {
        isStarting = true
        isStopping = true
        Task {
            do {
                try await serverManager.restart()
            } catch {
                NSLog("[WebServerView] Failed to restart server: \(error)")
            }
            isStarting = false
            isStopping = false
        }
    }

    private func openInBrowser() {
        if let url = URL(string: serverManager.serverURL) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Web Log View

struct WebLogView: View {
    @ObservedObject var serverManager: WebServerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Web Server Logs")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Log content
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(serverManager.lastLogLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding()
                    .onChange(of: serverManager.lastLogLines.count) { _, _ in
                        if let lastIndex = serverManager.lastLogLines.indices.last {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Footer
            HStack {
                Text("\(serverManager.lastLogLines.count) lines")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    serverManager.refreshLogs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            serverManager.refreshLogs()
        }
    }
}

// MARK: - Preview

#Preview {
    WebServerView(serverManager: WebServerManager())
}
