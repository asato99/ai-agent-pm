// Sources/App/Features/WebServer/WebServerRowView.swift
// サイドバー用Web Server行表示

import SwiftUI

/// サイドバーに表示するWeb Server状態行
public struct WebServerRowView: View {

    // MARK: - Properties

    @ObservedObject var serverManager: WebServerManager

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text("Web Server")

            Spacer()

            if serverManager.status == .running {
                Text(formattedUptime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("WebServerRow")
    }

    // MARK: - Computed Properties

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

    private var formattedUptime: String {
        let minutes = Int(serverManager.uptime) / 60
        let seconds = Int(serverManager.uptime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    WebServerRowView(serverManager: WebServerManager())
        .frame(width: 200)
        .padding()
}
