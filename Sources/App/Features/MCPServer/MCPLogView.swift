// Sources/App/Features/MCPServer/MCPLogView.swift
// MCPデーモンログビューア

import SwiftUI
import Infrastructure

/// MCPデーモンログビューア
public struct MCPLogView: View {

    // MARK: - Properties

    @ObservedObject var daemonManager: MCPDaemonManager
    @Environment(\.dismiss) private var dismiss
    @State private var autoScroll = true

    /// ログフィルタリング用ViewModel
    @State private var viewModel = MCPLogViewModel()

    /// 選択されたレベルフィルタ（空=全て表示）
    @State private var selectedLevels: Set<LogLevel> = []

    /// 選択されたカテゴリフィルタ（空=全て表示）
    @State private var selectedCategories: Set<LogCategory> = []

    /// 選択された時間範囲フィルタ
    @State private var selectedTimeRange: LogTimeRange = .allTime

    /// 検索テキスト
    @State private var searchText = ""

    /// 選択されたログエントリ（詳細表示用）
    @State private var selectedEntry: LogEntry?

    /// 詳細パネルの表示状態
    @State private var showDetailPanel = false

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                logContent
                    .frame(minWidth: 400)

                if showDetailPanel, let entry = selectedEntry {
                    detailPanel(for: entry)
                        .frame(minWidth: 280, maxWidth: 400)
                }
            }
        }
        .frame(minWidth: showDetailPanel ? 900 : 700, minHeight: 500)
        .accessibilityIdentifier("MCPLogView")
        .onAppear {
            daemonManager.refreshLogs()
            updateLogs()
            applyFilters()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("MCP Server Logs")
                .font(.headline)

            Spacer()

            searchField

            categoryFilterMenu

            levelFilterMenu

            timeRangeFilterMenu

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
                .onChange(of: searchText) { _, _ in
                    applyFilters()
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
        .accessibilityIdentifier("LogSearchField")
    }

    /// カテゴリフィルタメニュー
    private var categoryFilterMenu: some View {
        Menu {
            Button {
                selectedCategories = []
                applyFilters()
            } label: {
                HStack {
                    Text("All Categories")
                    if selectedCategories.isEmpty {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(LogCategory.allCases, id: \.self) { category in
                Button {
                    toggleCategory(category)
                } label: {
                    HStack {
                        Text(category.rawValue.capitalized)
                        if selectedCategories.contains(category) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(categoryFilterLabel)
                    .frame(minWidth: 60)
            }
        }
        .menuStyle(.borderlessButton)
        .accessibilityIdentifier("CategoryFilterMenu")
    }

    private var categoryFilterLabel: String {
        if selectedCategories.isEmpty {
            return "Category"
        } else if selectedCategories.count == 1 {
            return selectedCategories.first!.rawValue.capitalized
        } else {
            return "\(selectedCategories.count) cats"
        }
    }

    private func toggleCategory(_ category: LogCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        applyFilters()
    }

    /// ログレベルフィルタメニュー
    private var levelFilterMenu: some View {
        Menu {
            Button {
                selectedLevels = []
                applyFilters()
            } label: {
                HStack {
                    Text("All Levels")
                    if selectedLevels.isEmpty {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(LogLevel.allCases, id: \.self) { level in
                Button {
                    toggleLevel(level)
                } label: {
                    HStack {
                        Text(level.displayString)
                        if selectedLevels.contains(level) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(levelFilterLabel)
                    .frame(minWidth: 50)
            }
        }
        .menuStyle(.borderlessButton)
        .accessibilityIdentifier("LevelFilterMenu")
    }

    private var levelFilterLabel: String {
        if selectedLevels.isEmpty {
            return "Level"
        } else if selectedLevels.count == 1 {
            return selectedLevels.first!.displayString
        } else {
            return "\(selectedLevels.count) levels"
        }
    }

    private func toggleLevel(_ level: LogLevel) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
        applyFilters()
    }

    /// 時間範囲フィルタメニュー
    private var timeRangeFilterMenu: some View {
        Picker("Time", selection: $selectedTimeRange) {
            ForEach(LogTimeRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 120)
        .onChange(of: selectedTimeRange) { _, _ in
            applyFilters()
        }
        .accessibilityIdentifier("TimeRangeFilterMenu")
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
            updateLogs()
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
                    ForEach(Array(viewModel.filteredLogs.enumerated()), id: \.offset) { index, entry in
                        logEntryRow(entry)
                            .id(index)
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: daemonManager.lastLogLines.count) { _, _ in
                updateLogs()
                if autoScroll, let lastIndex = viewModel.filteredLogs.indices.last {
                    withAnimation {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logEntryRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // タイムスタンプ
            Text(formatTimestamp(entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            // レベルバッジ
            Text(entry.level.displayString)
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(logLevelColor(entry.level).opacity(0.2))
                .foregroundColor(logLevelColor(entry.level))
                .cornerRadius(3)
                .frame(width: 50)

            // カテゴリ
            Text(entry.category.rawValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            // メッセージ
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 詳細表示インジケーター
            if entry.details != nil || entry.operation != nil || entry.agentId != nil {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isEntrySelected(entry) ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectEntry(entry)
        }
    }

    private func isEntrySelected(_ entry: LogEntry) -> Bool {
        guard let selected = selectedEntry else { return false }
        return selected.timestamp == entry.timestamp && selected.message == entry.message
    }

    private func selectEntry(_ entry: LogEntry) {
        if isEntrySelected(entry) {
            // 同じエントリをタップした場合は詳細パネルを閉じる
            selectedEntry = nil
            showDetailPanel = false
        } else {
            selectedEntry = entry
            showDetailPanel = true
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func logLevelColor(_ level: LogLevel) -> Color {
        switch level {
        case .error:
            return .red
        case .warn:
            return .orange
        case .info:
            return .blue
        case .debug:
            return .gray
        case .trace:
            return .purple
        }
    }

    // MARK: - Detail Panel

    private func detailPanel(for entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            HStack {
                Text("Log Details")
                    .font(.headline)
                Spacer()
                Button {
                    showDetailPanel = false
                    selectedEntry = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 基本情報
                    detailSection(title: "Basic Info") {
                        detailRow(label: "Timestamp", value: formatFullTimestamp(entry.timestamp))
                        detailRow(label: "Level", value: entry.level.displayString)
                        detailRow(label: "Category", value: entry.category.rawValue)
                        detailRow(label: "Message", value: entry.message)
                    }

                    // オプション情報
                    if entry.operation != nil || entry.agentId != nil || entry.projectId != nil {
                        detailSection(title: "Context") {
                            if let operation = entry.operation {
                                detailRow(label: "Operation", value: operation)
                            }
                            if let agentId = entry.agentId {
                                detailRow(label: "Agent ID", value: agentId)
                            }
                            if let projectId = entry.projectId {
                                detailRow(label: "Project ID", value: projectId)
                            }
                        }
                    }

                    // 詳細情報（JSON）
                    if let details = entry.details {
                        detailSection(title: "Details") {
                            Text(formatDetails(details))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                    }

                    // JSON全体
                    detailSection(title: "Raw JSON") {
                        Text(entry.toJSON())
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("LogDetailPanel")
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            content()
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }

    private func formatFullTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func formatDetails(_ details: [String: Any]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    // MARK: - Filtering

    private func updateLogs() {
        viewModel.parseAndSetLogs(daemonManager.lastLogLines)
    }

    private func applyFilters() {
        viewModel.setLevelFilter(selectedLevels)
        viewModel.setCategoryFilter(selectedCategories)
        viewModel.setSearchText(searchText)
        viewModel.setTimeRange(selectedTimeRange)
    }
}

// MARK: - Preview

#Preview {
    MCPLogView(daemonManager: MCPDaemonManager())
}
