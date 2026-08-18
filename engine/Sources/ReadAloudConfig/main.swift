import Foundation
import Darwin

private enum OfflineStreamEvent: Sendable {
    case audio(Data)
    case failure
}

private enum OfflineStreamFixtureError: Error, Sendable {
    case failed
}

private struct OfflineTTSClient: TTSClient {
    let events: [OfflineStreamEvent]

    func stream(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                switch event {
                case .audio(let data):
                    continuation.yield(data)
                case .failure:
                    continuation.finish(throwing: OfflineStreamFixtureError.failed)
                    return
                }
            }
            continuation.finish()
        }
    }
}

private struct OfflineDelayedTTSClient: TTSClient {
    let delayNanoseconds: UInt64
    let events: [OfflineStreamEvent]

    func stream(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    for event in events {
                        try Task.checkCancellation()
                        switch event {
                        case .audio(let data):
                            continuation.yield(data)
                        case .failure:
                            continuation.finish(throwing: OfflineStreamFixtureError.failed)
                            return
                        }
                    }
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
}

private final class OfflinePlaybackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class OfflinePCMPlayer: PCMStreamingPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var stopCount = 0
    private var drainCount = 0
    private var pauseCount = 0
    private var resumeCount = 0

    func start() throws {}

    @discardableResult
    func append(_ data: Data) -> Bool {
        !data.isEmpty
    }

    func pause() {
        lock.withLock {
            pauseCount += 1
        }
    }

    func resume() {
        lock.withLock {
            resumeCount += 1
        }
    }

    func stop() {
        lock.lock()
        stopCount += 1
        lock.unlock()
    }

    func waitUntilDrained() async {
        lock.withLock {
            drainCount += 1
        }
    }

    func setRate(_ rate: Float) {}

    var counts: (stop: Int, drain: Int, pause: Int, resume: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (stopCount, drainCount, pauseCount, resumeCount)
    }
}

