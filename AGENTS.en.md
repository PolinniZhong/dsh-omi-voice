# AGENTS.md — dsh-omi-voice

> Project instructions for AI coding agents (Codex / Claude Code / DSH, etc.). Read this file before modifying the repository.

## One-liner

An in-conversation read-aloud plugin for DeepSeek Harness: tap 🔊 next to a reply to hear it spoken in a natural Doubao TTS voice (tap-to-read only, BYOK). **The plugin (JS) and the local engine (Swift) live in one repo.**

## Repository layout

```
Root (plugin, dsh.bundle)
├── client/lib/client.js   # Client: 🔊 button, three states (play/pause/resume), status polling
├── host/lib/index.js      # Minimal Node entry (no-op placeholder)
├── cordis.patch.yml       # Mounts the host entry
├── package.json           # dsh.bundle.patch + dsh.client.platform: web
├── docs/API.md            # Local protocol (single source of truth)
└── docs/DESIGN.md | DECISIONS.md | MEMORY.md | HANDOFF.md

engine/                    # Local engine (macOS app, Swift)
├── Sources/               # ReadAloudService (app shell) + ReadAloudConfig (engine core)
├── Resources/             # Icons (OmiDSH.icns / Omi_logo.svg) + Info.plist
├── build/build-service.sh # Build script (swiftc full compile + codesign)
└── VERSION                # Engine version (must match plugin package.json; currently 0.1.3)
```

## Key conventions

1. **Protocol single source of truth**: any endpoint/field change must first update `docs/API.md`, then sync the engine (`engine/Sources/ReadAloudService/LocalTTSService.swift`) and the plugin (`client/lib/client.js`).
2. **Engine build**: `engine/build/build-service.sh`, output `build/ReadAloudService.app`, install to `~/Applications/Omi DSH.app` (`ditto` + re-`codesign`).
3. **Version parity**: the plugin `package.json` `version` and the engine `engine/VERSION` must stay in sync (currently `0.1.2`).
4. **Tap-to-read only, no auto-read**: product decision since v0.1.1 — do not reintroduce auto-read.
5. **The key never leaves the machine**: the Doubao key lives only in the Omi engine's Keychain; the plugin has zero key access; logs/responses never carry the key.

## Publishing (important)

- Local `git push` to GitHub may be rate-limited or blocked; use the **GitHub Contents API** (single file) or the **git data API** (blobs/trees/commits, one bulk commit) instead — see `docs/MEMORY.md`.
- After uploading, point the tag at the latest `main` (`PATCH /git/refs/tags/vX.Y.Z`, `force: true`).

## Common change paths

- Button behavior/icons → `client/lib/client.js` (run `node --check` after editing)
- Engine logic/endpoints → `engine/Sources/...`, rerun `build-service.sh` + reinstall
- Protocol → `docs/API.md` first

## See also

- Architecture/design: `docs/DESIGN.md`
- Decision log: `docs/DECISIONS.md`
- Long-term knowledge (gotchas & conclusions): `docs/MEMORY.md`
- Handoff/continuation: `docs/HANDOFF.md`
