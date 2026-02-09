import Foundation
import Hummingbird
import GRDB
import Infrastructure
import UseCase
import Domain

extension RESTServer {

    // MARK: - Log Upload Handler


    /// POST /api/v1/execution-logs/upload
    /// Coordinatorからのログファイルアップロードを受け付け、プロジェクトWD配下に保存
    /// 参照: docs/design/LOG_TRANSFER_DESIGN.md
    func handleLogUpload(request: Request, context: AuthenticatedContext) async throws -> Response {
        // 1. coordinator_token認証
        guard let authHeader = request.headers[.authorization],
              authHeader.hasPrefix("Bearer ") else {
            debugLog("[Log Upload] Missing or invalid Authorization header")
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
            debugLog("[Log Upload] Invalid coordinator_token")
            return errorResponse(status: .unauthorized, message: "Invalid coordinator token")
        }

        // 2. リクエストボディを取得（最大15MB: 10MBログ + メタデータ余裕）
        let maxBodySize = 15 * 1024 * 1024
        let body = try await request.body.collect(upTo: maxBodySize)
        guard let data = body.getData(at: 0, length: body.readableBytes) else {
            debugLog("[Log Upload] Empty request body")
            return errorResponse(status: .badRequest, message: "Empty request body")
        }

        // 3. multipart/form-dataをパース
        guard let contentType = request.headers[.contentType],
              contentType.contains("multipart/form-data") else {
            debugLog("[Log Upload] Content-Type must be multipart/form-data")
            return errorResponse(status: .badRequest, message: "Content-Type must be multipart/form-data")
        }

        // boundaryを抽出
        guard let boundaryRange = contentType.range(of: "boundary="),
              let boundary = contentType[boundaryRange.upperBound...].split(separator: ";").first else {
            debugLog("[Log Upload] Missing boundary in Content-Type")
            return errorResponse(status: .badRequest, message: "Missing boundary in Content-Type")
        }

        let formData = parseMultipartFormData(data: data, boundary: String(boundary))

        // 4. 必須フィールドを取得
        guard let executionLogId = formData.fields["execution_log_id"],
              let agentId = formData.fields["agent_id"],
              let taskId = formData.fields["task_id"],
              let projectId = formData.fields["project_id"],
              let logFileData = formData.files["log_file"] else {
            debugLog("[Log Upload] Missing required fields")
            return errorResponse(status: .badRequest, message: "Missing required fields: execution_log_id, agent_id, task_id, project_id, log_file")
        }

        let originalFilename = formData.fields["original_filename"] ?? formData.filenames["log_file"] ?? "execution.log"

        debugLog("[Log Upload] Received: exec=\(executionLogId), agent=\(agentId), project=\(projectId), file=\(originalFilename)")

        // 5. LogUploadServiceを使用してアップロード処理
        let service = LogUploadService(
            directoryManager: directoryManager,
            projectRepository: projectRepository,
            executionLogRepository: executionLogRepository
        )

        do {
            let result = try service.uploadLog(
                executionLogId: executionLogId,
                agentId: agentId,
                taskId: taskId,
                projectId: projectId,
                logData: logFileData,
                originalFilename: originalFilename
            )

            debugLog("[Log Upload] Success: \(result.logFilePath ?? "unknown")")

            let response = LogUploadResponse(
                success: true,
                executionLogId: executionLogId,
                logFilePath: result.logFilePath ?? "",
                fileSize: result.fileSize
            )
            return jsonResponse(response)
        } catch let error as LogUploadError {
            switch error {
            case .projectNotFound:
                return errorResponse(status: .notFound, message: "Project not found")
            case .workingDirectoryNotConfigured:
                return errorResponse(status: .notFound, message: "Project working directory not configured")
            case .fileTooLarge(let maxMB, let actualMB):
                return errorResponse(status: HTTPResponse.Status(code: 413), message: "Log file exceeds maximum size (\(maxMB)MB). Actual: \(String(format: "%.2f", actualMB))MB")
            case .fileWriteFailed(let underlyingError):
                debugLog("[Log Upload] File write failed: \(underlyingError)")
                return errorResponse(status: .internalServerError, message: "Failed to save log file")
            case .executionLogNotFound:
                return errorResponse(status: .notFound, message: "Execution log not found")
            case .notImplemented:
                return errorResponse(status: .internalServerError, message: "Not implemented")
            }
        } catch {
            debugLog("[Log Upload] Unexpected error: \(error)")
            return errorResponse(status: .internalServerError, message: "Internal server error")
        }
    }

