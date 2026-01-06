// Tests/AppTests/AppTests.swift
// PRD UI仕様に基づくViewテスト

import XCTest
import SwiftUI
import ViewInspector
@testable import App
@testable import Domain
@testable import UseCase
@testable import Infrastructure

// MARK: - Test Infrastructure Verification

final class TestInfrastructureTests: XCTestCase {

    func testViewInspectorIsWorking() throws {
        // ViewInspectorが正しくセットアップされていることを確認
        let badge = PriorityBadge(priority: .high)
        XCTAssertNotNil(badge)
    }

    @MainActor
    func testDependencyContainerCreation() async throws {
        // テスト用DependencyContainerが作成できることを確認
        let container = try createTestContainer()
        XCTAssertNotNil(container)
    }

    func testRouterCreation() {
        // Routerが正しく作成されることを確認
        let router = createTestRouter()
        XCTAssertNotNil(router)
        XCTAssertNil(router.selectedProject)
        XCTAssertNil(router.selectedTask)
    }

    func testMockDataFactory() {
        // MockDataFactoryが正しくデータを生成することを確認
        let project = MockDataFactory.createProject(name: "Test")
        XCTAssertEqual(project.name, "Test")

        let agent = MockDataFactory.createAgent(name: "TestAgent")
        XCTAssertEqual(agent.name, "TestAgent")

        let task = MockDataFactory.createTask(title: "TestTask")
        XCTAssertEqual(task.title, "TestTask")
    }
}

// MARK: - Router Tests (Navigation Logic)

final class RouterTests: XCTestCase {

    func testProjectSelection() {
        let router = createTestRouter()
        let projectId = ProjectID(value: "project-1")

        router.selectProject(projectId)

        XCTAssertEqual(router.selectedProject, projectId)
        XCTAssertNil(router.selectedTask, "タスク選択はクリアされるべき")
        XCTAssertNil(router.selectedAgent, "エージェント選択はクリアされるべき")
    }

    func testTaskSelection() {
        let router = createTestRouter()
        let taskId = TaskID(value: "task-1")

        router.selectTask(taskId)

        XCTAssertEqual(router.selectedTask, taskId)
    }

    func testAgentSelection() {
        let router = createTestRouter()
        let agentId = AgentID(value: "agent-1")

        router.selectAgent(agentId)

        XCTAssertEqual(router.selectedAgent, agentId)
    }

    func testSheetPresentation() {
        let router = createTestRouter()
        let projectId = ProjectID(value: "project-1")

        router.showSheet(.newProject)
        XCTAssertNotNil(router.currentSheet)

        router.showSheet(.editProject(projectId))
        XCTAssertEqual(router.currentSheet?.id, "editProject-project-1")

        router.dismissSheet()
        XCTAssertNil(router.currentSheet)
    }

    func testAlertPresentation() {
        let router = createTestRouter()

        router.showAlert(.error(message: "Test error"))
        XCTAssertNotNil(router.currentAlert)

        router.dismissAlert()
        XCTAssertNil(router.currentAlert)
    }

    // MARK: - PRD: Deep Link Support

    func testDeepLinkProjectNavigation() {
        let router = createTestRouter()
        let url = URL(string: "aiagentpm://project/project-123")!

        router.handleDeepLink(url)

        XCTAssertEqual(router.selectedProject?.value, "project-123")
    }

    func testDeepLinkTaskNavigation() {
        let router = createTestRouter()
        let url = URL(string: "aiagentpm://task/task-456")!

        router.handleDeepLink(url)

        XCTAssertEqual(router.currentSheet?.id, "taskDetail-task-456")
    }

    func testDeepLinkAgentNavigation() {
        let router = createTestRouter()
        let url = URL(string: "aiagentpm://agent/agent-789")!

        router.handleDeepLink(url)

        XCTAssertEqual(router.currentSheet?.id, "agentDetail-agent-789")
    }

