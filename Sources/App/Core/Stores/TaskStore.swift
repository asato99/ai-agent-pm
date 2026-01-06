// Sources/App/Core/Stores/TaskStore.swift
// 共有タスクストア - リアクティブなUI更新を実現
// リアクティブ要件: UIは状態変更に自動的に反応して更新されるべき

import SwiftUI
import Domain

/// プロジェクト単位でタスクを管理する共有ストア
/// TaskBoardViewとTaskDetailViewが同じインスタンスを参照することで、
/// 一方でのステータス変更が他方に即座に反映される
@MainActor
public final class TaskStore: ObservableObject {

    /// プロジェクトのタスク一覧（@Publishedで変更を通知）
    @Published public private(set) var tasks: [Task] = []

    /// 読み込み中フラグ
    @Published public private(set) var isLoading: Bool = false

    public let projectId: ProjectID
    private weak var container: DependencyContainer?

    public init(projectId: ProjectID, container: DependencyContainer) {
        self.projectId = projectId
        self.container = container
    }

    /// タスク一覧を読み込む
    public func loadTasks() async {
        guard let container = container else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            tasks = try container.getTasksUseCase.execute(projectId: projectId, status: nil)
        } catch {
            // エラーは呼び出し元で処理
            print("[TaskStore] Failed to load tasks: \(error.localizedDescription)")
        }
    }

    /// 特定のタスクを更新（ローカル状態を即座に更新）
    /// リポジトリから再取得せずに、渡されたタスクで直接更新する
    public func updateTask(_ updatedTask: Task) {
        if let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) {
            tasks[index] = updatedTask
        } else {
            // 新しいタスクの場合は追加
            tasks.append(updatedTask)
        }
    }

    /// タスクIDで特定のタスクを再読み込み
    public func reloadTask(taskId: TaskID) async {
        guard let container = container else { return }

        do {
            let detail = try container.getTaskDetailUseCase.execute(taskId: taskId)
            updateTask(detail.task)
        } catch {
            print("[TaskStore] Failed to reload task \(taskId.value): \(error.localizedDescription)")
        }
    }

    /// タスクを削除
    public func removeTask(taskId: TaskID) {
        tasks.removeAll { $0.id == taskId }
    }

    /// 指定ステータスのタスクを取得
    public func tasks(for status: TaskStatus) -> [Task] {
        tasks.filter { $0.status == status }
    }
}
