import Foundation
import Network

/// dsh-omi-voice 本地引擎服务（协议见 dsh-omi-voice/docs/API.md v1）。
///
/// DSH Web 插件通过本服务控制 Omi 朗读：只监听 127.0.0.1，v1 无鉴权，
/// 豆包 API Key 永不离开 Keychain、不进任何日志。
///
/// 端点：
///   GET  /v1/status  健康/状态（含 keyConfigured / playing）
///   POST /v1/speak   朗读文本（打断当前播放；引擎负责清洗与分段）
///   POST /v1/stop    停止当前朗读（幂等）
final class LocalTTSService {
    private static let logPath = "/tmp/readaloud-service.log"
    private static let defaultPort: UInt16 = 8765
    private static let portDefaultsKey = "com.wentuo.readaloud.localtts.port"

    private let queue = DispatchQueue(label: "com.wentuo.readaloud.localtts")
    private var listener: NWListener?
    private weak var provider: ReadAloudServiceProvider?
    /// 存活连接处理器：收到完整请求并响应后连接关闭，届时从字典移除。
    private var activeConnections: [ObjectIdentifier: ConnectionHandler] = [:]
    /// 同文本短时间去重（防连点重复消耗豆包字符配额）。
    private var lastSpeakText: String?
    private var lastSpeakAt: Date?

    init(provider: ReadAloudServiceProvider) {
        self.provider = provider
    }

    var port: UInt16 {
        if let overridden = UserDefaults.standard.object(forKey: Self.portDefaultsKey) as? NSNumber,
           overridden.uint16Value != 0 {
            return overridden.uint16Value
        }
        return Self.defaultPort
    }

