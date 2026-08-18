import Foundation

struct ReadAloudPlaybackPreferences: Sendable {
    static let defaultRate: Float = 1.2

    private static let rateKey = "com.wentuo.readaloud.playback.rate"

    static func loadRate(from defaults: UserDefaults = .standard) -> Float {
        guard let storedRate = defaults.object(forKey: rateKey) as? NSNumber,
              let rate = validRate(storedRate.floatValue) else {
            return defaultRate
        }
        return rate
    }

    static func saveRate(_ rate: Float, to defaults: UserDefaults = .standard) {
        guard let rate = validRate(rate) else { return }
        defaults.set(rate, forKey: rateKey)
    }

    private static func validRate(_ rate: Float) -> Float? {
        guard rate.isFinite else { return nil }
        let step = Int((rate * 10).rounded())
        let normalizedRate = Float(step) / 10
        guard (10...20).contains(step), abs(rate - normalizedRate) < 0.0001 else {
            return nil
        }
        return normalizedRate
    }
}

struct ReadAloudProviderSettings: Sendable, Equatable {
    static let defaultModel = "seed-tts-1.0"
    static let defaultResourceID = "volc.service_type.10029"
    static let defaultVoiceID = "zh_female_shuangkuaisisi_moon_bigtts"

    private static let modelKey = "com.wentuo.readaloud.provider.model"
    private static let resourceIDKey = "com.wentuo.readaloud.provider.resource-id"
    private static let voiceIDKey = "com.wentuo.readaloud.provider.voice-id"

    var model: String
    var resourceID: String
    var voiceID: String

    static var defaults: ReadAloudProviderSettings {
        ReadAloudProviderSettings(
            model: defaultModel,
            resourceID: defaultResourceID,
            voiceID: defaultVoiceID
        )
    }

    static func load(from defaults: UserDefaults = .standard) -> ReadAloudProviderSettings {
        let fallback = Self.defaults
        return ReadAloudProviderSettings(
            model: normalized(defaults.string(forKey: modelKey)) ?? fallback.model,
            resourceID: normalized(defaults.string(forKey: resourceIDKey)) ?? fallback.resourceID,
            voiceID: normalized(defaults.string(forKey: voiceIDKey)) ?? fallback.voiceID
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: Self.modelKey)
        defaults.set(resourceID, forKey: Self.resourceIDKey)
        defaults.set(voiceID, forKey: Self.voiceIDKey)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
