import Foundation

/// V3 HTTP Chunked 单向流式客户端。
/// 服务端以 JSON 流返回音频分片，data 字段按 Base64 解码后交给播放器。
struct DoubaoHTTPStreamingClient: TTSClient {
    let configuration: TTSConfiguration

    func stream(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSClientError.emptyText
        }
        guard !configuration.apiKey.isEmpty else {
            throw TTSClientError.missingAPIKey
        }

        var endpoint = configuration.endpoint
        endpoint = URL(string: "https://openspeech.bytedance.com/api/v3/tts/unidirectional")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        for (key, value) in headers() { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try requestPayload(text: text)
        let preparedRequest = request

        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: preparedRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw TTSServiceError.invalidHTTPResponse
                    }
                    let requestID = http.value(forHTTPHeaderField: "X-Api-Request-Id")
                    guard (200..<300).contains(http.statusCode) else {
                        throw TTSServiceError.http(statusCode: http.statusCode, requestID: requestID)
                    }

                    var line = Data()
                    for try await byte in bytes {
                        if byte == 10 || byte == 13 {
                            try emit(line: line, requestID: requestID, continuation: continuation)
                            line.removeAll(keepingCapacity: true)
                        } else {
                            line.append(byte)
                        }
                    }
                    if !line.isEmpty { try emit(line: line, requestID: requestID, continuation: continuation) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    private func headers() -> [String: String] {
        var values = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Api-Key": configuration.apiKey,
            "X-Api-Request-Id": UUID().uuidString,
            "X-Control-Require-Usage-Tokens-Return": "text_words",
            "Connection": "keep-alive"
        ]
        if let resourceID = configuration.resourceID, !resourceID.isEmpty {
            values["X-Api-Resource-Id"] = resourceID
        }
        return values
    }

    func requestPayload(text: String) throws -> Data {
        let body: [String: Any] = [
            "req_params": [
                "text": text,
                "speaker": configuration.voiceType,
                "additions": "{\"disable_markdown_filter\":true,\"enable_language_detector\":true,\"enable_latex_tn\":true}",
                "audio_params": [
                    "format": "pcm",
                    "sample_rate": 24_000,
                    "speech_rate": configuration.clampedSpeechRate
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func emit(
        line: Data,
        requestID: String?,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) throws {
        guard !line.isEmpty,
              let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let code = object["code"] as? Int, code != 0, code != 20000000 {
            throw TTSServiceError.provider(code: String(code), requestID: requestID)
        }
        if let encoded = object["data"] as? String, let audio = Data(base64Encoded: encoded), !audio.isEmpty {
            continuation.yield(audio)
        }
    }
}