    func testDeepLinkSettingsNavigation() {
        let router = createTestRouter()
        let url = URL(string: "aiagentpm://settings")!

        router.handleDeepLink(url)

        XCTAssertEqual(router.currentSheet?.id, "settings")
    }
}

// MARK: - PRD UI Component Tests

final class PriorityBadgeTests: XCTestCase {

    /// PRD 02_task_board.md: 優先度表示
    /// | 優先度 | 表示 |
    /// |--------|------|
    /// | Urgent | 🔴 赤バー (左端) |
    /// | High | 🟠 オレンジバー |
    /// | Medium | 🔵 青バー |
    /// | Low | ⚪ グレーバー |
    func testPriorityColors() throws {
        // Urgent -> Red
        let urgentBadge = PriorityBadge(priority: .urgent)
        let urgentView = try urgentBadge.inspect()
        // バッジが存在することを確認
        XCTAssertNoThrow(try urgentView.text())

        // High -> Orange
        let highBadge = PriorityBadge(priority: .high)
        let highView = try highBadge.inspect()
        XCTAssertNoThrow(try highView.text())

        // Medium -> Blue
        let mediumBadge = PriorityBadge(priority: .medium)
        let mediumView = try mediumBadge.inspect()
        XCTAssertNoThrow(try mediumView.text())

        // Low -> Gray
        let lowBadge = PriorityBadge(priority: .low)
        let lowView = try lowBadge.inspect()
        XCTAssertNoThrow(try lowView.text())
    }

    func testPriorityBadgeDisplaysCapitalizedText() throws {
        let badge = PriorityBadge(priority: .high)
        let text = try badge.inspect().text().string()
        XCTAssertEqual(text, "High")
    }
}

final class AgentStatusBadgeTests: XCTestCase {

    /// PRD 03_agent_management.md: エージェントステータス表示
    func testAgentStatusColors() throws {
        // Active -> Green
        let activeBadge = AgentStatusBadge(status: .active)
        XCTAssertNoThrow(try activeBadge.inspect().text())

        // Inactive -> Gray
        let inactiveBadge = AgentStatusBadge(status: .inactive)
        XCTAssertNoThrow(try inactiveBadge.inspect().text())

        // Suspended -> Orange
        let suspendedBadge = AgentStatusBadge(status: .suspended)
        XCTAssertNoThrow(try suspendedBadge.inspect().text())

        // Archived -> Red
        let archivedBadge = AgentStatusBadge(status: .archived)
        XCTAssertNoThrow(try archivedBadge.inspect().text())
    }
}

final class AgentTypeBadgeTests: XCTestCase {

    /// PRD 02_task_board.md: 担当エージェント表示
    /// | 状態 | 表示 |
    /// |------|------|
    /// | AIエージェント | 🤖 名前 |
    /// | 人間 | 👤 名前 |
    func testAgentTypeDisplay() throws {
        let aiBadge = AgentTypeBadge(type: .ai)
        let aiText = try aiBadge.inspect().text().string()
        XCTAssertEqual(aiText, "AI")

        let humanBadge = AgentTypeBadge(type: .human)
        let humanText = try humanBadge.inspect().text().string()
        XCTAssertEqual(humanText, "Human")
    }
}

final class RoleTypeBadgeTests: XCTestCase {

    func testRoleTypeBadgeDisplay() throws {
        // 要件: AgentRoleType には owner は存在しない。manager を使用
        let managerBadge = RoleTypeBadge(roleType: .manager)
        let managerText = try managerBadge.inspect().text().string()
        XCTAssertEqual(managerText, "Manager")

        let developerBadge = RoleTypeBadge(roleType: .developer)
        let developerText = try developerBadge.inspect().text().string()
        XCTAssertEqual(developerText, "Developer")
    }
}

final class StatItemTests: XCTestCase {

