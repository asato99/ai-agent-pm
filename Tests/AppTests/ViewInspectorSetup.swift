// Tests/AppTests/ViewInspectorSetup.swift
// ViewInspector テストセットアップ

import XCTest
import SwiftUI
import ViewInspector
@testable import App
@testable import Domain
@testable import UseCase
@testable import Infrastructure

// MARK: - Inspectable Extensions

extension ContentView: Inspectable {}
extension ProjectListView: Inspectable {}
extension TaskBoardView: Inspectable {}
extension TaskDetailView: Inspectable {}
extension AgentDetailView: Inspectable {}
extension ProjectFormView: Inspectable {}
extension TaskFormView: Inspectable {}
extension AgentFormView: Inspectable {}
extension HandoffView: Inspectable {}
extension SettingsView: Inspectable {}
extension TaskColumnView: Inspectable {}
extension TaskCardView: Inspectable {}
extension PriorityBadge: Inspectable {}
extension StatItem: Inspectable {}
extension TaskRow: Inspectable {}
extension SessionRow: Inspectable {}
extension AgentRow: Inspectable {}
extension RoleTypeBadge: Inspectable {}
extension AgentTypeBadge: Inspectable {}
extension AgentStatusBadge: Inspectable {}

// MARK: - Test Helpers

/// テスト用のインメモリDependencyContainer
@MainActor
func createTestContainer() throws -> DependencyContainer {
    // インメモリDBを使用
    let tempDir = FileManager.default.temporaryDirectory
    let dbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db").path
    return try DependencyContainer(databasePath: dbPath)
}

/// テスト用のRouter
func createTestRouter() -> Router {
    Router()
}

// MARK: - Mock Data Factories

enum MockDataFactory {

    static func createProject(
        id: String = UUID().uuidString,
        name: String = "Test Project",
        description: String = "Test Description"
    ) -> Project {
        Project(
            id: ProjectID(value: id),
            name: name,
            description: description,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static func createAgent(
        id: String = UUID().uuidString,
        name: String = "Test Agent",
        role: String = "Developer",
        roleType: AgentRoleType = .developer,
        type: AgentType = .ai,
        status: AgentStatus = .active,
        parentAgentId: String? = nil
    ) -> Agent {
        Agent(
            id: AgentID(value: id),
            name: name,
            role: role,
            type: type,
            roleType: roleType,
            parentAgentId: parentAgentId.map { AgentID(value: $0) },
            status: status,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static func createTask(
        id: String = UUID().uuidString,
        projectId: String = UUID().uuidString,
        title: String = "Test Task",
        description: String = "Test Description",
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        assigneeId: String? = nil
    ) -> Task {
        Task(
            id: TaskID(value: id),
            projectId: ProjectID(value: projectId),
            title: title,
            description: description,
            status: status,
            priority: priority,
            assigneeId: assigneeId.map { AgentID(value: $0) },
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static func createSession(
        id: String = UUID().uuidString,
        projectId: String = UUID().uuidString,
        agentId: String = UUID().uuidString,
        status: SessionStatus = .active
    ) -> Session {
        Session(
            id: SessionID(value: id),
            projectId: ProjectID(value: projectId),
            agentId: AgentID(value: agentId),
            startedAt: Date(),
            endedAt: nil,
            status: status
        )
    }
}

// MARK: - View Test Base Class

class ViewTestCase: XCTestCase {
    var container: DependencyContainer!
    var router: Router!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        container = try createTestContainer()
        router = createTestRouter()
    }

    override func tearDown() {
        container = nil
        router = nil
        super.tearDown()
    }
}
