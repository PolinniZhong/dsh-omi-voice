import Foundation

/// 公开版的错误边界：服务端原始响应、请求 Header、请求文本和凭据都不能越过这里。
enum TTSServiceError: LocalizedError, Sendable {
    case invalidHTTPResponse
    case http(statusCode: Int, requestID: String?)
    case provider(code: String?, requestID: String?)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "朗读服务返回了无效响应。"
        case .http(let statusCode, let requestID):
            return "朗读服务请求失败（HTTP \(statusCode)\(ReadAloudDiagnostics.requestIDSuffix(requestID))）。"
        case .provider(let code, let requestID):
            let codePart = code.map { "服务码 \($0)" } ?? "服务端错误"
            return "朗读服务请求失败（\(codePart)\(ReadAloudDiagnostics.requestIDSuffix(requestID))）。"
        }
    }
}

enum ReadAloudDiagnostics {
    private final class SensitiveValueStore: @unchecked Sendable {
        private let lock = NSLock()
        private var values = Set<String>()

        func insert(_ value: String) {
            lock.lock()
            values.insert(value)
            lock.unlock()
        }

        func snapshot() -> Set<String> {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private static let sensitiveValueStore = SensitiveValueStore()

    static func registerSensitiveValue(_ value: String) {
        guard !value.isEmpty else { return }
        sensitiveValueStore.insert(value)
    }

    /// 最后一层防线。正常日志应只由结构化字段组成，不能依赖这层去保留第三方原文。
    static func redact(_ message: String) -> String {
        var result = message
        for value in sensitiveValueStore.snapshot() where !value.isEmpty {
            result = result.replacingOccurrences(of: value, with: "[REDACTED]")
        }
        result = replacing(
            #"(?i)(x-api-key\s*[:=]\s*)[^\s,;]+"#,
            in: result,
            with: "$1[REDACTED]"
        )
        result = replacing(
            #"(?i)(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+"#,
            in: result,
            with: "$1[REDACTED]"
        )
        result = replacing(
            #"(?i)\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b"#,
            in: result,
            with: "[REDACTED-UUID]"
        )
        return result
    }

    static func logFields(for error: Error) -> String {
        if let error = error as? TTSServiceError {
            switch error {
            case .invalidHTTPResponse:
                return "category=service-response kind=invalid-http-response"
            case .http(let statusCode, let requestID):
                return "category=service-response httpStatus=\(statusCode)\(requestIDField(requestID))"
            case .provider(let code, let requestID):
                let codeField = code.map { " serviceCode=\($0)" } ?? ""
                return "category=service-response\(codeField)\(requestIDField(requestID))"
            }
        }
        if let error = error as? URLError {
            return "category=network urlError=\(error.code.rawValue)"
        }
        if let error = error as? KeychainError {
            return "category=keychain kind=\(keychainKind(error))"
        }
        if error is TTSClientError {
            return "category=tts-client"
        }
        return "category=unexpected type=\(String(describing: type(of: error)))"
    }

    static func userFacingMessage(_ error: Error) -> String {
        if let error = error as? KeychainError {
            return error.localizedDescription
        }
        if let error = error as? TTSServiceError {
            return error.localizedDescription
        }
        if error is TTSClientError {
            return "朗读服务暂时不可用，请检查配置和网络后重试。"
        }
        if error is URLError {
            return "网络连接失败，请检查网络后重试。"
        }
        return "朗读失败，请稍后重试。"
    }

    static func requestIDSuffix(_ requestID: String?) -> String {
        guard let requestID, !requestID.isEmpty else { return "" }
        return "，请求 ID：\(requestID)"
    }

    private static func requestIDField(_ requestID: String?) -> String {
        guard let requestID, !requestID.isEmpty else { return "" }
        return " requestID=\(requestID)"
    }

    private static func keychainKind(_ error: KeychainError) -> String {
        switch error {
        case .itemNotFound: return "item-not-found"
        case .legacyItemUnavailable: return "legacy-item-unavailable"
        case .accessDenied: return "access-denied"
        case .invalidData: return "invalid-data"
        case .emptyValue: return "empty-value"
        case .unexpectedStatus(let status): return "status-\(status)"
        }
    }

    private static func replacing(_ pattern: String, in value: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }
}
