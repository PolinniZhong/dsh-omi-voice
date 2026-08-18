import Foundation

/// 将会话状态、TTS 音频流和 macOS 播放器连接起来的最小控制器。
final class ReadAloudController: @unchecked Sendable {
    let session: ReadAloudSession
    let player: any PCMStreamingPlaying

    init(
        session: ReadAloudSession = ReadAloudSession(),
        player: any PCMStreamingPlaying = PCMStreamPlayer()
    ) {
        self.session = session
        self.player = player
    }

    func start(
        text: String,
        client: any TTSClient,
        onPlaybackStarted: @escaping @Sendable () -> Void
    ) async throws {
        try player.start()
        await session.start(
            text: text,
            client: client,
            onAudioChunk: { [player] chunk in player.append(chunk) },
            onPlaybackStarted: onPlaybackStarted
        )
    }

    func stop() async {
        await session.stop()
        player.stop()
    }

    @discardableResult
    func pause() async -> Bool {
        guard await session.pause() else { return false }
        player.pause()
        return true
    }

    @discardableResult
    func resume() async -> Bool {
        guard await session.resume() else { return false }
        player.resume()
        return true
    }

    func waitUntilFinished() async {
        await session.waitUntilFinished()
        switch await session.state {
        case .playing, .paused:
            await player.waitUntilDrained()
            await session.markPlaybackCompleted()
        case .failed:
            // 网络流失败或没有任何有效 PCM 时，不继续播放已排队的残余音频。
            player.stop()
        case .idle, .preparing, .stopped:
            break
        }
    }

    func setRate(_ rate: Float) {
        player.setRate(rate)
    }
}