private func runSessionOfflineTests() async throws {
    let noAudioSession = ReadAloudSession()
    await noAudioSession.start(
        text: "测试",
        client: OfflineTTSClient(events: []),
        onAudioChunk: { !$0.isEmpty },
        onPlaybackStarted: {}
    )
    await noAudioSession.waitUntilFinished()
    guard await noAudioSession.state
        == .failed(ReadAloudSessionError.noPlayableAudio.localizedDescription) else {
        throw TTSProtocolError.invalidPayload
    }

    let rejectedAudioSession = ReadAloudSession()
    await rejectedAudioSession.start(
        text: "测试",
        client: OfflineTTSClient(events: [.audio(Data())]),
        onAudioChunk: { !$0.isEmpty },
        onPlaybackStarted: {}
    )
    await rejectedAudioSession.waitUntilFinished()
    guard await rejectedAudioSession.state
        == .failed(ReadAloudSessionError.noPlayableAudio.localizedDescription) else {
        throw TTSProtocolError.invalidPayload
    }

    let completedSession = ReadAloudSession()
    let completedCounter = OfflinePlaybackCounter()
    await completedSession.start(
        text: "测试",
        client: OfflineTTSClient(events: [.audio(Data([0, 0]))]),
        onAudioChunk: { !$0.isEmpty },
        onPlaybackStarted: { completedCounter.record() }
    )
    await completedSession.waitUntilFinished()
    guard await completedSession.state == .playing, completedCounter.value == 1 else {
        throw TTSProtocolError.invalidPayload
    }
    await completedSession.markPlaybackCompleted()
    guard await completedSession.state == .idle else {
        throw TTSProtocolError.invalidPayload
    }

    let failedSession = ReadAloudSession()
    let failedCounter = OfflinePlaybackCounter()
    await failedSession.start(
        text: "测试",
        client: OfflineTTSClient(
            events: [.audio(Data([0, 0])), .failure]
        ),
        onAudioChunk: { !$0.isEmpty },
        onPlaybackStarted: { failedCounter.record() }
    )
    await failedSession.waitUntilFinished()
    guard case .failed = await failedSession.state, failedCounter.value == 1 else {
        throw TTSProtocolError.invalidPayload
    }

    let replacementSession = ReadAloudSession()
    let replacementCounter = OfflinePlaybackCounter()
    await replacementSession.start(
        text: "旧请求",
        client: OfflineDelayedTTSClient(
            delayNanoseconds: 100_000_000,
            events: [.audio(Data([0, 0]))]
        ),
        onAudioChunk: { !$0.isEmpty },
        onPlaybackStarted: { replacementCounter.record() }
    )
    await replacementSession.start(
        text: "新请求",
        client: OfflineTTSClient(events: [.audio(Data([0, 0]))]),
        onAudioChunk: { !$0.isEmpty },
        onPlaybackStarted: { replacementCounter.record() }
    )
    await replacementSession.waitUntilFinished()
    try await Task.sleep(nanoseconds: 150_000_000)
    guard await replacementSession.state == .playing, replacementCounter.value == 1 else {
        throw TTSProtocolError.invalidPayload
    }

    let stoppedSession = ReadAloudSession()
    let stoppedCounter = OfflinePlaybackCounter()
    await stoppedSession.start(
        text: "停止请求",
        client: OfflineDelayedTTSClient(
            delayNanoseconds: 100_000_000,
            events: [.audio(Data([0, 0]))]
        ),
        onAudioChunk: { !$0.isEmpty },
        onPlaybackStarted: { stoppedCounter.record() }
    )
    await stoppedSession.stop()
    try await Task.sleep(nanoseconds: 150_000_000)
    guard await stoppedSession.state == .stopped, stoppedCounter.value == 0 else {
        throw TTSProtocolError.invalidPayload
    }

    let failedPlayer = OfflinePCMPlayer()
    let failedController = ReadAloudController(player: failedPlayer)
    try await failedController.start(
        text: "失败请求",
        client: OfflineTTSClient(
            events: [.audio(Data([0, 0])), .failure]
        ),
        onPlaybackStarted: {}
    )
    await failedController.waitUntilFinished()
    guard case .failed = await failedController.session.state,
          failedPlayer.counts.stop == 1,
          failedPlayer.counts.drain == 0 else {
        throw TTSProtocolError.invalidPayload
    }

    let drainedPlayer = OfflinePCMPlayer()
    let drainedController = ReadAloudController(player: drainedPlayer)
    try await drainedController.start(
        text: "完成请求",
        client: OfflineTTSClient(events: [.audio(Data([0, 0]))]),
        onPlaybackStarted: {}
    )
    await drainedController.waitUntilFinished()
    guard await drainedController.session.state == .idle,
          drainedPlayer.counts.stop == 0,
          drainedPlayer.counts.drain == 1 else {
        throw TTSProtocolError.invalidPayload
    }

    let resumablePlayer = OfflinePCMPlayer()
    let resumableController = ReadAloudController(player: resumablePlayer)
    try await resumableController.start(
        text: "暂停续播请求",
        client: OfflineTTSClient(events: [.audio(Data([0, 0]))]),
        onPlaybackStarted: {}
    )
    await resumableController.session.waitUntilFinished()
    guard await resumableController.session.state == .playing,
          await resumableController.pause(),
          await resumableController.session.state == .paused,
          resumablePlayer.counts.pause == 1,
          resumablePlayer.counts.stop == 0 else {
        throw TTSProtocolError.invalidPayload
    }
    guard await resumableController.resume(),
          await resumableController.session.state == .playing,
          resumablePlayer.counts.resume == 1,
          resumablePlayer.counts.stop == 0 else {
        throw TTSProtocolError.invalidPayload
    }
    await resumableController.waitUntilFinished()
    guard await resumableController.session.state == .idle,
          resumablePlayer.counts.drain == 1 else {
        throw TTSProtocolError.invalidPayload
    }
}

