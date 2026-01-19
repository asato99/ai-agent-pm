// Sources/App/Core/Navigation/Router.swift
// ナビゲーション管理 - 画面遷移を一元管理

import SwiftUI
import Domain

/// アプリケーションのナビゲーション状態を管理
@Observable
public final class Router {

    // MARK: - Selection State

    /// 選択中のプロジェクト
    public var selectedProject: ProjectID?

    /// 選択中のタスク（サイドバーで選択）
    public var selectedTask: TaskID?

    /// 選択中のエージェント
    public var selectedAgent: AgentID?

    /// 選択中のテンプレート
    public var selectedTemplate: WorkflowTemplateID?

    /// 選択中のInternal Audit
    public var selectedInternalAudit: InternalAuditID?

    /// チャット表示中のエージェント
    /// 参照: docs/design/CHAT_FEATURE.md
    public var selectedChatAgent: AgentID?

    /// チャットのプロジェクトコンテキスト
    public var selectedChatProjectId: ProjectID?

    /// Internal Audits一覧を表示中かどうか
    public var showingInternalAudits: Bool = false

    /// MCP Server管理画面を表示中かどうか
    public var showingMCPServer: Bool = false

    /// Web Server管理画面を表示中かどうか
    public var showingWebServer: Bool = false

    /// 詳細ビューのリフレッシュ用ID（選択のたびに変更してビューを再作成）
    public var detailRefreshId: UUID = UUID()

    // MARK: - Navigation Path

    /// NavigationStack用のパス
    public var path: NavigationPath = NavigationPath()

    // MARK: - Sheet State

    /// 現在表示中のシート
    public var currentSheet: SheetDestination?

    // MARK: - Alert State

    /// 現在表示中のアラート
    public var currentAlert: AlertDestination?

    // MARK: - Initialization

    public init() {}

    // MARK: - Sheet Destination

    /// シートの遷移先
    public enum SheetDestination: Identifiable, Equatable {
        case newProject
        case editProject(ProjectID)
        case newTask(ProjectID)
        case editTask(TaskID)
        case newAgent
        case editAgent(AgentID)
        case taskDetail(TaskID)
        case agentDetail(AgentID)
        case handoff(TaskID)
        case addContext(TaskID)
        case settings
        case newTemplate
        case editTemplate(WorkflowTemplateID)
        case templateDetail(WorkflowTemplateID)
        case instantiateTemplate(WorkflowTemplateID, ProjectID)
        case newInternalAudit
        case editInternalAudit(InternalAuditID)
        case internalAuditDetail(InternalAuditID)
        case newAuditRule(InternalAuditID)
        case editAuditRule(AuditRuleID, InternalAuditID)

        public var id: String {
            switch self {
            case .newProject:
                return "newProject"
            case .editProject(let id):
                return "editProject-\(id.value)"
            case .newTask(let id):
                return "newTask-\(id.value)"
            case .editTask(let id):
                return "editTask-\(id.value)"
            case .newAgent:
                return "newAgent"
            case .editAgent(let id):
                return "editAgent-\(id.value)"
            case .taskDetail(let id):
                return "taskDetail-\(id.value)"
            case .agentDetail(let id):
                return "agentDetail-\(id.value)"
            case .handoff(let id):
                return "handoff-\(id.value)"
            case .addContext(let id):
                return "addContext-\(id.value)"
            case .settings:
                return "settings"
            case .newTemplate:
                return "newTemplate"
            case .editTemplate(let id):
                return "editTemplate-\(id.value)"
            case .templateDetail(let id):
                return "templateDetail-\(id.value)"
            case .instantiateTemplate(let templateId, let projectId):
                return "instantiateTemplate-\(templateId.value)-\(projectId.value)"
            case .newInternalAudit:
                return "newInternalAudit"
            case .editInternalAudit(let id):
                return "editInternalAudit-\(id.value)"
            case .internalAuditDetail(let id):
                return "internalAuditDetail-\(id.value)"
            case .newAuditRule(let auditId):
                return "newAuditRule-\(auditId.value)"
            case .editAuditRule(let ruleId, let auditId):
                return "editAuditRule-\(ruleId.value)-\(auditId.value)"
            }
        }
    }

    // MARK: - Alert Destination

