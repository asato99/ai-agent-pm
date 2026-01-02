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
    }

    /// タスクを選択
    public func selectTask(_ taskId: TaskID?) {
        selectedTask = taskId
    }

    /// エージェントを選択
    public func selectAgent(_ agentId: AgentID?) {
        selectedAgent = agentId
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
        default:
            break
        }
    }
}