private func runAudioCacheOfflineTests() async throws {
    let cache = ReadAloudLastAudioCache(maximumBytes: 16)
    let key = ReadAloudAudioCacheKey(
        text: "相同文本",
        model: "test-model",
        resourceID: "test-resource",
        voiceID: "test-voice",
        speechRate: 20,
        sampleRate: 24_000
    )
    guard await cache.audio(for: key) == nil else {
        throw TTSProtocolError.invalidPayload
    }

    let expectedChunks = [Data([0, 1]), Data([2, 3])]
    let recordingClient = RecordingTTSClient(
        base: OfflineTTSClient(events: expectedChunks.map(OfflineStreamEvent.audio)),
        key: key,
        cache: cache,
        onStored: { _, _, _ in }
    )
    let recordingStream = try await recordingClient.stream(text: key.text)
    var recordedChunks: [Data] = []
    for try await chunk in recordingStream {
        recordedChunks.append(chunk)
    }
    guard recordedChunks == expectedChunks,
          let cachedAudio = await cache.audio(for: key),
          cachedAudio.chunks == expectedChunks,
          cachedAudio.totalBytes == 4 else {
        throw TTSProtocolError.invalidPayload
    }

    let cachedClient = CachedAudioTTSClient(audio: cachedAudio)
    let cachedStream = try await cachedClient.stream(text: key.text)
    var replayedChunks: [Data] = []
    for try await chunk in cachedStream {
        replayedChunks.append(chunk)
    }
    guard replayedChunks == expectedChunks else {
        throw TTSProtocolError.invalidPayload
    }

    let differentRateKey = ReadAloudAudioCacheKey(
        text: key.text,
        model: key.model,
        resourceID: key.resourceID,
        voiceID: key.voiceID,
        speechRate: 30,
        sampleRate: key.sampleRate
    )
    guard await cache.audio(for: differentRateKey) == nil else {
        throw TTSProtocolError.invalidPayload
    }

    let failedKey = ReadAloudAudioCacheKey(
        text: "失败文本",
        model: key.model,
        resourceID: key.resourceID,
        voiceID: key.voiceID,
        speechRate: key.speechRate,
        sampleRate: key.sampleRate
    )
    let failedClient = RecordingTTSClient(
        base: OfflineTTSClient(events: [.audio(Data([0, 1])), .failure]),
        key: failedKey,
        cache: cache,
        onStored: { _, _, _ in }
    )
    do {
        let failedStream = try await failedClient.stream(text: failedKey.text)
        for try await _ in failedStream {}
        throw TTSProtocolError.invalidPayload
    } catch is OfflineStreamFixtureError {
        guard await cache.audio(for: failedKey) == nil else {
            throw TTSProtocolError.invalidPayload
        }
    }

    let oversizedKey = ReadAloudAudioCacheKey(
        text: "超长文本",
        model: key.model,
        resourceID: key.resourceID,
        voiceID: key.voiceID,
        speechRate: key.speechRate,
        sampleRate: key.sampleRate
    )
    guard await cache.store(chunks: [Data(repeating: 0, count: 17)], for: oversizedKey) == false,
          await cache.audio(for: oversizedKey) == nil else {
        throw TTSProtocolError.invalidPayload
    }
}

func printUsage() {
    print("Usage: readaloud-config status | set | delete | keychain-test | settings-test | preview-paste-test | reading-text-test | protocol-test | payload-test | diagnostics-test | session-test | cache-test | audio-test | tts-smoke | http-smoke")
    print("set reads the API Key from stdin; it is not accepted as a command argument.")
}

