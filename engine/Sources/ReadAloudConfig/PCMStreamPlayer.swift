import AVFoundation
import Foundation

private final class PCMConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var wasSupplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

enum PCMStreamPlayerError: LocalizedError {
    case noOutputDevice

    var errorDescription: String? {
        switch self {
        case .noOutputDevice:
            return "没有可用的音频输出设备。请连接扬声器或耳机后重试。"
        }
    }
}

protocol PCMStreamingPlaying: Sendable {
    func start() throws
    @discardableResult func append(_ data: Data) -> Bool
    func pause()
    func resume()
    func stop()
    func waitUntilDrained() async
    func setRate(_ rate: Float)
}

/// V1 播放器假定豆包返回 24 kHz、单声道、16-bit PCM。
/// MP3/Opus 等格式应在 Provider 层解码后再传入此播放器。
final class PCMStreamPlayer: PCMStreamingPlaying, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var started = false
    private var connected = false
    private var playbackFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var playbackGeneration: UInt64 = 0
    private var pendingBufferCount = 0
    private var paused = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(sampleRate: Double = 24_000, channels: AVAudioChannelCount = 1) {
        format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )!
        engine.attach(player)
        engine.attach(timePitch)
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        let deviceFormat = engine.outputNode.outputFormat(forBus: 0)
        guard deviceFormat.channelCount > 0, deviceFormat.sampleRate > 0,
              let negotiatedFormat = AVAudioFormat(
                standardFormatWithSampleRate: deviceFormat.sampleRate,
                channels: deviceFormat.channelCount
              ) else {
            throw PCMStreamPlayerError.noOutputDevice
        }
        if !connected {
            // 播放图使用当前硬件的标准格式；豆包 PCM 在 append 时转换到该格式。
            // 既不把 24 kHz 强塞给设备，也不查询未配置 bus 的 inputFormat。
            engine.connect(player, to: timePitch, format: negotiatedFormat)
            engine.connect(timePitch, to: engine.mainMixerNode, format: negotiatedFormat)
            connected = true
        }
        playbackFormat = negotiatedFormat
        converter = AVAudioConverter(from: format, to: negotiatedFormat)
        engine.prepare()
        try engine.start()
        player.play()
        started = true
        paused = false
    }

    @discardableResult
    func append(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return false }
        let frameCount = data.count / bytesPerFrame
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let destination = buffer.int16ChannelData?.pointee else { return false }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.baseAddress else { return }
            destination.update(from: source.assumingMemoryBound(to: Int16.self), count: frameCount * Int(format.channelCount))
        }
        guard let converter, let playbackFormat else {
            return scheduleForPlayback(buffer)
        }

        let outputCapacity = AVAudioFrameCount(ceil(Double(frameCount) * playbackFormat.sampleRate / format.sampleRate)) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: outputCapacity) else { return false }
        let input = PCMConverterInput(buffer: buffer)
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if input.wasSupplied {
                status.pointee = .noDataNow
                return nil
            }
            input.wasSupplied = true
            status.pointee = .haveData
            return input.buffer
        }
        guard conversionError == nil, converted.frameLength > 0 else { return false }
        return scheduleForPlayback(converted)
    }

    /// 仅暂停渲染，保留已经排入播放器的 PCM buffer 与当前位置。
    func pause() {
        lock.lock()
        guard started, !paused else {
            lock.unlock()
            return
        }
        paused = true
        lock.unlock()
        player.pause()
    }

    /// 从暂停位置继续渲染，不重新调度或重放已有 PCM buffer。
    func resume() {
        lock.lock()
        guard started, paused else {
            lock.unlock()
            return
        }
        paused = false
        lock.unlock()
        player.play()
    }

    func stop() {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        playbackGeneration &+= 1
        pendingBufferCount = 0
        waiters = drainWaiters
        drainWaiters.removeAll()
        started = false
        paused = false
        lock.unlock()

        player.stop()
        engine.stop()
        waiters.forEach { $0.resume() }
    }

    /// 等待最后一个已排入 AVAudioPlayerNode 的 PCM buffer 真正播放完毕。
    func waitUntilDrained() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if pendingBufferCount == 0 {
                lock.unlock()
                continuation.resume()
            } else {
                drainWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func setRate(_ rate: Float) {
        timePitch.rate = min(max(rate, 0.5), 2.0)
    }

    private func scheduleForPlayback(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.lock()
        guard started else {
            lock.unlock()
            return false
        }
        let generation = playbackGeneration
        pendingBufferCount += 1
        lock.unlock()

        player.scheduleBuffer(
            buffer,
            at: nil,
            options: [],
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            self?.didPlayBuffer(generation: generation)
        }
        return true
    }

    private func didPlayBuffer(generation: UInt64) {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        guard generation == playbackGeneration else {
            lock.unlock()
            return
        }
        pendingBufferCount = max(0, pendingBufferCount - 1)
        if pendingBufferCount == 0 {
            waiters = drainWaiters
            drainWaiters.removeAll()
        } else {
            waiters = []
        }
        lock.unlock()
        waiters.forEach { $0.resume() }
    }
}
