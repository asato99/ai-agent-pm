// Sources/App/Features/MCPServer/MCPServerRowView.swift
// サイドバー用MCPサーバー行表示

import SwiftUI

/// サイドバーに表示するMCPサーバー状態行
public struct MCPServerRowView: View {

    // MARK: - Properties

    @ObservedObject var daemonManager: MCPDaemonManager

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text("MCP Server")

            Spacer()

            if daemonManager.status == .running {
                Text(formattedUptime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("MCPServerRow")
    }

    // MARK: - Computed Properties

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

    private var formattedUptime: String {
        let minutes = Int(daemonManager.uptime) / 60
        let seconds = Int(daemonManager.uptime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    MCPServerRowView(daemonManager: MCPDaemonManager())
        .frame(width: 200)
        .padding()
}