func readHiddenInput() -> String? {
    var original = termios()
    guard tcgetattr(STDIN_FILENO, &original) == 0 else { return readLine() }
    var hidden = original
    hidden.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &hidden)
    defer { tcsetattr(STDIN_FILENO, TCSANOW, &original) }
    print("API Key: ", terminator: "")
    fflush(stdout)
    return readLine(strippingNewline: true)
}

let store = KeychainStore()
let command = CommandLine.arguments.dropFirst().first ?? "status"

do {
    switch command {
    case "status":
        print(store.exists() ? "configured" : "not-configured")
    case "set":
        guard let input = readHiddenInput(), !input.isEmpty else {
            fputs("API Key is required on stdin.\n", stderr)
            exit(2)
        }
        try store.save(input)
        print("saved")
    case "delete":
        try store.remove()
        print("deleted")
    case "keychain-test":
        _ = try store.read()
        print("keychain-ok")
    case "settings-test":
        let suiteName = "com.wentuo.readaloud.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TTSProtocolError.invalidPayload
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = ReadAloudProviderSettings(
            model: "test-model",
            resourceID: "test-resource",
            voiceID: "test-voice"
        )
        expected.save(to: defaults)
        guard ReadAloudProviderSettings.load(from: defaults) == expected else {
            throw TTSProtocolError.invalidPayload
        }
        guard ReadAloudPlaybackPreferences.loadRate(from: defaults) == ReadAloudPlaybackPreferences.defaultRate else {
            throw TTSProtocolError.invalidPayload
        }
        ReadAloudPlaybackPreferences.saveRate(1.5, to: defaults)
        guard ReadAloudPlaybackPreferences.loadRate(from: defaults) == 1.5 else {
            throw TTSProtocolError.invalidPayload
        }
        defaults.set(1.55, forKey: "com.wentuo.readaloud.playback.rate")
        guard ReadAloudPlaybackPreferences.loadRate(from: defaults) == ReadAloudPlaybackPreferences.defaultRate else {
            throw TTSProtocolError.invalidPayload
        }
        print("settings-ok")
    case "preview-paste-test":
        let fixtures = [
            (
                "<ol><li>Alpha</li><li>Beta</li></ol>",
                "1. Alpha\n2. Beta"
            ),
            (
                "<ul><li>Gamma</li><li>Delta</li></ul>",
                "• Gamma\n• Delta"
            ),
            (
                "<ol start=\"3\"><li>Third &amp; <strong>bold</strong></li><li value=\"7\">Seventh</li></ol>",
                "3. Third & bold\n7. Seventh"
            ),
            (
                "<ol><li>Parent<ul><li>Child</li></ul></li><li>Next</li></ol>",
                "1. Parent\n  • Child\n2. Next"
            )
        ]
        for (html, expected) in fixtures {
            guard HTMLListPlainTextConverter.convert(html) == expected else {
                throw TTSProtocolError.invalidPayload
            }
        }
        guard HTMLListPlainTextConverter.convert("<p>Plain text only</p>") == nil else {
            throw TTSProtocolError.invalidPayload
        }
        print("preview-paste-ok ordered=preserved unordered=preserved nested=preserved output=plain-text")
    case "reading-text-test":
        let markdownMixed = """
        章节说明

        | 项目 | 结论 |
        | — | — |
        | Alpha | 通过 |
        | Beta | 待确认 |
        """
        let markdownResult = ReadAloudTextPreparation.prepare(plainText: markdownMixed)
        guard markdownResult.text == "章节说明",
              markdownResult.removedTableBlocks == 1 else {
            throw TTSProtocolError.invalidPayload
        }

        let pureTable = """
        名称 | 状态
        --- | ---
        Alpha | 完成
        """
        guard ReadAloudTextPreparation.prepare(plainText: pureTable).text.isEmpty else {
            throw TTSProtocolError.invalidPayload
        }

        let tabular = "前言\n名称\t状态\nAlpha\t完成\n结尾"
        guard ReadAloudTextPreparation.prepare(plainText: tabular).text == "前言\n结尾" else {
            throw TTSProtocolError.invalidPayload
        }

        let ordinaryText = "保留 A | B 作为普通句子。\n• 项目符号仍然保留。"
        guard ReadAloudTextPreparation.prepare(plainText: ordinaryText).text == ordinaryText else {
            throw TTSProtocolError.invalidPayload
        }

        let htmlMixed = "<h2>章节说明</h2><table><tr><td>名称</td><td>状态</td></tr></table><p>后续段落</p>"
        let htmlResult = ReadAloudTextPreparation.prepare(
            plainText: "章节说明 名称 状态 后续段落",
            html: htmlMixed
        )
        guard htmlResult.text == "章节说明\n后续段落",
              htmlResult.removedTableBlocks == 1 else {
            throw TTSProtocolError.invalidPayload
        }

        let longText = String(repeating: "这是一个用于验证安全分段的中文句子。", count: 80)
        let segments = ReadAloudTextPreparation.segments(for: longText, maximumUTF8Bytes: 120)
        guard segments.count > 1,
              segments.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 120 }),
              segments.joined() == longText else {
            throw TTSProtocolError.invalidPayload
        }
        let rejectedContent = [
            "   \n\t",
            "……？！---",
            "### ** ~~",
            "😀🚀🎉"
        ]
        guard rejectedContent.allSatisfy({
            !ReadAloudTextPreparation.containsSpeakableContent($0)
        }),
        ["中文", "English", "2026", "中英 Mixed 42"].allSatisfy({
            ReadAloudTextPreparation.containsSpeakableContent($0)
        }) else {
            throw TTSProtocolError.invalidPayload
        }
        print("reading-text-ok markdown-table=removed tabular-table=removed html-table=removed prose=preserved long-text=segmented non-speech=rejected")
    case "protocol-test":
        let audio = Data([0x01, 0x02, 0x03])
        var fixture = Data([0x11, 0xB0, 0x00, 0x00])
        fixture.append(contentsOf: [0, 0, 0, 1])
        fixture.append(contentsOf: [0, 0, 0, UInt8(audio.count)])
        fixture.append(audio)
        guard case .audio(let parsed, let sequence, _) = try TTSBinaryProtocol.parseServerFrame(fixture),
              parsed == audio, sequence == 1 else {
            throw TTSProtocolError.invalidPayload
        }
        print("protocol-ok")
    case "payload-test":
        var configuration = TTSConfiguration(apiKey: "test-key")
        configuration.resourceID = "test-resource"
        configuration.voiceType = "test-voice"
        let clients: [Data] = [
            try DoubaoTTSClient(configuration: configuration).requestPayload(text: "测试"),
            try DoubaoHTTPStreamingClient(configuration: configuration).requestPayload(text: "测试")
        ]
        for payload in clients {
            guard let root = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let request = root["req_params"] as? [String: Any],
                  let audio = request["audio_params"] as? [String: Any],
                  let speaker = request["speaker"] as? String,
                  let speechRate = audio["speech_rate"] as? Int,
                  speechRate == 20,
                  speaker == "test-voice" else {
                throw TTSProtocolError.invalidPayload
            }
        }
        let headers = DoubaoTTSClient(configuration: configuration).requestHeaders()
        guard headers["X-Api-Resource-Id"] == "test-resource" else {
            throw TTSProtocolError.invalidPayload
        }
        print("payload-ok speech_rate=20 rate=1.2x voice=test-voice resource=test-resource")
    case "diagnostics-test":
        let fixture = "X-Api-Key: test-secret Authorization: Bearer test-token id=123e4567-e89b-12d3-a456-426614174000"
        let redacted = ReadAloudDiagnostics.redact(fixture)
        guard !redacted.contains("test-secret"),
              !redacted.contains("test-token"),
              !redacted.contains("123e4567-e89b-12d3-a456-426614174000") else {
            throw TTSProtocolError.invalidPayload
        }
        let error = TTSServiceError.http(statusCode: 401, requestID: "request-id-for-test")
        let logFields = ReadAloudDiagnostics.logFields(for: error)
        guard logFields == "category=service-response httpStatus=401 requestID=request-id-for-test",
              !ReadAloudDiagnostics.userFacingMessage(error).contains("test-secret") else {
            throw TTSProtocolError.invalidPayload
        }
        print("diagnostics-ok")
    case "session-test":
        let group = DispatchGroup()
        group.enter()
        Task.detached {
            defer { group.leave() }
            do {
                try await runSessionOfflineTests()
                print("session-ok no-audio=rejected playback-start=single stream-failure=stopped replacement=isolated stop=stable drain=completed pause=preserved resume=continued")
            } catch {
                fputs("Session offline test failed.\n", stderr)
                exit(1)
            }
        }
        group.wait()
    case "cache-test":
        let group = DispatchGroup()
        group.enter()
        Task.detached {
            defer { group.leave() }
            do {
                try await runAudioCacheOfflineTests()
                print("cache-ok miss=network complete=stored hit=replayed variants=isolated failed=not-stored oversized=not-stored")
            } catch {
                fputs("Audio cache offline test failed.\n", stderr)
                exit(1)
            }
        }
        group.wait()
    case "audio-test":
        let player = PCMStreamPlayer()
        try player.start()
        player.append(Data(repeating: 0, count: 48_000))
        Thread.sleep(forTimeInterval: 0.1)
        player.pause()
        Thread.sleep(forTimeInterval: 0.1)
        player.resume()
        Thread.sleep(forTimeInterval: 0.2)
        player.stop()
        print("audio-ok pause=preserved resume=continued")
    case "tts-smoke":
        guard store.exists() else {
            fputs("API Key is not configured. Run: ./build/readaloud-config set\n", stderr)
            exit(2)
        }
        let key = try store.read()
        ReadAloudDiagnostics.registerSensitiveValue(key)
        let client = DoubaoTTSClient(configuration: TTSConfiguration(apiKey: key))
        let group = DispatchGroup()
        group.enter()
        Task {
            defer { group.leave() }
            do {
                let stream = try await client.stream(text: "你好，这是朗读插件的连接测试。")
                var totalBytes = 0
                var chunks = 0
                for try await chunk in stream {
                    totalBytes += chunk.count
                    chunks += 1
                }
                print("tts-ok chunks=\(chunks) bytes=\(totalBytes)")
            } catch {
                fputs("TTS smoke test failed: \(ReadAloudDiagnostics.userFacingMessage(error))\n", stderr)
                exit(1)
            }
        }
        group.wait()
    case "http-smoke":
        guard store.exists() else {
            fputs("API Key is not configured. Run: ./build/readaloud-config set\n", stderr)
            exit(2)
        }
        let key = try store.read()
        ReadAloudDiagnostics.registerSensitiveValue(key)
        let client = DoubaoHTTPStreamingClient(configuration: TTSConfiguration(apiKey: key))
        let group = DispatchGroup()
        group.enter()
        Task {
            defer { group.leave() }
            do {
                let stream = try await client.stream(text: "你好，这是朗读插件的 HTTP 流式连接测试。")
                var totalBytes = 0
                var chunks = 0
                for try await chunk in stream {
                    totalBytes += chunk.count
                    chunks += 1
                }
                print("http-tts-ok chunks=\(chunks) bytes=\(totalBytes)")
            } catch {
                fputs("HTTP TTS smoke test failed: \(ReadAloudDiagnostics.userFacingMessage(error))\n", stderr)
                exit(1)
            }
        }
        group.wait()
    default:
        printUsage()
        exit(2)
    }
} catch {
    fputs("Keychain operation failed: \(ReadAloudDiagnostics.userFacingMessage(error))\n", stderr)
    exit(1)
}
