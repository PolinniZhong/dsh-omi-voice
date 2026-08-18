import Foundation

struct TTSConfiguration: Sendable {
    var apiKey: String
    // 控制台“语音合成大模型”的产品名是 seed-tts-1.0；
    // V3 请求头使用该服务的 Resource ID，而不是产品名本身。
    var resourceID: String? = "volc.service_type.10029"
    var endpoint: URL = URL(string: "wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream")!
    var model: String = "seed-tts-1.0"
    var voiceType: String = "zh_female_shuangkuaisisi_moon_bigtts"
    /// 豆包语速范围为 -50...100；20 对应 1.2 倍速。
    var speechRate: Int = 20

    var clampedSpeechRate: Int {
        min(max(speechRate, -50), 100)
    }
}

enum TTSClientError: LocalizedError {
    case emptyText
    case missingAPIKey
    case invalidEndpoint
    case protocolPending
    case network

    var errorDescription: String? {
        switch self {
        case .emptyText: return "没有可朗读的文本。"
        case .missingAPIKey: return "尚未配置 API Key。"
        case .invalidEndpoint: return "TTS 服务地址无效。"
        case .protocolPending: return "标准 TTS 流式报文尚未完成配置。"
        case .network: return "TTS 网络请求失败。"
        }
    }
}

/// V1 的 TTS 供应商边界。播放器只依赖这个协议，不直接依赖豆包字段。
protocol TTSClient: Sendable {
    func stream(text: String) async throws -> AsyncThrowingStream<Data, Error>
}

struct DoubaoTTSClient: TTSClient {
    let configuration: TTSConfiguration

    func requestHeaders(requestID: String = UUID().uuidString) -> [String: String] {
        var headers = [
            "Content-Type": "application/json",
            "X-Api-Key": configuration.apiKey,
            "X-Api-Request-Id": requestID
        ]
        if let resourceID = configuration.resourceID, !resourceID.isEmpty {
            headers["X-Api-Resource-Id"] = resourceID
        }
        return headers
    }

    func requestPayload(text: String) throws -> Data {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSClientError.emptyText
        }
        let payload: [String: Any] = [
            "req_params": [
                "text": text,
                "speaker": configuration.voiceType,
                // additions 必须是 JSON 字符串，和控制台“语音合成大模型”的示例一致。
                "additions": "{\"disable_markdown_filter\":true,\"enable_language_detector\":true,\"enable_latex_tn\":true}",
                "audio_params": [
                    "format": "pcm",
                    "sample_rate": 24_000,
                    "speech_rate": configuration.clampedSpeechRate
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    func stream(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSClientError.emptyText
        }
        guard !configuration.apiKey.isEmpty else {
            throw TTSClientError.missingAPIKey
        }
        guard configuration.endpoint.scheme == "wss" else {
            throw TTSClientError.invalidEndpoint
        }

        let payload = try requestPayload(text: text)
        var request = URLRequest(url: configuration.endpoint)
        request.timeoutInterval = 30
        for (key, value) in requestHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let preparedRequest = request

        return AsyncThrowingStream { continuation in
            let worker = Task {
                let socket = URLSession.shared.webSocketTask(with: preparedRequest)
                socket.resume()
                do {
                    try await socket.send(.data(TTSBinaryProtocol.makeClientRequest(payload: payload)))
                    receiveLoop: while !Task.isCancelled {
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case .data(let value): data = value
                        case .string(let value): data = Data(value.utf8)
                        @unknown default: throw TTSClientError.network
                        }
                        switch try TTSBinaryProtocol.parseServerFrame(data) {
                        case .audio(let audio, _, let isFinal):
                            continuation.yield(audio)
                            if isFinal { break receiveLoop }
                        case .error:
                            throw TTSServiceError.provider(code: nil, requestID: nil)
                        case .other:
                            continue
                        }
                    }
                    socket.cancel(with: .normalClosure, reason: nil)
                    continuation.finish()
                } catch is CancellationError {
                    socket.cancel(with: .goingAway, reason: nil)
                    continuation.finish()
                } catch {
                    socket.cancel(with: .abnormalClosure, reason: nil)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}
