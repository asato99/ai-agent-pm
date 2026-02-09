// Sources/Domain/Repositories/AuditRepositoryProtocols.swift
// 監査関連のリポジトリプロトコル（InternalAudit, AuditRule）
// 参照: docs/requirements/AUDIT.md

import Foundation

// MARK: - InternalAuditRepositoryProtocol

/// Internal Auditリポジトリのプロトコル
public protocol InternalAuditRepositoryProtocol: Sendable {
    func findById(_ id: InternalAuditID) throws -> InternalAudit?
    func findAll(includeInactive: Bool) throws -> [InternalAudit]
    func findActive() throws -> [InternalAudit]
    func save(_ audit: InternalAudit) throws
    func delete(_ id: InternalAuditID) throws
}

// MARK: - AuditRuleRepositoryProtocol

/// Audit Ruleリポジトリのプロトコル
public protocol AuditRuleRepositoryProtocol: Sendable {
    func findById(_ id: AuditRuleID) throws -> AuditRule?
    func findByAudit(_ auditId: InternalAuditID) throws -> [AuditRule]
    func findEnabled(auditId: InternalAuditID) throws -> [AuditRule]
    func findByTriggerType(_ triggerType: TriggerType) throws -> [AuditRule]
    func save(_ rule: AuditRule) throws
    func delete(_ id: AuditRuleID) throws
}
