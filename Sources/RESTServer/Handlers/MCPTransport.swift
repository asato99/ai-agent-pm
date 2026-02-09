import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - MCP HTTP Transport

    /// MCP JSON-RPCリクエストを処理
    /// Authorization: Bearer <coordinator_token> で認証
    func handleMCPRequest(request: Request, context: AuthenticatedContext) async throws -> Response {
        // 1. coordinator_token認証
        guard let authHeader = request.headers[.authorization],
              authHeader.hasPrefix("Bearer ") else {
            debugLog("[MCP HTTP] Missing or invalid Authorization header")
            return errorResponse(status: .unauthorized, message: "Authorization header required")
        }

        let coordinatorToken = String(authHeader.dropFirst("Bearer ".count))

        // DBの設定を優先、環境変数をフォールバック
        var expectedToken: String?
        if let settings = try? appSettingsRepository.get() {
            expectedToken = settings.coordinatorToken
        }
        if expectedToken == nil || expectedToken?.isEmpty == true {
            expectedToken = ProcessInfo.processInfo.environment["COORDINATOR_TOKEN"]
        }

        guard let expected = expectedToken, !expected.isEmpty, coordinatorToken == expected else {
            debugLog("[MCP HTTP] Invalid coordinator_token")
            return errorResponse(status: .unauthorized, message: "Invalid coordinator token")
        }

        // 2. リクエストボディをパース
        let body = try await request.body.collect(upTo: 1024 * 1024) // 1MB limit
        guard let data = body.getData(at: 0, length: body.readableBytes) else {
            debugLog("[MCP HTTP] Empty request body")
            return jsonRPCErrorResponse(id: nil, error: JSONRPCError.invalidRequest)
        }

        // 3. JSONRPCRequestをデコード
        let jsonRPCRequest: JSONRPCRequest
        do {
            jsonRPCRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        } catch {
            debugLog("[MCP HTTP] JSON parse error: \(error)")
            return jsonRPCErrorResponse(id: nil, error: JSONRPCError.parseError)
        }

        debugLog("[MCP HTTP] Request: \(jsonRPCRequest.method)")

        // 4. MCPServerで処理（非同期版を使用 - Long Polling対応）
        // 参照: docs/design/LONG_POLLING_DESIGN.md
        let response = await mcpServer.processHTTPRequestAsync(jsonRPCRequest)

        // 5. レスポンスをJSON化して返す
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let responseData = try encoder.encode(response)

        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: responseData))
        )
    }

    /// JSON-RPCエラーレスポンスを生成
    func jsonRPCErrorResponse(id: RequestID?, error: JSONRPCError) -> Response {
        let response = JSONRPCResponse(id: id, error: error)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(response) else {
            return Response(
                status: .internalServerError,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: "{\"error\":\"Internal Server Error\"}"))
            )
        }

        return Response(
            status: .ok, // JSON-RPC always returns 200, errors are in the body
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

}
