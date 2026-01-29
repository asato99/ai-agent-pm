// Tests/InfrastructureTests/Logging/MCPLogViewModelTests.swift

import XCTest
@testable import Infrastructure

final class MCPLogViewModelTests: XCTestCase {

    // MARK: - Filter by Level

    func testFilterByLevel() {
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: Date(), level: .debug, category: .system, message: "Debug"),
            LogEntry(timestamp: Date(), level: .info, category: .system, message: "Info"),
            LogEntry(timestamp: Date(), level: .error, category: .system, message: "Error")
        ])

        viewModel.setLevelFilter([.info, .error])

        XCTAssertEqual(viewModel.filteredLogs.count, 2)
        XCTAssertFalse(viewModel.filteredLogs.contains { $0.level == .debug })
    }

    func testFilterByLevelShowsAll() {
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: Date(), level: .debug, category: .system, message: "Debug"),
            LogEntry(timestamp: Date(), level: .info, category: .system, message: "Info"),
            LogEntry(timestamp: Date(), level: .error, category: .system, message: "Error")
        ])

        // No level filter = show all
        viewModel.setLevelFilter([])

        XCTAssertEqual(viewModel.filteredLogs.count, 3)
    }

    // MARK: - Filter by Category

    func testFilterByCategory() {
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: Date(), level: .info, category: .agent, message: "Agent log"),
            LogEntry(timestamp: Date(), level: .info, category: .task, message: "Task log"),
            LogEntry(timestamp: Date(), level: .info, category: .health, message: "Health log")
        ])

        viewModel.setCategoryFilter([.agent])

        XCTAssertEqual(viewModel.filteredLogs.count, 1)
        XCTAssertEqual(viewModel.filteredLogs[0].category, .agent)
    }

    func testFilterByMultipleCategories() {
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: Date(), level: .info, category: .agent, message: "Agent log"),
            LogEntry(timestamp: Date(), level: .info, category: .task, message: "Task log"),
            LogEntry(timestamp: Date(), level: .info, category: .health, message: "Health log")
        ])

        viewModel.setCategoryFilter([.agent, .task])

        XCTAssertEqual(viewModel.filteredLogs.count, 2)
    }

    // MARK: - Filter by AgentId

    func testFilterByAgentId() {
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: Date(), level: .info, category: .agent, message: "Log 1", agentId: "agt_123"),
            LogEntry(timestamp: Date(), level: .info, category: .agent, message: "Log 2", agentId: "agt_456"),
            LogEntry(timestamp: Date(), level: .info, category: .agent, message: "Log 3", agentId: nil)
        ])

        viewModel.setAgentIdFilter("agt_123")

        XCTAssertEqual(viewModel.filteredLogs.count, 1)
        XCTAssertEqual(viewModel.filteredLogs[0].agentId, "agt_123")
    }

    func testFilterByAgentIdClearedShowsAll() {
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: Date(), level: .info, category: .agent, message: "Log 1", agentId: "agt_123"),
            LogEntry(timestamp: Date(), level: .info, category: .agent, message: "Log 2", agentId: "agt_456")
        ])

        viewModel.setAgentIdFilter(nil)

        XCTAssertEqual(viewModel.filteredLogs.count, 2)
    }

    // MARK: - Combined Filters

    func testCombinedFilters() {
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: Date(), level: .debug, category: .agent, message: "Debug agent", agentId: "agt_123"),
            LogEntry(timestamp: Date(), level: .info, category: .agent, message: "Info agent", agentId: "agt_123"),
            LogEntry(timestamp: Date(), level: .info, category: .task, message: "Info task", agentId: "agt_123"),
            LogEntry(timestamp: Date(), level: .info, category: .agent, message: "Info agent 456", agentId: "agt_456")
        ])

        viewModel.setLevelFilter([.info])
        viewModel.setCategoryFilter([.agent])
        viewModel.setAgentIdFilter("agt_123")

        XCTAssertEqual(viewModel.filteredLogs.count, 1)
        XCTAssertEqual(viewModel.filteredLogs[0].message, "Info agent")
    }

    // MARK: - Search Text Filter

    func testFilterBySearchText() {
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: Date(), level: .info, category: .system, message: "Starting server"),
            LogEntry(timestamp: Date(), level: .info, category: .system, message: "Server ready"),
            LogEntry(timestamp: Date(), level: .error, category: .system, message: "Connection failed")
        ])

        viewModel.setSearchText("server")

        XCTAssertEqual(viewModel.filteredLogs.count, 2)
    }

    func testSearchTextCaseInsensitive() {
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: Date(), level: .info, category: .system, message: "Server started"),
            LogEntry(timestamp: Date(), level: .info, category: .system, message: "server running")
        ])

        viewModel.setSearchText("SERVER")

        XCTAssertEqual(viewModel.filteredLogs.count, 2)
    }

    // MARK: - Parse and Set Logs

    func testParseAndSetLogs() {
        let viewModel = MCPLogViewModel()
        let lines = [
            "{\"timestamp\":\"2026-01-28T09:21:35Z\",\"level\":\"INFO\",\"category\":\"system\",\"message\":\"First\"}",
            "{\"timestamp\":\"2026-01-28T09:21:36Z\",\"level\":\"ERROR\",\"category\":\"agent\",\"message\":\"Second\"}",
            "[2026-01-28T09:21:37Z] [WARN] [task] Third"
        ]

        viewModel.parseAndSetLogs(lines)

        XCTAssertEqual(viewModel.allLogs.count, 3)
        XCTAssertEqual(viewModel.allLogs[0].message, "First")
        XCTAssertEqual(viewModel.allLogs[1].level, .error)
        XCTAssertEqual(viewModel.allLogs[2].category, .task)
    }

    // MARK: - Time Range Filter

    func testFilterByTimeRangeLastHour() {
        let now = Date()
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: now.addingTimeInterval(-1800), level: .info, category: .system, message: "30 min ago"),
            LogEntry(timestamp: now.addingTimeInterval(-3599), level: .info, category: .system, message: "Just under 1 hour ago"),
            LogEntry(timestamp: now.addingTimeInterval(-7200), level: .info, category: .system, message: "2 hours ago")
        ])

        viewModel.setTimeRange(.lastHour)

        // Only logs within the last hour (30 min and just under 1 hour ago)
        XCTAssertEqual(viewModel.filteredLogs.count, 2)
    }

    func testFilterByTimeRangeLast24Hours() {
        let now = Date()
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: now.addingTimeInterval(-3600), level: .info, category: .system, message: "1 hour ago"),
            LogEntry(timestamp: now.addingTimeInterval(-86399), level: .info, category: .system, message: "Just under 24 hours ago"),
            LogEntry(timestamp: now.addingTimeInterval(-172800), level: .info, category: .system, message: "48 hours ago")
        ])

        viewModel.setTimeRange(.last24Hours)

        // Only logs within the last 24 hours
        XCTAssertEqual(viewModel.filteredLogs.count, 2)
    }

    func testFilterByTimeRangeAllTime() {
        let now = Date()
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: now.addingTimeInterval(-3600), level: .info, category: .system, message: "1 hour ago"),
            LogEntry(timestamp: now.addingTimeInterval(-86400 * 30), level: .info, category: .system, message: "30 days ago"),
            LogEntry(timestamp: now.addingTimeInterval(-86400 * 365), level: .info, category: .system, message: "1 year ago")
        ])

        viewModel.setTimeRange(.allTime)

        // All logs should be shown
        XCTAssertEqual(viewModel.filteredLogs.count, 3)
    }

    func testFilterByTimeRangeLast7Days() {
        let now = Date()
        let viewModel = MCPLogViewModel()
        viewModel.setLogs([
            LogEntry(timestamp: now.addingTimeInterval(-86400 * 3), level: .info, category: .system, message: "3 days ago"),
            LogEntry(timestamp: now.addingTimeInterval(-86400 * 7 + 1), level: .info, category: .system, message: "Just under 7 days ago"),
            LogEntry(timestamp: now.addingTimeInterval(-86400 * 10), level: .info, category: .system, message: "10 days ago")
        ])

        viewModel.setTimeRange(.last7Days)

        // Only logs within the last 7 days
        XCTAssertEqual(viewModel.filteredLogs.count, 2)
    }
}
