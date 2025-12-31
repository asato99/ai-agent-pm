// Sources/Domain/Entities/Subtask.swift
// 参照: docs/prd/TASK_MANAGEMENT.md - サブタスク

import Foundation

/// タスクのサブタスク（チェックリスト項目）を表すエンティティ
public struct Subtask: Identifiable, Equatable, Sendable {
    public let id: SubtaskID
    public let taskId: TaskID
    public var title: String
    public var isCompleted: Bool
    public var order: Int
    public let createdAt: Date
    public var completedAt: Date?

    public init(
        id: SubtaskID,
        taskId: TaskID,
        title: String,
        isCompleted: Bool = false,
        order: Int = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.title = title
        self.isCompleted = isCompleted
        self.order = order
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    /// サブタスクを完了にする
    public mutating func complete() {
        isCompleted = true
        completedAt = Date()
    }

    /// サブタスクを未完了に戻す
    public mutating func uncomplete() {
        isCompleted = false
        completedAt = nil
    }
}
