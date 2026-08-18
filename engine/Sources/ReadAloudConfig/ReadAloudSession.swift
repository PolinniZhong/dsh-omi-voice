import Foundation

enum ReadSessionState: Equatable, Sendable {
    case idle
    case preparing
    case playing
    case paused
    case stopped
    case failed(String)
}

enum ReadAloudSessionError: LocalizedError, Sendable {
    case noPlayableAudio

    var errorDescription: String? {
        switch self {
        case .noPlayableAudio:
            return "未收到可播放音频，请重试。"
        }
    }
}

private enum AudioChunkAcceptance {
    case accepted
    case rejected
    case stale
}

/// V1 最小会话控制：一次只允许一个朗读任务，新的任务会取消旧任务。
actor ReadAloudSession {
    private(set) var state: ReadSessionState = .idle
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    func start(
        text: String,
        client: any TTSClient,
        onAudioChunk: @escaping @Sendable (Data) -> Bool,
        onPlaybackStarted: @escaping @Sendable () -> Void
    ) {
        task?.cancel()
        generation &+= 1
        let currentGeneration = generation
        state = .preparing
        task = Task { [weak self] in
            do {
                let audioStream = try await client.stream(text: text)
                var didStartPlayback = false
                for try await chunk in audioStream {
                    try Task.checkCancellation()
                    switch await self?.accept(
                        chunk,
                        generation: currentGeneration,
                        onAudioChunk: onAudioChunk
                    ) {
                    case .accepted:
                        break
                    case .rejected:
                        continue
                    case .stale, .none:
                        throw CancellationError()
                    }
                    guard !didStartPlayback else { continue }
                    didStartPlayback = true
                    guard await self?.setState(.playing, generation: currentGeneration) == true else {
                        throw CancellationError()
                    }
                    onPlaybackStarted()
                }
                try Task.checkCancellation()
                if !didStartPlayback {
                    await self?.setState(
                        .failed(ReadAloudSessionError.noPlayableAudio.localizedDescription),
                        generation: currentGeneration
                    )
                }
            } catch is CancellationError {
                await self?.setState(.stopped, generation: currentGeneration)
            } catch {
                await self?.setState(
                    .failed(ReadAloudDiagnostics.userFacingMessage(error)),
                    generation: currentGeneration
                )
            }
        }
    }

    func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
        state = .stopped
    }

    @discardableResult
    func pause() -> Bool {
        guard state == .playing else { return false }
        state = .paused
        return true
    }

    @discardableResult
    func resume() -> Bool {
        guard state == .paused else { return false }
        state = .playing
        return true
    }

    /// 等待当前 TTS 网络流结束；播放器仍可能有已排队的 PCM，需要由调用方继续等待播放完成。
    func waitUntilFinished() async {
        await task?.value
    }

    func markPlaybackCompleted() {
        guard state == .playing || state == .paused else { return }
        state = .idle
        task = nil
    }

    @discardableResult
    private func setState(
        _ nextState: ReadSessionState,
        generation expectedGeneration: UInt64
    ) -> Bool {
        guard expectedGeneration == generation else { return false }
        state = nextState
        return true
    }

    private func accept(
        _ chunk: Data,
        generation expectedGeneration: UInt64,
        onAudioChunk: @escaping @Sendable (Data) -> Bool
    ) -> AudioChunkAcceptance {
        guard expectedGeneration == generation else { return .stale }
        return onAudioChunk(chunk) ? .accepted : .rejected
    }
}
