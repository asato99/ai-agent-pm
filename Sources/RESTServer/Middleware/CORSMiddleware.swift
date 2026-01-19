// Sources/RESTServer/Middleware/CORSMiddleware.swift
// AI Agent PM - REST API Server

import Foundation
import Hummingbird

/// CORS Middleware for cross-origin requests from web-ui
public struct CORSMiddleware<Context: RequestContext>: MiddlewareProtocol {
    private let allowedOrigins: Set<String>
    private let allowedMethods: String
    private let allowedHeaders: String
    private let maxAge: Int

    public init(
        allowedOrigins: Set<String> = ["http://localhost:5173", "http://localhost:3000", "http://127.0.0.1:5173"],
        allowedMethods: String = "GET, POST, PUT, PATCH, DELETE, OPTIONS",
        allowedHeaders: String = "Content-Type, Authorization, Accept",
        maxAge: Int = 86400
    ) {
        self.allowedOrigins = allowedOrigins
        self.allowedMethods = allowedMethods
        self.allowedHeaders = allowedHeaders
        self.maxAge = maxAge
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let origin = request.headers[.origin]

        // Handle preflight OPTIONS request
        if request.method == .options {
            var response = Response(status: .noContent)
            addCORSHeaders(to: &response, origin: origin)
            return response
        }

        // Handle regular request
        var response = try await next(request, context)
        addCORSHeaders(to: &response, origin: origin)
        return response
    }

    private func addCORSHeaders(to response: inout Response, origin: String?) {
        // Check if origin is allowed
        let allowedOrigin: String
        if let origin = origin, allowedOrigins.contains(origin) {
            allowedOrigin = origin
        } else if allowedOrigins.contains("*") {
            allowedOrigin = "*"
        } else {
            // Default to first allowed origin for non-browser requests
            allowedOrigin = allowedOrigins.first ?? "http://localhost:5173"
        }

        response.headers[.accessControlAllowOrigin] = allowedOrigin
        response.headers[.accessControlAllowMethods] = allowedMethods
        response.headers[.accessControlAllowHeaders] = allowedHeaders
        response.headers[.accessControlMaxAge] = String(maxAge)
        response.headers[.accessControlAllowCredentials] = "true"
    }
}
