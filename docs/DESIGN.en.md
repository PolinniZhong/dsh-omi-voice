[中文](DESIGN.md) | **English**

# dsh-omi-voice Architecture (DESIGN)

> Single source of truth for architecture & design. Update this first before changing architecture.

## 1. Overall architecture

```
┌──────────────────────────────┐   localhost:8765   ┌──────────────────────────────┐
│ DeepSeek Harness desktop      │ ─────────────────▶ │ Omi DSH engine (macOS app)    │
│  dsh-omi-voice plugin (client)│  /v1/speak/pause/  │  LocalTTSService (added)       │
│  🔊 button (play/pause/resume)│    resume/stop/status│  ├─ ReadAloudTextPreparation │
│  status polling / failure toast│ ◀──────────────── │  ├─ DoubaoHTTPStreamingClient │
└──────────────────────────────┘    status/error JSON │  ├─ PCMStreamPlayer → speaker │
                                                      │  └─ KeychainStore (key, local)│
                                                      └──────────────┬───────────────┘
                                                                     ▼ Doubao TTS cloud
                                                        openspeech.bytedance.com (WSS/HTTPS)
```

## 2. Component responsibilities

| Component | File | Responsibility |
|---|---|---|
| Plugin (client) | `client/lib/client.js` | Extracts the final answer text, three-state button, polls engine status, failure toast; zero key access |
| Plugin (Node placeholder) | `host/lib/index.js` | No-op placeholder so the bundle mounts cleanly |
| Engine HTTP service | `engine/Sources/ReadAloudService/LocalTTSService.swift` | NWListener minimal HTTP/1.1, routes `/v1/*`, CORS loopback, dedup/throttle |
| Engine read pipeline | `engine/Sources/ReadAloudConfig/*` | Clean → segment → Doubao streaming synthesis → local playback (AVAudioEngine); cache/speed/pause |
| App shell | `engine/Sources/ReadAloudService/main.swift` | Menu bar, settings, Keychain, wires LocalTTSService into the existing pipeline |

## 3. Data flow (one tap-to-read)

1. Plugin `findMessageText` extracts `kind === 'text'` blocks from the assistant node in the session snapshot (excluding tool-call/tool-result/think, etc.).
2. `POST /v1/speak {text}` → engine validates (content→key) → `ReadAloudTextPreparation` cleans (tables/code fences/diagrams) → segments into ≤900-byte chunks.
3. Reads the Doubao key from Keychain → builds the request → WSS streams PCM back → `PCMStreamPlayer` plays as it arrives.
4. Plugin polls `/v1/status` every second, syncing playing/paused/idle/failed states; auto-resets on finish, toasts `message` on failure.

## 4. Protocol v1 (single source of truth: docs/API.md)

- `GET /v1/status`: health + `state` (idle/preparing/playing/paused/failed) + `message` + `keyConfigured`
- `POST /v1/speak`: read (interrupt semantics), returns `segments`
- `POST /v1/pause` / `/v1/resume`: pause/resume (keeps position)
- `POST /v1/stop`: stop (idempotent)
- Listens on 127.0.0.1 only; CORS allows any loopback origin

## 5. Security & privacy boundary

- Doubao key lives only in the macOS Keychain, never in logs/responses/plugin.
- No auth token (v1): any local process can trigger TTS. Impact is only "the local speaker makes a sound" — no data exfiltration; if a "read local file" capability is added later, a token becomes mandatory.
- Text only flows in memory; never written to disk or history.

## 6. Cost-control design

- Manual tap-to-read only, no auto-read.
- Engine in-memory LRU cache: 3 items / ≤5MB, LRU eviction, cleared on quit.
- Same-text 3s dedup + 300ms throttle between any reads.
- Content with nothing speakable (pure tables/code/diagrams) returns `invalid_text` before any Doubao request.

## 7. Key constraints

- Engine is macOS (Apple Silicon) only. Plugin works with any `dsh web`.
- Version: plugin `package.json` and engine `engine/VERSION` must match.
- Protocol changes sync in three places: API.md → LocalTTSService → client.js.

## 8. Localization / i18n

- Engine UI **follows the system language** automatically: `main.swift` uses `NSLocalizedString("Chinese", comment: "")` (Chinese string is the key), paired with `Resources/en.lproj/Localizable.strings` (Chinese→English) **+ `zh-Hans.lproj/Localizable.strings` (key=Chinese value)**.
- ⚠️ **Both en + zh-Hans .lproj are required**: macOS's Bundle determines the app's available languages from `.lproj` dirs; **with only en.lproj the app is considered "English-only" and always resolves to English regardless of the system language (real bug lesson)**; with both, it switches correctly by system language (zh-Hans system → Chinese, en system → English).
- Build: `engine/build/build-service.sh` copies both `en.lproj` and `zh-Hans.lproj` into the app bundle's `Contents/Resources`.
- Scope: user-visible UI (settings panel/status/menu/buttons/error hints/accessibility labels); logs (`serviceLog`) and dev diagnostics stay Chinese.
- **Gotcha**: strings with interpolation (`\(...)`) cannot use "literal-as-key" (the expanded value becomes the key and won't be found); keep them as-is or use `String(format:)`.