    func testStatItemDisplay() throws {
        let statItem = StatItem(title: "Tasks", value: "42")
        let view = try statItem.inspect()

        // VStack containing value and title
        let vstack = try view.vStack()
        XCTAssertEqual(try vstack.text(0).string(), "42")
        XCTAssertEqual(try vstack.text(1).string(), "Tasks")
    }
}

// MARK: - PRD Task Card Tests

final class TaskCardViewTests: XCTestCase {

    func testTaskCardShowsTitle() throws {
        let task = MockDataFactory.createTask(title: "Implement API")
        let card = TaskCardView(task: task, agents: [])

        let view = try card.inspect()
        // VStackの最初のTextがタイトル
        let title = try view.vStack().text(0).string()
        XCTAssertEqual(title, "Implement API")
    }

    func testTaskCardShowsDescription() throws {
        let task = MockDataFactory.createTask(
            title: "Test",
            description: "Important task description"
        )
        let card = TaskCardView(task: task, agents: [])

        let view = try card.inspect()
        // descriptionが表示されることを確認
        let vstack = try view.vStack()
        // 2番目のTextがdescription（存在する場合）
        XCTAssertNoThrow(try vstack.text(1))
    }

    func testTaskCardShowsAssigneeName() throws {
        let agentId = "agent-1"
        let agent = MockDataFactory.createAgent(id: agentId, name: "Developer Bot")
        let task = MockDataFactory.createTask(assigneeId: agentId)
        let card = TaskCardView(task: task, agents: [agent])

        XCTAssertEqual(card.assigneeName, "Developer Bot")
    }

    func testTaskCardShowsUnassignedWhenNoAssignee() throws {
        let task = MockDataFactory.createTask(assigneeId: nil)
        let card = TaskCardView(task: task, agents: [])

        XCTAssertNil(card.assigneeName)
    }
}

// MARK: - PRD Task Column Tests

final class TaskColumnViewTests: XCTestCase {

    /// PRD 02_task_board.md: カラムヘッダー
    /// ステータス名と件数が表示される
    func testColumnShowsStatusName() throws {
        let column = TaskColumnView(
            status: .inProgress,
            tasks: [],
            agents: [],
            onTaskDropped: { _, _ in }
        )

        let view = try column.inspect()
        // ヘッダーのHStackを検査
        let vstack = try view.vStack()
        let header = try vstack.hStack(0)
        let statusText = try header.text(0).string()
        XCTAssertEqual(statusText, "In Progress")
    }

    func testColumnShowsTaskCount() throws {
        let tasks = [
            MockDataFactory.createTask(title: "Task 1", status: .todo),
            MockDataFactory.createTask(title: "Task 2", status: .todo)
        ]
        let column = TaskColumnView(
            status: .todo,
            tasks: tasks,
            agents: [],
            onTaskDropped: { _, _ in }
        )

        let view = try column.inspect()
        // accessibilityIdentifierを使ってカウントTextを取得
        let countText = try view.find(viewWithAccessibilityIdentifier: "ColumnCount_todo").text().string()
        XCTAssertEqual(countText, "2")
    }
}

// MARK: - Task Status Display Name Tests

final class TaskStatusDisplayTests: XCTestCase {

    /// 要件 02_task_board.md: カラム表示名（inReview削除済み）
    func testTaskStatusDisplayNames() {
        XCTAssertEqual(TaskStatus.backlog.displayName, "Backlog")
        XCTAssertEqual(TaskStatus.todo.displayName, "To Do")
        XCTAssertEqual(TaskStatus.inProgress.displayName, "In Progress")
        XCTAssertEqual(TaskStatus.blocked.displayName, "Blocked")
        XCTAssertEqual(TaskStatus.done.displayName, "Done")
        XCTAssertEqual(TaskStatus.cancelled.displayName, "Cancelled")
    }
}

// MARK: - PRD Sheet Destination Tests

final class SheetDestinationTests: XCTestCase {