    /// 启动监听。失败时抛出（端口被占用等）。
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.log("localtts listener state=\(state)")
        }
        listener.start(queue: queue)
        self.listener = listener
        log("localtts started port=\(port) bound=127.0.0.1")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        log("localtts stopped")
    }

    // MARK: - 连接处理

    private func handle(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let handler = ConnectionHandler(connection: connection) { [weak self] request in
            self?.dispatch(request, on: connection)
        }
        activeConnections[id] = handler
        connection.stateUpdateHandler = { [weak self, weak handler] state in
            switch state {
            case .failed, .cancelled:
                self?.activeConnections[id] = nil
                handler?.connection.cancel()
            default:
                break
            }
        }
        handler.start(on: queue)
    }

    private func dispatch(_ request: HTTPRequest, on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("OPTIONS", _):
            respond(connection, status: 204, reason: "No Content", headers: corsHeaders(for: request), body: Data())
        case ("GET", "/v1/status"):
            handleStatus(on: connection, request: request)
        case ("POST", "/v1/speak"):
            handleSpeak(on: connection, request: request)
        case ("POST", "/v1/stop"):
            handleStop(on: connection, request: request)
        case ("POST", "/v1/pause"):
            handlePause(on: connection, request: request)
        case ("POST", "/v1/resume"):
            handleResume(on: connection, request: request)
        default:
            respondJSON(
                connection,
                status: 404,
                reason: "Not Found",
                request: request,
                payload: errorPayload(code: "not_found", message: "未知端点：\(request.path)")
            )
        }
    }

    private func handleStatus(on connection: NWConnection, request: HTTPRequest) {
        Task { @MainActor [weak self, weak provider] in
            guard let self, let provider else { return }
            let status = provider.remoteEngineStatus
            let payload: [String: Any] = [
                "ok": true,
                "engine": "omi",
                "engineVersion": Self.engineVersion,
                "protocolVersion": 1,
                "keyConfigured": provider.remoteKeyConfigured,
                "voice": provider.remoteVoiceID,
                "state": status.state,
                "playing": status.playing,
                "paused": status.paused,
                "message": status.message ?? NSNull(),
                "currentTaskId": NSNull()
            ]
            self.respondJSON(connection, status: 200, reason: "OK", request: request, payload: payload)
        }
    }

    private func handlePause(on connection: NWConnection, request: HTTPRequest) {
        Task { @MainActor [weak self, weak provider] in
            guard let self, let provider else { return }
            provider.remotePause()
            self.respondJSON(connection, status: 200, reason: "OK", request: request, payload: ["ok": true])
        }
    }

    private func handleResume(on connection: NWConnection, request: HTTPRequest) {
        Task { @MainActor [weak self, weak provider] in
            guard let self, let provider else { return }
            provider.remoteResume()
            self.respondJSON(connection, status: 200, reason: "OK", request: request, payload: ["ok": true])
        }
    }

    private func handleSpeak(on connection: NWConnection, request: HTTPRequest) {
        let body: [String: Any]
        do {
            guard let parsed = try? JSONSerialization.jsonObject(with: request.body, options: []) as? [String: Any] else {
                respondJSON(
                    connection,
                    status: 400,
                    reason: "Bad Request",
                    request: request,
                    payload: errorPayload(code: "invalid_request", message: "请求体必须是 JSON 对象")
                )
                return
            }
            body = parsed
        }
        guard let text = body["text"] as? String else {
            respondJSON(
                connection,
                status: 400,
                reason: "Bad Request",
                request: request,
                payload: errorPayload(code: "invalid_text", message: "缺少 text 字段")
            )
            return
        }
        let rate = (body["rate"] as? NSNumber)?.floatValue
        // 同文本 3 秒内短时间去重：连点/重复请求不重复消耗豆包字符配额
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if lastSpeakText == normalizedText,
           let lastSpeakAt,
           Date().timeIntervalSince(lastSpeakAt) < 3 {
            let payload: [String: Any] = [
                "ok": true,
                "taskId": UUID().uuidString,
                "segments": 0
            ]
            log("localtts speak deduplicated textLength=\(normalizedText.count)")
            respondJSON(connection, status: 202, reason: "Accepted", request: request, payload: payload)
            return
        }
        // 任意朗读请求间最小间隔 300ms，防连点不同消息时连续烧字数
        if let lastSpeakAt, Date().timeIntervalSince(lastSpeakAt) < 0.3 {
            let payload: [String: Any] = [
                "ok": true,
                "taskId": UUID().uuidString,
                "segments": 0
            ]
            log("localtts speak throttled")
            respondJSON(connection, status: 202, reason: "Accepted", request: request, payload: payload)
            return
        }
        lastSpeakText = normalizedText
        lastSpeakAt = Date()
        Task { @MainActor [weak self, weak provider] in
            guard let self, let provider else { return }
            do {
                let segmentCount = try provider.remoteSpeak(text: text, rate: rate)
                let payload: [String: Any] = [
                    "ok": true,
                    "taskId": UUID().uuidString,
                    "segments": segmentCount
                ]
                self.respondJSON(connection, status: 202, reason: "Accepted", request: request, payload: payload)
            } catch RemoteSpeakError.invalidText {
                self.respondJSON(
                    connection,
                    status: 400,
                    reason: "Bad Request",
                    request: request,
                    payload: self.errorPayload(code: "invalid_text", message: "文本为空或没有可朗读的内容")
                )
            } catch RemoteSpeakError.keyNotConfigured {
                self.respondJSON(
                    connection,
                    status: 403,
                    reason: "Forbidden",
                    request: request,
                    payload: self.errorPayload(code: "key_not_configured", message: "请先在 Omi 设置页配置豆包 API Key")
                )
            } catch {
                self.log("localtts speak failed \(error)")
                self.respondJSON(
                    connection,
                    status: 500,
                    reason: "Internal Server Error",
                    request: request,
                    payload: self.errorPayload(code: "tts_failed", message: "朗读失败，请查看 Omi 面板状态")
                )
            }
        }
    }

    private func handleStop(on connection: NWConnection, request: HTTPRequest) {
        Task { @MainActor [weak self, weak provider] in
            guard let self, let provider else { return }
            provider.remoteStop()
            self.respondJSON(connection, status: 200, reason: "OK", request: request, payload: ["ok": true])
        }
    }

    // MARK: - 响应

    private func respondJSON(
        _ connection: NWConnection,
        status: Int,
        reason: String,
        request: HTTPRequest,
        payload: [String: Any]
    ) {
        let body: Data
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            body = data
        } else {
            body = Data("{}".utf8)
        }
        var headers = corsHeaders(for: request)
        headers["Content-Type"] = "application/json; charset=utf-8"
        respond(connection, status: status, reason: reason, headers: headers, body: body)
    }

    private func respond(
        _ connection: NWConnection,
        status: Int,
        reason: String,
        headers: [String: String],
        body: Data
    ) {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var merged = headers
        merged["Content-Length"] = "\(body.count)"
        merged["Connection"] = "close"
        for (key, value) in merged.sorted(by: { $0.key < $1.key }) {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func corsHeaders(for request: HTTPRequest) -> [String: String] {
        var headers: [String: String] = [:]
        if let origin = request.headers["origin"], Self.isLoopbackOrigin(origin) {
            headers["Access-Control-Allow-Origin"] = origin
            headers["Vary"] = "Origin"
        }
        headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        headers["Access-Control-Allow-Headers"] = "Content-Type"
        return headers
    }

    /// 服务只监听 127.0.0.1，放行任意 loopback origin（任意端口），
    /// 避免 DSH 换端口/代理端口时出现难排查的 "Load failed"。
    private static func isLoopbackOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let host = url.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private static var engineVersion: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return "dev"
    }

    private func errorPayload(code: String, message: String) -> [String: Any] {
        [
            "ok": false,
            "error": [
                "code": code,
                "message": message,
                "retryAfterSec": nil
            ]
        ]
    }

    // MARK: - 日志（与主服务共用 /tmp/readaloud-service.log）

    private func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = URL(fileURLWithPath: Self.logPath)
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - 最小 HTTP/1.1 请求解析（单请求每连接）

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

private final class ConnectionHandler {
    let connection: NWConnection
    private let onRequest: (HTTPRequest) -> Void
    private var buffer = Data()

    init(connection: NWConnection, onRequest: @escaping (HTTPRequest) -> Void) {
        self.connection = connection
        self.onRequest = onRequest
    }

    func start(on queue: DispatchQueue) {
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
            }
            if error == nil {
                if let request = self.parseRequestIfReady() {
                    self.onRequest(request)
                    return
                }
                if isComplete {
                    self.connection.cancel()
                    return
                }
                self.receive()
            } else {
                self.connection.cancel()
            }
        }
    }

    private func parseRequestIfReady() -> HTTPRequest? {
        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ").map(String.init)
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        let bodyStart = headerRange.upperBound
        let available = buffer.count - bodyStart
        guard available >= contentLength else { return nil }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        buffer.removeAll(keepingCapacity: true)
        return HTTPRequest(
            method: requestLine[0],
            path: requestLine[1],
            headers: headers,
            body: body
        )
    }
}
