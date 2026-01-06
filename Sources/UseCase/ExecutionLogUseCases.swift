// Sources/UseCase/ExecutionLogUseCases.swift
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3 実行ログ

import Foundation
import Domain

// MARK: - RecordExecutionStartUseCase

/// 実行開始記録ユースケース
/// 外部Runnerがタスク実行を開始したことを記録する
public struct RecordExecutionStartUseCase: Sendable {
    private let executionLogRepository: any ExecutionLogRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol

    public init(
        executionLogRepository: any ExecutionLogRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol
    ) {
        self.executionLogRepository = executionLogRepository
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
    }

    public func execute(
        taskId: TaskID,
        agentId: AgentID
    ) throws -> ExecutionLog {
        // タスクの存在確認
        guard try taskRepository.findById(taskId) != nil else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // エージェントの存在確認
        guard try agentRepository.findById(agentId) != nil else {
            throw UseCaseError.agentNotFound(agentId)
        }

        // 実行ログを作成
        let log = ExecutionLog(taskId: taskId, agentId: agentId)
        try executionLogRepository.save(log)

        return log
    }
}

// MARK: - RecordExecutionCompleteUseCase

/// 実行完了記録ユースケース
/// 外部Runnerがタスク実行を完了したことを記録する
public struct RecordExecutionCompleteUseCase: Sendable {
    private let executionLogRepository: any ExecutionLogRepositoryProtocol

    public init(
        executionLogRepository: any ExecutionLogRepositoryProtocol
    ) {
        self.executionLogRepository = executionLogRepository
    }

    public func execute(
        executionLogId: ExecutionLogID,
        exitCode: Int,
        durationSeconds: Double,
        logFilePath: String? = nil,
        errorMessage: String? = nil
    ) throws -> ExecutionLog {
        // 実行ログの存在確認
        guard var log = try executionLogRepository.findById(executionLogId) else {
            throw UseCaseError.executionLogNotFound(executionLogId)
        }

        // 既に完了している場合はエラー
        guard log.status == .running else {
            throw UseCaseError.invalidStateTransition(
                "Execution log is already completed with status: \(log.status.rawValue)"
            )
        }

        // 完了処理
        log.complete(
            exitCode: exitCode,
            durationSeconds: durationSeconds,
            logFilePath: logFilePath,
            errorMessage: errorMessage
        )

        try executionLogRepository.save(log)

        return log
    }
}

// MARK: - GetExecutionLogsUseCase

/// 実行ログ取得ユースケース
/// タスクまたはエージェントの実行ログを取得する
public struct GetExecutionLogsUseCase: Sendable {
    private let executionLogRepository: any ExecutionLogRepositoryProtocol

    public init(
        executionLogRepository: any ExecutionLogRepositoryProtocol
    ) {
        self.executionLogRepository = executionLogRepository
    }

    public func executeByTaskId(_ taskId: TaskID) throws -> [ExecutionLog] {
        try executionLogRepository.findByTaskId(taskId)
    }

    public func executeByAgentId(_ agentId: AgentID) throws -> [ExecutionLog] {
        try executionLogRepository.findByAgentId(agentId)
    }

    public func executeRunning(agentId: AgentID) throws -> [ExecutionLog] {
        try executionLogRepository.findRunning(agentId: agentId)
    }
}
