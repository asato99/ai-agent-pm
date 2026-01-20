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
    private let allowRemoteAccess: Bool

    public init(
        allowedOrigins: Set<String> = ["http://localhost:5173", "http://localhost:3000", "http://127.0.0.1:5173"],
        allowedMethods: String = "GET, POST, PUT, PATCH, DELETE, OPTIONS",
        allowedHeaders: String = "Content-Type, Authorization, Accept",
        maxAge: Int = 86400,
        allowRemoteAccess: Bool = false
    ) {
        self.allowedOrigins = allowedOrigins
        self.allowedMethods = allowedMethods
        self.allowedHeaders = allowedHeaders
        self.maxAge = maxAge
        self.allowRemoteAccess = allowRemoteAccess
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
        if let origin = origin {
            if allowedOrigins.contains(origin) {
                allowedOrigin = origin
            } else if allowedOrigins.contains("*") {
                allowedOrigin = "*"
            } else if allowRemoteAccess && isPrivateNetworkOrigin(origin) {
                // When remote access is enabled, allow origins from private networks
                allowedOrigin = origin
            } else {
                // Default to first allowed origin for non-browser requests
                allowedOrigin = allowedOrigins.first ?? "http://localhost:5173"
            }
        } else {
            allowedOrigin = allowedOrigins.first ?? "http://localhost:5173"
        }

        response.headers[.accessControlAllowOrigin] = allowedOrigin
        response.headers[.accessControlAllowMethods] = allowedMethods
        response.headers[.accessControlAllowHeaders] = allowedHeaders
        response.headers[.accessControlMaxAge] = String(maxAge)
        response.headers[.accessControlAllowCredentials] = "true"
    }

    /// Check if the origin is from a private network (RFC 1918)
    private func isPrivateNetworkOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin),
              let host = url.host else {
            return false
        }

        // Allow localhost variants
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }

        // Parse IP address and check private ranges
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            // Not a valid IPv4, could be hostname on local network
            // Allow if it doesn't contain dots (simple hostname) or ends with .local
            return !host.contains(".") || host.hasSuffix(".local")
        }

        // Check RFC 1918 private IP ranges:
        // 10.0.0.0/8 (10.x.x.x)
        if parts[0] == 10 {
            return true
        }

        // 172.16.0.0/12 (172.16.x.x - 172.31.x.x)
        if parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31 {
            return true
        }

        // 192.168.0.0/16 (192.168.x.x)
        if parts[0] == 192 && parts[1] == 168 {
            return true
        }

        // Link-local 169.254.0.0/16
        if parts[0] == 169 && parts[1] == 254 {
            return true
        }

        return false
    }
}
