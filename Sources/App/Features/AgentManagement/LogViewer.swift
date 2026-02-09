// Sources/App/Features/AgentManagement/LogViewer.swift
// 実行ログ詳細行・ログビューアシート

import SwiftUI
import Domain

// MARK: - ExecutionLogDetailRow (Enhanced)

/// 実行履歴タブ用の詳細行（プロジェクト名、タスクタイトル、ログを開くボタン付き）
struct ExecutionLogDetailRow: View {
    let log: ExecutionLog
    let task: Task?
    let project: Project?
    let onOpenLog: () -> Void

    private var statusColor: Color {
        switch log.status {
        case .running: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var statusIcon: String {
        switch log.status {
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var durationText: String {
        guard let duration = log.durationSeconds else { return "" }
        if duration < 60 {
            return String(format: "%.0f秒", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)分\(seconds)秒"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)時間\(minutes)分"
        }
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var text = formatter.string(from: log.startedAt)
        if let completedAt = log.completedAt {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss"
            text += " - " + timeFormatter.string(from: completedAt)
        }
        if !durationText.isEmpty {
            text += " (\(durationText))"
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with time range
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title3)

                Text(timeRangeText)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(log.status.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            // Project info
            if let project = project {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("プロジェクト: \(project.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Task info
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let task = task {
                    Text("タスク: \(log.taskId.value.prefix(12))... \(task.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("タスク: \(log.taskId.value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Error message if any
            if let error = log.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            // Open Log button
            if log.logFilePath != nil {
                Button(action: onOpenLog) {
                    Label("ログを開く", systemImage: "doc.text")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("OpenLogButton_\(log.id.value)")
            } else {
                Text("ログファイルなし")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - LogViewerSheet

/// ログファイルの内容を表示するシート
struct LogViewerSheet: View {
    let log: ExecutionLog
    let task: Task?
    let project: Project?
    let agent: Agent?

    @Environment(\.dismiss) private var dismiss
    @State private var logContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isWordWrapEnabled = true

    private var filteredContent: String {
        guard !searchText.isEmpty else { return logContent }
        // 簡易的なハイライト（実際の検索）
        return logContent
    }

    private var durationText: String {
        guard let duration = log.durationSeconds else { return "-" }
        if duration < 60 {
            return String(format: "%.1f秒", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)分\(seconds)秒"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)時間\(minutes)分"
        }
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var text = formatter.string(from: log.startedAt)
        if let completedAt = log.completedAt {
            text += " - " + formatter.string(from: completedAt)
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("実行ログ")
                    .font(.headline)
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
                .accessibilityIdentifier("CloseLogViewerButton")
            }
            .padding()

            Divider()

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                if let agent = agent {
                    HStack {
                        Text("エージェント:")
                            .foregroundStyle(.secondary)
                        Text(agent.name)
                    }
                    .font(.caption)
                }

                if let task = task {
                    HStack {
                        Text("タスク:")
                            .foregroundStyle(.secondary)
                        Text("\(log.taskId.value.prefix(12))... \(task.title)")
                            .lineLimit(1)
                    }
                    .font(.caption)
                }

                if let project = project {
                    HStack {
                        Text("プロジェクト:")
                            .foregroundStyle(.secondary)
                        Text(project.name)
                    }
                    .font(.caption)
                }

                HStack {
                    Text("実行期間:")
                        .foregroundStyle(.secondary)
                    Text("\(timeRangeText) (\(durationText))")
                }
                .font(.caption)

                HStack {
                    Text("結果:")
                        .foregroundStyle(.secondary)
                    Text(log.status.rawValue)
                        .foregroundStyle(log.status == .completed ? .green : (log.status == .failed ? .red : .orange))
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // Search and options
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("検索...", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("LogSearchField")

                Spacer()

                Toggle(isOn: $isWordWrapEnabled) {
                    Text("折り返し")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("WordWrapToggle")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Log content
            Group {
                if isLoading {
                    ProgressView("ログを読み込み中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        "ログを読み込めません",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        Text(filteredContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: isWordWrapEnabled ? .infinity : nil, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding()
                    }
                    .accessibilityIdentifier("LogContentScrollView")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
        .task {
            await loadLogContent()
        }
    }

    private func loadLogContent() async {
        guard let path = log.logFilePath else {
            errorMessage = "ログファイルパスが設定されていません"
            isLoading = false
            return
        }

        do {
            let url = URL(fileURLWithPath: path)
            let content = try String(contentsOf: url, encoding: .utf8)
            logContent = content
            isLoading = false
        } catch {
            errorMessage = "ファイルを読み込めませんでした: \(error.localizedDescription)"
            isLoading = false
        }
    }
}
