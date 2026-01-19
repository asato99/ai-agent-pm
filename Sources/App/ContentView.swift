// Sources/App/ContentView.swift
// メインコンテンツビュー - 3カラムレイアウト
// リアクティブ要件: TaskStoreを共有してUIの自動更新を実現

import SwiftUI
import Domain

struct ContentView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    /// プロジェクト単位でタスクを管理する共有ストア
    /// TaskBoardViewとTaskDetailViewが同じインスタンスを参照
    @State private var taskStore: TaskStore?

    var body: some View {
        @Bindable var router = router

        NavigationSplitView {
            // サイドバー: プロジェクトリスト
            ProjectListView()
        } content: {
            // コンテンツ: タスクボード or Internal Audits or MCP Server or Web Server or エージェント管理
            if router.showingMCPServer {
                MCPServerView(daemonManager: container.mcpDaemonManager)
            } else if router.showingWebServer {
                WebServerView(serverManager: container.webServerManager)
            } else if router.showingInternalAudits {
                InternalAuditListView()
            } else if let projectId = router.selectedProject {
                // プロジェクト変更時にビューを再作成するため .id(projectId) を使用
                // これにより .task が再実行され、タスク一覧がリアクティブに更新される
                TaskBoardView(projectId: projectId, taskStore: taskStore)
                    .id(projectId)  // プロジェクト変更時にビューを強制再作成
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder",
                    description: Text("Select a project from the sidebar or create a new one.")
                )
            }
        } detail: {
            // 詳細: タスク詳細 or チャット or エージェント詳細
            // 優先順位: selectedTask > selectedChatAgent > selectedAgent
            if let taskId = router.selectedTask {
                TaskDetailView(taskId: taskId, taskStore: taskStore)
                    .id(router.detailRefreshId)  // タスク再選択時にビューを再作成
            } else if let chatAgentId = router.selectedChatAgent,
                      let chatProjectId = router.selectedChatProjectId {
                // チャット画面（参照: docs/design/CHAT_FEATURE.md）
                AgentChatView(agentId: chatAgentId, projectId: chatProjectId)
                    .id(router.detailRefreshId)  // 再選択時にビューを再作成
            } else if let agentId = router.selectedAgent {
                AgentDetailView(agentId: agentId)
                    .id(agentId)  // エージェント再選択時にビューを再作成
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text",
                    description: Text("Select a task or agent to view details.")
                )
            }
        }
        .onChange(of: router.selectedProject) { oldValue, newValue in
            // プロジェクトが変わったらTaskStoreを再作成
            if let projectId = newValue {
                taskStore = TaskStore(projectId: projectId, container: container)
            } else {
                taskStore = nil
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
        case .newAgent:
            AgentFormView(mode: .create)
        case .editAgent(let agentId):
            AgentFormView(mode: .edit(agentId))
        case .taskDetail(let taskId):
            TaskDetailView(taskId: taskId)
        case .agentDetail(let agentId):
            AgentDetailView(agentId: agentId)
        case .handoff(let taskId):
            HandoffView(taskId: taskId)
        case .addContext(let taskId):
            ContextFormView(taskId: taskId)
        case .settings:
            SettingsView()
        case .newTemplate:
            TemplateFormView(mode: .create)
        case .editTemplate(let templateId):
            TemplateFormView(mode: .edit(templateId))
        case .templateDetail(let templateId):
            TemplateDetailView(templateId: templateId)
        case .instantiateTemplate(let templateId, let projectId):
            InstantiateTemplateView(templateId: templateId, projectId: projectId)
        case .newInternalAudit:
            InternalAuditFormView(mode: .create)
        case .editInternalAudit(let auditId):
            InternalAuditFormView(mode: .edit(auditId))
        case .internalAuditDetail(let auditId):
            InternalAuditDetailView(auditId: auditId)
        case .newAuditRule(let auditId):
            AuditRuleFormView(mode: .create(auditId))
        case .editAuditRule(let ruleId, let auditId):
            AuditRuleFormView(mode: .edit(ruleId, auditId))
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