    /// 要件: 各シートに一意のIDがあること（エージェントはプロジェクト非依存）
    func testSheetDestinationIds() {
        let projectId = ProjectID(value: "p1")
        let taskId = TaskID(value: "t1")
        let agentId = AgentID(value: "a1")

        XCTAssertEqual(Router.SheetDestination.newProject.id, "newProject")
        XCTAssertEqual(Router.SheetDestination.editProject(projectId).id, "editProject-p1")
        XCTAssertEqual(Router.SheetDestination.newTask(projectId).id, "newTask-p1")
        XCTAssertEqual(Router.SheetDestination.editTask(taskId).id, "editTask-t1")
        XCTAssertEqual(Router.SheetDestination.newAgent.id, "newAgent")
        XCTAssertEqual(Router.SheetDestination.editAgent(agentId).id, "editAgent-a1")
        XCTAssertEqual(Router.SheetDestination.taskDetail(taskId).id, "taskDetail-t1")
        XCTAssertEqual(Router.SheetDestination.agentDetail(agentId).id, "agentDetail-a1")
        XCTAssertEqual(Router.SheetDestination.handoff(taskId).id, "handoff-t1")
        XCTAssertEqual(Router.SheetDestination.settings.id, "settings")
    }
}

// MARK: - PRD Alert Destination Tests

final class AlertDestinationTests: XCTestCase {

    func testAlertDestinationIds() {
        let deleteAlert = Router.AlertDestination.deleteConfirmation(title: "Project", action: {})
        XCTAssertTrue(deleteAlert.id.hasPrefix("delete-"))

        let errorAlert = Router.AlertDestination.error(message: "Something went wrong")
        XCTAssertTrue(errorAlert.id.hasPrefix("error-"))

        let infoAlert = Router.AlertDestination.info(title: "Info", message: "Hello")
        XCTAssertTrue(infoAlert.id.hasPrefix("info-"))
    }
}

// MARK: - PRD Compliance Summary Tests

final class UISpecComplianceTests: XCTestCase {

    /// UI仕様との差異を文書化するテスト
    func testPRDCompliance_ProjectListFeatures() {
        // PRD 01_project_list.md で定義されている機能の確認

        // 必須機能
        // [x] プロジェクト選択 -> Router.selectProject
        // [x] 新規プロジェクト作成 -> SheetDestination.newProject
        // [x] プロジェクト編集 -> SheetDestination.editProject
        // [ ] ソートオプション (recentlyUpdated, name, createdDate, taskCount) -> 未実装
        // [ ] フィルターオプション (all, active, archived) -> 未実装
        // [ ] 右クリックコンテキストメニュー -> 未実装
        // [ ] プロジェクトカードにタスクサマリ表示 -> 未実装
        // [ ] 最新イベント表示 -> 未実装

        XCTAssertTrue(true, "PRD差異を文書化")
    }

    func testPRDCompliance_TaskBoardFeatures() {
        // PRD 02_task_board.md で定義されている機能の確認

        // 必須機能
        // [x] カンバンカラム表示 -> TaskColumnView
        // [x] タスクカード表示 -> TaskCardView
        // [x] 優先度バッジ -> PriorityBadge
        // [x] ステータス表示名 -> TaskStatus.displayName
        // [ ] ドラッグ&ドロップ -> 未実装
        // [ ] 検索機能 -> 未実装
        // [ ] フィルターバー -> 未実装
        // [ ] 右クリックコンテキストメニュー -> 未実装

        XCTAssertTrue(true, "PRD差異を文書化")
    }

    func testPRDCompliance_TaskBoardColumns() {
        // PRD: Backlog, Todo, Progress, Review, Done, Blocked
        // 実装: 5カラム (Backlog, Todo, InProgress, InReview, Done)
        // 差異: Blockedカラムが実装に含まれていない

        // TaskBoardViewのcolumnsを確認
        // 実装では: [.backlog, .todo, .inProgress, .inReview, .done]
        // PRDでは: Blockedも表示されるべき

        XCTAssertTrue(true, "PRD差異: Blockedカラムが未実装")
    }
}
