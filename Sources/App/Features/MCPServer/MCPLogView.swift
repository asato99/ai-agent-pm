// Sources/App/Features/MCPServer/MCPLogView.swift
// MCPデーモンログビューア

import SwiftUI

/// MCPデーモンログビューア
public struct MCPLogView: View {

    // MARK: - Properties

    @ObservedObject var daemonManager: MCPDaemonManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var filterLevel: LogLevel = .all

    // MARK: - Log Level

    enum LogLevel: String, CaseIterable {
        case all = "All"
        case error = "Error"
        case warning = "Warning"
        case info = "Info"
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logContent
        }
        .frame(minWidth: 700, minHeight: 500)
        .accessibilityIdentifier("MCPLogView")
        .onAppear {
            daemonManager.refreshLogs()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text("MCP Server Logs")
                .font(.headline)

            Spacer()

            searchField

            filterPicker

            autoScrollToggle

            refreshButton

            closeButton
        }
        .padding()
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search logs...", text: $searchText)
                .textFieldStyle(.plain)
                .frame(width: 150)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
        .accessibilityIdentifier("LogSearchField")
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $filterLevel) {
            ForEach(LogLevel.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 100)
    }

    private var autoScrollToggle: some View {
        Toggle(isOn: $autoScroll) {
            Label("Auto-scroll", systemImage: "arrow.down.to.line")
        }
        .toggleStyle(.button)
        .accessibilityIdentifier("AutoScrollToggle")
    }

    private var refreshButton: some View {
        Button {
            daemonManager.refreshLogs()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("Refresh logs")
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(.escape, modifiers: [])
    }

    // MARK: - Log Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, line in
                        logLine(line)
                            .id(index)
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: daemonManager.lastLogLines.count) { _, _ in
                if autoScroll, let lastIndex = filteredLogs.indices.last {
                    withAnimation {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var filteredLogs: [String] {
        var logs = daemonManager.lastLogLines

        // Apply level filter
        if filterLevel != .all {
            logs = logs.filter { line in
                switch filterLevel {
                case .error:
                    return line.lowercased().contains("error")
                case .warning:
                    return line.lowercased().contains("warning") || line.lowercased().contains("warn")
                case .info:
                    return line.lowercased().contains("info")
                case .all:
                    return true
                }
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            logs = logs.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }

        return logs
    }

    private func logLine(_ line: String) -> some View {
        Text(line)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(logLineColor(for: line))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func logLineColor(for line: String) -> Color {
        let lowercased = line.lowercased()
        if lowercased.contains("error") {
            return .red
        } else if lowercased.contains("warning") || lowercased.contains("warn") {
            return .orange
        } else if lowercased.contains("daemon") || lowercased.contains("started") || lowercased.contains("stopped") {
            return .blue
        }
        return .primary
    }
}

// MARK: - Preview

#Preview {
    MCPLogView(daemonManager: MCPDaemonManager())
}
