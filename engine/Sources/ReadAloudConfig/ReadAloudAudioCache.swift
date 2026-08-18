import Foundation

struct ReadAloudAudioCacheKey: Hashable, Equatable, Sendable {
    let text: String
    let model: String
    let resourceID: String
    let voiceID: String
    let speechRate: Int
    let sampleRate: Int
}

struct ReadAloudCachedAudio: Sendable {
    let chunks: [Data]
    let totalBytes: Int
}

/// 进程内 LRU 音频缓存：默认最多 3 条、总量 ≤5MB，超出按最久未用淘汰。
/// 只存内存、不写磁盘，退出 Omi 进程即清空。
actor ReadAloudLastAudioCache {
    private struct Entry: Sendable {
        let key: ReadAloudAudioCacheKey
        let audio: ReadAloudCachedAudio
    }

    private let maximumEntries: Int
    private let maximumBytes: Int
    private var entries: [ReadAloudAudioCacheKey: Entry] = [:]
    private var order: [ReadAloudAudioCacheKey] = []
    private var totalBytes = 0

    init(maximumEntries: Int = 3, maximumBytes: Int = 5 * 1024 * 1024) {
        self.maximumEntries = maximumEntries
        self.maximumBytes = maximumBytes
    }

    func audio(for key: ReadAloudAudioCacheKey) -> ReadAloudCachedAudio? {
        guard let entry = entries[key] else { return nil }
        touch(key)
        return entry.audio
    }

    @discardableResult
    func store(chunks: [Data], for key: ReadAloudAudioCacheKey) -> Bool {
        let bytes = chunks.reduce(into: 0) { $0 += $1.count }
        guard !chunks.isEmpty, bytes > 0, bytes <= maximumBytes else {
            if entries[key] != nil { remove(key) }
            return false
        }
        if let existing = entries[key] {
            totalBytes -= existing.audio.totalBytes
        }
        entries[key] = Entry(key: key, audio: ReadAloudCachedAudio(chunks: chunks, totalBytes: bytes))
        touch(key)
        totalBytes += bytes
        evictIfNeeded()
        return true
    }

    private func touch(_ key: ReadAloudAudioCacheKey) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }

    private func remove(_ key: ReadAloudAudioCacheKey) {
        if let entry = entries.removeValue(forKey: key) {
            totalBytes -= entry.audio.totalBytes
        }
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
    }

    private func evictIfNeeded() {
        while entries.count > maximumEntries || totalBytes > maximumBytes {
            guard let oldest = order.first else { break }
            remove(oldest)
        }
    }
}

struct CachedAudioTTSClient: TTSClient {
    let audio: ReadAloudCachedAudio

    func stream(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in audio.chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

struct RecordingTTSClient: TTSClient {
    let base: any TTSClient
    let key: ReadAloudAudioCacheKey
    let cache: ReadAloudLastAudioCache
    let onStored: @Sendable (Bool, Int, Int) -> Void

    func stream(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        let source = try await base.stream(text: text)
        return AsyncThrowingStream { continuation in
            let worker = Task {
                var chunks: [Data] = []
                do {
                    for try await chunk in source {
                        try Task.checkCancellation()
                        chunks.append(chunk)
                        continuation.yield(chunk)
                    }
                    try Task.checkCancellation()
                    let stored = await cache.store(chunks: chunks, for: key)
                    onStored(stored, chunks.count, chunks.reduce(into: 0) { $0 += $1.count })
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