    /// アラートの種類
    public enum AlertDestination: Identifiable {
        case deleteConfirmation(title: String, action: () -> Void)
        case error(message: String)
        case info(title: String, message: String)

        public var id: String {
            switch self {
            case .deleteConfirmation(let title, _):
                return "delete-\(title)"
            case .error(let message):
                return "error-\(message)"
            case .info(let title, _):
                return "info-\(title)"
            }
        }
    }

    // MARK: - Navigation Actions

    /// プロジェクトを選択
    public func selectProject(_ projectId: ProjectID?) {
        selectedProject = projectId
        selectedTask = nil
        selectedAgent = nil
        selectedChatAgent = nil
        selectedChatProjectId = nil
        showingInternalAudits = false
        showingMCPServer = false
        showingWebServer = false
    }

    /// タスクを選択
    public func selectTask(_ taskId: TaskID?) {
        selectedTask = taskId
        // タスク選択時はチャットをクリア
        selectedChatAgent = nil
        selectedChatProjectId = nil
        // タスク選択時は常にdetailRefreshIdを更新してビューを再作成
        detailRefreshId = UUID()
    }

    /// エージェントを選択
    public func selectAgent(_ agentId: AgentID?) {
        selectedAgent = agentId
    }

    /// テンプレートを選択
    public func selectTemplate(_ templateId: WorkflowTemplateID?) {
        selectedTemplate = templateId
    }

    /// Internal Auditを選択
    public func selectInternalAudit(_ auditId: InternalAuditID?) {
        selectedInternalAudit = auditId
    }

    /// エージェントとのチャットを開く
    /// 参照: docs/design/CHAT_FEATURE.md
    public func selectChatWithAgent(_ agentId: AgentID, in projectId: ProjectID) {
        selectedTask = nil
        selectedAgent = nil
        selectedChatAgent = agentId
        selectedChatProjectId = projectId
        detailRefreshId = UUID()
    }

    /// チャット画面を閉じる
    public func closeChatView() {
        selectedChatAgent = nil
        selectedChatProjectId = nil
    }

    /// Internal Audits一覧を表示
    public func showInternalAudits() {
        showingInternalAudits = true
        selectedProject = nil
        selectedTask = nil
        selectedAgent = nil
    }

    /// Internal Audits表示を解除（プロジェクト選択時など）
    public func hideInternalAudits() {
        showingInternalAudits = false
    }

    /// MCP Server管理画面を表示
    public func showMCPServer() {
        showingMCPServer = true
        showingWebServer = false
        selectedProject = nil
        selectedTask = nil
        selectedAgent = nil
        showingInternalAudits = false
    }

    /// Web Server管理画面を表示
    public func showWebServer() {
        showingWebServer = true
        showingMCPServer = false
        selectedProject = nil
        selectedTask = nil
        selectedAgent = nil
        showingInternalAudits = false
    }

    /// シートを表示
    public func showSheet(_ destination: SheetDestination) {
        currentSheet = destination
    }

    /// シートを閉じる
    public func dismissSheet() {
        currentSheet = nil
    }

    /// アラートを表示
    public func showAlert(_ alert: AlertDestination) {
        currentAlert = alert
    }

    /// アラートを閉じる
    public func dismissAlert() {
        currentAlert = nil
    }

    /// ナビゲーションパスをリセット
    public func resetPath() {
        path = NavigationPath()
    }

    /// 前の画面に戻る
    public func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    // MARK: - Deep Link Support

    /// URLからナビゲーションを実行
    public func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)

        switch host {
        case "project":
            if let projectIdString = pathComponents.first {
                selectProject(ProjectID(value: projectIdString))
            }
        case "task":
            if let taskIdString = pathComponents.first {
                showSheet(.taskDetail(TaskID(value: taskIdString)))
            }
        case "agent":
            if let agentIdString = pathComponents.first {
                showSheet(.agentDetail(AgentID(value: agentIdString)))
            }
        case "settings":
            showSheet(.settings)
        case "template":
            if let templateIdString = pathComponents.first {
                showSheet(.templateDetail(WorkflowTemplateID(value: templateIdString)))
            }
        case "audit":
            if let auditIdString = pathComponents.first {
                showSheet(.internalAuditDetail(InternalAuditID(value: auditIdString)))
            }
        default:
            break
        }
    }
}
