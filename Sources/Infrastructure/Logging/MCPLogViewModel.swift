// Sources/Infrastructure/Logging/MCPLogViewModel.swift
// ログフィルタリングを提供するViewModel

import Foundation

// MARK: - LogTimeRange

/// ログの時間範囲フィルタ
public enum LogTimeRange: String, CaseIterable, Sendable {
    case lastHour = "Last Hour"
    case last24Hours = "Last 24 Hours"
    case last7Days = "Last 7 Days"
    case allTime = "All Time"

    /// 指定した時間範囲の開始日時を取得
    ///
    /// - Parameter now: 現在時刻（テスト用にカスタマイズ可能）
    /// - Returns: 時間範囲の開始日時（allTimeの場合はnil）
    public func startDate(from now: Date = Date()) -> Date? {
        switch self {
        case .lastHour:
            return now.addingTimeInterval(-3600)
        case .last24Hours:
            return now.addingTimeInterval(-86400)
        case .last7Days:
            return now.addingTimeInterval(-86400 * 7)
        case .allTime:
            return nil
        }
    }
}

/// MCPログのフィルタリングと管理を行うViewModel
///
/// ログレベル、カテゴリ、エージェントID、検索テキスト、時間範囲によるフィルタリングをサポート。
public final class MCPLogViewModel: @unchecked Sendable {

    // MARK: - Properties

    private let lock = NSLock()

    /// 全てのログエントリ
    private var _allLogs: [LogEntry] = []
    public var allLogs: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _allLogs
    }

    /// レベルフィルタ（空の場合は全レベル表示）
    private var _levelFilter: Set<LogLevel> = []
    public var levelFilter: Set<LogLevel> {
        lock.lock()
        defer { lock.unlock() }
        return _levelFilter
    }

    /// カテゴリフィルタ（空の場合は全カテゴリ表示）
    private var _categoryFilter: Set<LogCategory> = []
    public var categoryFilter: Set<LogCategory> {
        lock.lock()
        defer { lock.unlock() }
        return _categoryFilter
    }

    /// エージェントIDフィルタ（nilの場合は全エージェント表示）
    private var _agentIdFilter: String?
    public var agentIdFilter: String? {
        lock.lock()
        defer { lock.unlock() }
        return _agentIdFilter
    }

    /// 検索テキスト（空の場合はフィルタなし）
    private var _searchText: String = ""
    public var searchText: String {
        lock.lock()
        defer { lock.unlock() }
        return _searchText
    }

    /// 時間範囲フィルタ
    private var _timeRange: LogTimeRange = .allTime
    public var timeRange: LogTimeRange {
        lock.lock()
        defer { lock.unlock() }
        return _timeRange
    }

    // MARK: - Computed Properties

    /// フィルタ適用後のログ
    public var filteredLogs: [LogEntry] {
        lock.lock()
        let logs = _allLogs
        let levels = _levelFilter
        let categories = _categoryFilter
        let agentId = _agentIdFilter
        let search = _searchText
        let timeRangeValue = _timeRange
        lock.unlock()

        let now = Date()
        let timeRangeStart = timeRangeValue.startDate(from: now)

        return logs.filter { entry in
            // 時間範囲フィルタ
            if let start = timeRangeStart, entry.timestamp < start {
                return false
            }

            // レベルフィルタ
            if !levels.isEmpty && !levels.contains(entry.level) {
                return false
            }

            // カテゴリフィルタ
            if !categories.isEmpty && !categories.contains(entry.category) {
                return false
            }

            // エージェントIDフィルタ
            if let filterAgentId = agentId, entry.agentId != filterAgentId {
                return false
            }

            // 検索テキストフィルタ
            if !search.isEmpty {
                let lowerSearch = search.lowercased()
                if !entry.message.lowercased().contains(lowerSearch) {
                    return false
                }
            }

            return true
        }
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// ログエントリを設定
    ///
    /// - Parameter logs: 設定するログエントリの配列
    public func setLogs(_ logs: [LogEntry]) {
        lock.lock()
        defer { lock.unlock() }
        _allLogs = logs
    }

    /// 文字列のログ行をパースして設定
    ///
    /// - Parameter lines: ログ行の配列（JSON形式またはテキスト形式）
    public func parseAndSetLogs(_ lines: [String]) {
        let entries = LogParser.parseAll(lines)
        setLogs(entries)
    }

    /// レベルフィルタを設定
    ///
    /// - Parameter levels: 表示するレベルの集合（空の場合は全レベル表示）
    public func setLevelFilter(_ levels: Set<LogLevel>) {
        lock.lock()
        defer { lock.unlock() }
        _levelFilter = levels
    }

    /// レベルフィルタを設定（配列版）
    ///
    /// - Parameter levels: 表示するレベルの配列
    public func setLevelFilter(_ levels: [LogLevel]) {
        setLevelFilter(Set(levels))
    }

    /// カテゴリフィルタを設定
    ///
    /// - Parameter categories: 表示するカテゴリの集合（空の場合は全カテゴリ表示）
    public func setCategoryFilter(_ categories: Set<LogCategory>) {
        lock.lock()
        defer { lock.unlock() }
        _categoryFilter = categories
    }

    /// カテゴリフィルタを設定（配列版）
    ///
    /// - Parameter categories: 表示するカテゴリの配列
    public func setCategoryFilter(_ categories: [LogCategory]) {
        setCategoryFilter(Set(categories))
    }

    /// エージェントIDフィルタを設定
    ///
    /// - Parameter agentId: 表示するエージェントID（nilの場合は全エージェント表示）
    public func setAgentIdFilter(_ agentId: String?) {
        lock.lock()
        defer { lock.unlock() }
        _agentIdFilter = agentId
    }

    /// 検索テキストを設定
    ///
    /// - Parameter text: 検索テキスト（空の場合はフィルタなし）
    public func setSearchText(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        _searchText = text
    }

    /// 時間範囲フィルタを設定
    ///
    /// - Parameter range: 時間範囲
    public func setTimeRange(_ range: LogTimeRange) {
        lock.lock()
        defer { lock.unlock() }
        _timeRange = range
    }

    /// 全てのフィルタをクリア
    public func clearAllFilters() {
        lock.lock()
        defer { lock.unlock() }
        _levelFilter = []
        _categoryFilter = []
        _agentIdFilter = nil
        _searchText = ""
        _timeRange = .allTime
    }
}