    /// multipart/form-dataをパースする
    func parseMultipartFormData(data: Data, boundary: String) -> MultipartFormData {
        var result = MultipartFormData()
        let boundaryData = "--\(boundary)".data(using: .utf8)!
        let endBoundaryData = "--\(boundary)--".data(using: .utf8)!

        // パートを分割
        var parts: [Data] = []
        var currentStart = 0

        // 最初のboundaryを見つける
        if let firstBoundaryRange = data.range(of: boundaryData) {
            currentStart = firstBoundaryRange.upperBound
        }

        while currentStart < data.count {
            // 次のboundaryを見つける
            let searchRange = currentStart..<data.count
            if let nextBoundaryRange = data.range(of: boundaryData, in: searchRange) {
                // CRLFをスキップ
                var partStart = currentStart
                if data.count > partStart + 1 && data[partStart] == 0x0D && data[partStart + 1] == 0x0A {
                    partStart += 2
                }
                // 末尾のCRLFを除去
                var partEnd = nextBoundaryRange.lowerBound
                if partEnd >= 2 && data[partEnd - 2] == 0x0D && data[partEnd - 1] == 0x0A {
                    partEnd -= 2
                }
                if partStart < partEnd {
                    parts.append(data.subdata(in: partStart..<partEnd))
                }
                currentStart = nextBoundaryRange.upperBound
            } else if let endRange = data.range(of: endBoundaryData, in: searchRange) {
                // 最後のパート
                var partStart = currentStart
                if data.count > partStart + 1 && data[partStart] == 0x0D && data[partStart + 1] == 0x0A {
                    partStart += 2
                }
                var partEnd = endRange.lowerBound
                if partEnd >= 2 && data[partEnd - 2] == 0x0D && data[partEnd - 1] == 0x0A {
                    partEnd -= 2
                }
                if partStart < partEnd {
                    parts.append(data.subdata(in: partStart..<partEnd))
                }
                break
            } else {
                break
            }
        }

        // 各パートをパース
        for part in parts {
            // ヘッダーとボディを分離（空行で区切り）
            let separatorData = "\r\n\r\n".data(using: .utf8)!
            guard let separatorRange = part.range(of: separatorData) else { continue }

            let headerData = part.subdata(in: 0..<separatorRange.lowerBound)
            let bodyData = part.subdata(in: separatorRange.upperBound..<part.count)

            guard let headerString = String(data: headerData, encoding: .utf8) else { continue }

            // Content-Dispositionからnameとfilenameを抽出
            var fieldName: String?
            var fileName: String?

            let lines = headerString.components(separatedBy: "\r\n")
            for line in lines {
                if line.lowercased().hasPrefix("content-disposition:") {
                    // name="..."を抽出
                    if let nameRange = line.range(of: "name=\"") {
                        let start = nameRange.upperBound
                        if let endQuote = line[start...].firstIndex(of: "\"") {
                            fieldName = String(line[start..<endQuote])
                        }
                    }
                    // filename="..."を抽出
                    if let filenameRange = line.range(of: "filename=\"") {
                        let start = filenameRange.upperBound
                        if let endQuote = line[start...].firstIndex(of: "\"") {
                            fileName = String(line[start..<endQuote])
                        }
                    }
                }
            }

            if let name = fieldName {
                if let fn = fileName {
                    // ファイルフィールド
                    result.files[name] = bodyData
                    result.filenames[name] = fn
                } else {
                    // テキストフィールド
                    if let textValue = String(data: bodyData, encoding: .utf8) {
                        result.fields[name] = textValue
                    }
                }
            }
        }

        return result
    }
}

/// multipart/form-dataのパース結果
struct MultipartFormData {
    var fields: [String: String] = [:]
    var files: [String: Data] = [:]
    var filenames: [String: String] = [:]
}
