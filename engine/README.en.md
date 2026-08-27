# Omi DSH Engine (engine)

The **local read-aloud engine** for dsh-omi-voice: a macOS menu-bar app that bundles Doubao TTS synthesis with a local HTTP service (`127.0.0.1:8765`), powering in-conversation read-aloud for the dsh-omi-voice plugin in DeepSeek Harness.

## Features

- In-conversation read / pause / resume (resume from where you paused) / stop
- Reads only the final answer: tool logs, code fences, tables, and box-drawing/ASCII graphics are filtered locally before the request
- Doubao TTS 1.0 (`seed-tts-1.0`) streaming synthesis + local playback (AVAudioEngine, adjustable speed)
- In-memory LRU cache (3 items / 5MB, cleared on quit) + same-text dedup to avoid repeat billing
- BYOK: the Doubao API Key stays in the macOS Keychain, never leaves your machine

## Build & install

Prerequisites: Apple Silicon Mac, macOS 13+, Xcode (or Command Line Tools), and an enabled Doubao "Speech Synthesis 1.0" service.

```bash
./build/build-service.sh
mkdir -p "$HOME/Applications"
ditto build/ReadAloudService.app "$HOME/Applications/Omi DSH.app"
open "$HOME/Applications/Omi DSH.app"
```

On first use, save your Doubao key once under "Settings > API Key"; consider enabling "Settings > App Preferences > Launch at login".

## Local service protocol

See [docs/API.md](../docs/API.md) at the repo root (`/v1/status`, `/v1/speak`, `/v1/pause`, `/v1/resume`, `/v1/stop`). The protocol is the only contract between the plugin and the engine.

## Directory

- `Sources/` — Swift sources (`ReadAloudService` app shell + `ReadAloudConfig` engine core)
- `Resources/` — icons (`OmiDSH.icns`, `Omi_logo.svg`) and `Info.plist`
- `build/` — build script (`build-service.sh`)
