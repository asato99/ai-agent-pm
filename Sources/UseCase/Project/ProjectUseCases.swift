// Sources/UseCase/Project/ProjectUseCases.swift
// プロジェクト関連ユースケース

import Foundation
import Domain

// MARK: - GetProjectsUseCase

/// プロジェクト一覧取得ユースケース
public struct GetProjectsUseCase: Sendable {
    private let projectRepository: any ProjectRepositoryProtocol

    public init(projectRepository: any ProjectRepositoryProtocol) {
        self.projectRepository = projectRepository
    }

    public func execute() throws -> [Project] {
        try projectRepository.findAll()
    }
}

// MARK: - CreateProjectUseCase

/// プロジェクト作成ユースケース
public struct CreateProjectUseCase: Sendable {
    private let projectRepository: any ProjectRepositoryProtocol

    public init(projectRepository: any ProjectRepositoryProtocol) {
        self.projectRepository = projectRepository
    }

    public func execute(name: String, description: String? = nil, workingDirectory: String? = nil) throws -> Project {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Name cannot be empty")
        }

        let project = Project(
            id: ProjectID.generate(),
            name: name,
            description: description ?? "",
            workingDirectory: workingDirectory?.isEmpty == true ? nil : workingDirectory
        )

        try projectRepository.save(project)
        return project
    }
}

// MARK: - Feature 14: Project Pause/Resume UseCases

/// プロジェクト一時停止ユースケース
/// 要件: docs/plan/PROJECT_PAUSE_FEATURE.md
/// - タスク処理のみ停止、チャット・管理操作は継続
/// - アクティブセッションの有効期限を短縮（5分）
public struct PauseProjectUseCase: Sendable {
    private let projectRepository: any ProjectRepositoryProtocol
    private let agentSessionRepository: any AgentSessionRepositoryProtocol

    /// 後処理猶予時間（5分）
    private static let gracePeriod: TimeInterval = 5 * 60

    public init(
        projectRepository: any ProjectRepositoryProtocol,
        agentSessionRepository: any AgentSessionRepositoryProtocol
    ) {
        self.projectRepository = projectRepository
        self.agentSessionRepository = agentSessionRepository
    }

    public func execute(projectId: ProjectID) throws -> Project {
        guard var project = try projectRepository.findById(projectId) else {
            throw UseCaseError.projectNotFound(projectId)
        }

        // archivedプロジェクトは一時停止できない
        guard project.status != .archived else {
            throw UseCaseError.invalidProjectStatus(
                projectId: projectId,
                currentStatus: project.status,
                requiredStatus: "active or paused"
            )
        }

        // 既にpausedの場合はそのまま返す
        guard project.status != .paused else {
            return project
        }

        // ステータスをpausedに変更
        project.status = .paused
        project.updatedAt = Date()
        try projectRepository.save(project)

        // アクティブセッションの有効期限を短縮
        let sessions = try agentSessionRepository.findByProjectId(projectId)

        let newExpiry = Date().addingTimeInterval(Self.gracePeriod)
        for var session in sessions {
            if !session.isExpired && session.expiresAt > newExpiry {
                session.expiresAt = newExpiry
                try agentSessionRepository.save(session)
            }
        }

        return project
    }
}

/// プロジェクト再開ユースケース
/// 要件: docs/plan/PROJECT_PAUSE_FEATURE.md
/// - pausedからactiveに変更
/// - resumedAtを設定（復帰検知用）
public struct ResumeProjectUseCase: Sendable {
    private let projectRepository: any ProjectRepositoryProtocol

    public init(projectRepository: any ProjectRepositoryProtocol) {
        self.projectRepository = projectRepository
    }

    public func execute(projectId: ProjectID) throws -> Project {
        guard var project = try projectRepository.findById(projectId) else {
            throw UseCaseError.projectNotFound(projectId)
        }

        // archivedプロジェクトは再開できない
        guard project.status != .archived else {
            throw UseCaseError.invalidProjectStatus(
                projectId: projectId,
                currentStatus: project.status,
                requiredStatus: "active or paused"
            )
        }

        // 既にactiveの場合はそのまま返す（resumedAtは更新しない）
        guard project.status != .active else {
            return project
        }

        // ステータスをactiveに変更し、resumedAtを設定
        project.status = .active
        project.resumedAt = Date()
        project.updatedAt = Date()
        try projectRepository.save(project)

        return project
    }
}
