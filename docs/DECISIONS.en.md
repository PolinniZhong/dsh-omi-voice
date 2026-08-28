[中文](DECISIONS.md) | **English**

# dsh-omi-voice Decision Log (DECISIONS)

> Records locked-in decisions and their rationale. New decisions are appended (reverse-chronological).

## 2026-08-18 (v0.1.0 → v0.1.2 development)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Engine playback** (plugin only sends commands; audio is played locally by the Omi engine) | Reuses the existing PCM player/speed/pause/cache; zero audio-format work; browser playback deferred to v2 |
| D2 | **Removed auto-read**, tap-to-read only | Product decision reversal: default-off still wasn't enough, so removed entirely (v0.1.1), avoiding "documented feature that doesn't exist" |
| D3 | Read only the final answer (`kind==='text'` block filter) | Misreading tool logs/thinking was a real bug; engine cleaning can't fix it, must filter in the plugin's block-extraction layer |
| D4 | Code fences/tables/box-drawing/ASCII graphics **filtered before the request** | These can't be spoken and waste quota; pure such content returns `invalid_text` and never hits Doubao |
| D5 | In-memory **LRU cache 3 items / ≤5MB** | Re-reading recent content doesn't re-bill; pure memory, zero disk, cleared on quit (user's "minimal cache" principle) |
| D6 | Keychain **data protection off** | ad-hoc signing has no keychain-access-groups entitlement; enabling it breaks save with -34018 |
| D7 | Fixed port **8765** + CORS allows any loopback | Avoids hard-to-diagnose "Load failed" when the DSH port changes; threat model unchanged (still 127.0.0.1 only) |
| D8 | Same-text 3s dedup + 300ms throttle between reads | Prevents rapid/repeat requests from burning Doubao quota |
| D9 | Engine **merged into the same repo** `engine/` | User request: one repo for plugin + engine; install `&path:/` stays unchanged |
| D10 | Plugin/engine version **unified at 0.1.2** | Removes confusion from two version schemes |
| D11 | Tagline「**沉浸式听朗读 · 豆包音质**」 | Written from the user's scenario (Vibe Coding read-aloud, commute review), replacing the vague "有温度的对话内朗读" |
| D12 | No auth token (v1) | Local loopback only, key never leaves the machine, text not persisted; impact is only "local speaker makes a sound" — acceptable |
| D13 | UI localization: **follow system language** (NSLocalizedString + `en.lproj` + **`zh-Hans.lproj`**, Chinese string as the key) | Standard for international distribution; **both en + zh-Hans .lproj are required** (only en is treated as English-only and always shows English — a real test bug); en system → English, zh-Hans system → Chinese, zero manual switching |

## Pending (not yet executed)

- Auth token (mandatory if a "read local file" capability is added later)
- Speed UI, skip-paragraph, port config UI (v1.1)
- Whether the Omi DSH build should stop registering the ⌥⇧Q hotkey (confusable when coexisting with the v0.1.3 clipboard build)
