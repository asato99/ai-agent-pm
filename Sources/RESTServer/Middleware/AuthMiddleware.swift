// Sources/RESTServer/Middleware/AuthMiddleware.swift
// AI Agent PM - REST API Server

import Foundation
import Hummingbird
import Infrastructure
import Domain

/// Request context with authenticated agent info
public struct AuthenticatedContext: RequestContext {
    public var coreContext: CoreRequestContextStorage
    public var agentId: AgentID?
    public var sessionToken: String?

    public init(source: Source) {
        self.coreContext = .init(source: source)
        self.agentId = nil
        self.sessionToken = nil
    }
}

/// Authentication Middleware - validates session token from Authorization header
public struct AuthMiddleware: MiddlewareProtocol {
    public typealias Context = AuthenticatedContext

    private let sessionRepository: AgentSessionRepository

    public init(sessionRepository: AgentSessionRepository) {
        self.sessionRepository = sessionRepository
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Extract Bearer token from Authorization header
        guard let authHeader = request.headers[.authorization],
              authHeader.hasPrefix("Bearer ") else {
            return unauthorizedResponse(message: "Missing or invalid Authorization header")
        }

        let token = String(authHeader.dropFirst(7)) // Remove "Bearer " prefix

        // Validate session
        do {
            guard let session = try sessionRepository.findByToken(token) else {
                return unauthorizedResponse(message: "Invalid session token")
            }

            // Check if session is expired
            if session.expiresAt < Date() {
                return unauthorizedResponse(message: "Session expired")
            }

            // Set authenticated context
            var mutableContext = context
            mutableContext.agentId = session.agentId
            mutableContext.sessionToken = token

            return try await next(request, mutableContext)
        } catch {
            return unauthorizedResponse(message: "Session validation failed: \(error.localizedDescription)")
        }
    }

    private func unauthorizedResponse(message: String) -> Response {
        let json = "{\"error\":\"\(message)\"}"
        var response = Response(
            status: .unauthorized,
            body: .init(byteBuffer: .init(string: json))
        )
        response.headers[.contentType] = "application/json"
        return response
    }
}
