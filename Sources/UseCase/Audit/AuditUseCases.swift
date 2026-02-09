// Sources/UseCase/Audit/AuditUseCases.swift
// Internal Audit CRUD ユースケース
// 参照: docs/requirements/AUDIT.md

import Foundation
import Domain

// MARK: - CreateInternalAuditUseCase

/// Internal Audit作成ユースケース
public struct CreateInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(name: String, description: String? = nil) throws -> InternalAudit {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw UseCaseError.validationFailed("Name cannot be empty")
        }
        guard trimmedName.count <= 100 else {
            throw UseCaseError.validationFailed("Name must be 100 characters or less")
        }

        let audit = InternalAudit(
            id: InternalAuditID.generate(),
            name: trimmedName,
            description: description
        )
        try internalAuditRepository.save(audit)
        return audit
    }
}

// MARK: - ListInternalAuditsUseCase

/// Internal Audit一覧取得ユースケース
public struct ListInternalAuditsUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(includeInactive: Bool = false) throws -> [InternalAudit] {
        try internalAuditRepository.findAll(includeInactive: includeInactive)
    }
}

// MARK: - GetInternalAuditUseCase

/// Internal Audit詳細取得ユースケース
public struct GetInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(auditId: InternalAuditID) throws -> InternalAudit {
        guard let audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }
        return audit
    }
}

// MARK: - UpdateInternalAuditUseCase

/// Internal Audit更新ユースケース
public struct UpdateInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(
        auditId: InternalAuditID,
        name: String? = nil,
        description: String? = nil
    ) throws -> InternalAudit {
        guard var audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        if let name = name {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw UseCaseError.validationFailed("Name cannot be empty")
            }
            guard trimmedName.count <= 100 else {
                throw UseCaseError.validationFailed("Name must be 100 characters or less")
            }
            audit.name = trimmedName
        }

        if let description = description {
            audit.description = description
        }

        audit.updatedAt = Date()
        try internalAuditRepository.save(audit)
        return audit
    }
}

// MARK: - SuspendInternalAuditUseCase

/// Internal Audit一時停止ユースケース
public struct SuspendInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(auditId: InternalAuditID) throws -> InternalAudit {
        guard var audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        audit.status = .suspended
        audit.updatedAt = Date()
        try internalAuditRepository.save(audit)
        return audit
    }
}

// MARK: - ActivateInternalAuditUseCase

/// Internal Audit有効化ユースケース
public struct ActivateInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(auditId: InternalAuditID) throws -> InternalAudit {
        guard var audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        audit.status = .active
        audit.updatedAt = Date()
        try internalAuditRepository.save(audit)
        return audit
    }
}

// MARK: - DeleteInternalAuditUseCase

/// Internal Audit削除ユースケース
public struct DeleteInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(auditId: InternalAuditID) throws {
        guard try internalAuditRepository.findById(auditId) != nil else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }
        try internalAuditRepository.delete(auditId)
    }
}
