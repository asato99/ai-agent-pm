// Sources/UseCase/SubtaskUseCases.swift
// サブタスク関連のユースケース

import Foundation
import Domain

// MARK: - AddSubtaskUseCase

/// サブタスク追加ユースケース
public struct AddSubtaskUseCase: Sendable {
    private let subtaskRepository: any SubtaskRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol

    public init(
        subtaskRepository: any SubtaskRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol
    ) {
        self.subtaskRepository = subtaskRepository
        self.taskRepository = taskRepository
    }

    public func execute(
        taskId: TaskID,
        title: String
    ) throws -> Subtask {
        // タスクの存在確認
        guard try taskRepository.findById(taskId) != nil else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // バリデーション
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Title cannot be empty")
        }

        // 既存のサブタスク数を取得してorder決定
        let existingSubtasks = try subtaskRepository.findByTask(taskId)
        let order = existingSubtasks.count

        let subtask = Subtask(
            id: SubtaskID.generate(),
            taskId: taskId,
            title: title,
            isCompleted: false,
            order: order
        )

        try subtaskRepository.save(subtask)

        return subtask
    }
}

// MARK: - CompleteSubtaskUseCase

/// サブタスク完了ユースケース
public struct CompleteSubtaskUseCase: Sendable {
    private let subtaskRepository: any SubtaskRepositoryProtocol

    public init(subtaskRepository: any SubtaskRepositoryProtocol) {
        self.subtaskRepository = subtaskRepository
    }

    public func execute(subtaskId: SubtaskID) throws -> Subtask {
        guard var subtask = try subtaskRepository.findById(subtaskId) else {
            throw UseCaseError.validationFailed("Subtask not found")
        }

        subtask.complete()

        try subtaskRepository.save(subtask)

        return subtask
    }

    /// サブタスクを未完了に戻す
    public func uncomplete(subtaskId: SubtaskID) throws -> Subtask {
        guard var subtask = try subtaskRepository.findById(subtaskId) else {
            throw UseCaseError.validationFailed("Subtask not found")
        }

        subtask.uncomplete()

        try subtaskRepository.save(subtask)

        return subtask
    }
}

// MARK: - GetSubtasksUseCase

/// サブタスク取得ユースケース
public struct GetSubtasksUseCase: Sendable {
    private let subtaskRepository: any SubtaskRepositoryProtocol

    public init(subtaskRepository: any SubtaskRepositoryProtocol) {
        self.subtaskRepository = subtaskRepository
    }

    public func execute(taskId: TaskID) throws -> [Subtask] {
        try subtaskRepository.findByTask(taskId)
    }
}
