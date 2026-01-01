// Sources/App/ContentView.swift
// メインコンテンツビュー - 3カラムレイアウト

import SwiftUI
import Domain

struct ContentView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    var body: some View {
        @Bindable var router = router

        NavigationSplitView {
            // サイドバー: プロジェクトリスト
            ProjectListView()
        } content: {
            // コンテンツ: タスクボード or エージェント管理
            if let projectId = router.selectedProject {
                TaskBoardView(projectId: projectId)
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder",
                    description: Text("Select a project from the sidebar or create a new one.")
                )
            }
        } detail: {
            // 詳細: タスク詳細 or エージェント詳細
            if let taskId = router.selectedTask {
                TaskDetailView(taskId: taskId)
            } else if let agentId = router.selectedAgent {
                AgentDetailView(agentId: agentId)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text",
                    description: Text("Select a task or agent to view details.")
                )
            }
        }
        .sheet(item: $router.currentSheet) { destination in
            sheetContent(for: destination)
        }
        .alert(item: $router.currentAlert) { alert in
            alertContent(for: alert)
        }
        .onOpenURL { url in
            router.handleDeepLink(url)
        }
        // XCUITest用: ルートビューをアクセシビリティ階層に確実に公開
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MainContentView")
    }

    @ViewBuilder
    private func sheetContent(for destination: Router.SheetDestination) -> some View {
        switch destination {
        case .newProject:
            ProjectFormView(mode: .create)
        case .editProject(let projectId):
            ProjectFormView(mode: .edit(projectId))
        case .newTask(let projectId):
            TaskFormView(mode: .create(projectId: projectId))
        case .editTask(let taskId):
            TaskFormView(mode: .edit(taskId))
        case .newAgent(let projectId):
            AgentFormView(mode: .create(projectId: projectId))
        case .editAgent(let agentId):
            AgentFormView(mode: .edit(agentId))
        case .taskDetail(let taskId):
            TaskDetailView(taskId: taskId)
        case .agentDetail(let agentId):
            AgentDetailView(agentId: agentId)
        case .handoff(let taskId):
            HandoffView(taskId: taskId)
        case .settings:
            SettingsView()
        }
    }

    private func alertContent(for alert: Router.AlertDestination) -> Alert {
        switch alert {
        case .deleteConfirmation(let title, let action):
            return Alert(
                title: Text("Delete \(title)?"),
                message: Text("This action cannot be undone."),
                primaryButton: .destructive(Text("Delete"), action: action),
                secondaryButton: .cancel()
            )
        case .error(let message):
            return Alert(
                title: Text("Error"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        case .info(let title, let message):
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
