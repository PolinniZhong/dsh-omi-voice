[中文](HANDOFF.md) | **English**

# dsh-omi-voice Handoff (HANDOFF)

> Current project state + how to continue. Read this and `AGENTS.md` before taking over.

## Current state (2026-08-18, updated to 2026-08-27)

- **Version**: v0.1.3 (plugin `package.json` and engine `engine/VERSION` unified).
- **Published**: GitHub public repo `PolinniZhong/dsh-omi-voice`, containing plugin (root) + engine (engine/) + docs + screenshots/GIF + Release.
- **Features landed & verified**: tap-to-read / pause / resume / stop, failure-reason feedback, reads only the final answer, code/table/diagram filtering, LRU cache, dedup/throttle, BYOK.
- **UI i18n (2026-08-27)**: engine UI follows the system language (NSLocalizedString + `en.lproj` + `zh-Hans.lproj`), English system→English, Chinese system→Chinese; docs are bilingual (README/AGENTS/engine README + switching links). **Synced to GitHub** (main.swift + both .lproj + build-service.sh).
- **Local runtime state**: engine installed at `~/Applications/Omi DSH.app` (port 8765); desktop installs the plugin via `link:`.

## To-dos (by priority)

1. **PR status**:
   - ✅ **beancookie/awesome-dsh-plugin #75 merged (2026-08-19)** — plugin is in the DSH main plugin list.
   - ✅ fendouai #20 included: PR closed but content manually merged by the maintainer into main (commit `ada8503`, category `ui`), see `data/plugins.json`.
   - ✅ **npm published (2026-08-25): `dsh-omi-voice@0.1.2`**, `repository` linked to GitHub; install `dsh plugin add dsh-omi-voice`.
   - ⏳ **awesome-dsh-plugin org main list PR #3148** (CI passed, conflict-free, awaiting maintainer merge, category `voice`).
   - ⏳ libukai #41 awaiting maintainer merge (waiting on them, no action needed).
2. **Official post**: deepseek-ai/deepseek-harness discussions #3084 posted (GIF demo + "lightweight, native-like" positioning); reply to it to boost visibility.
3. **Promo articles**: ✅ **published (2026-08-25)** — Xiaohongshu/WeChat/Zhihu (written by the user, drove the main traffic, repo 2★ → 46★). After PR #3148 merges, a follow-up "selected into the official list" article can ride the second wave.
4. **Optional enhancements (v1.1)**: speed UI, skip-paragraph, port config UI, auth token, Windows engine.
5. **Fork cleanup**: ✅ **done (2026-08-25, user deleted manually)** — removed `awesome-dsh-plugin` (beancookie), `awesome-deepseek-harness-fendouai` (fendouai), `awesome-deepseek-harness-dominic` (Dominic; note the real fork name is `-dominic`, not `-1`); **kept** `awesome-deepseek-harness` (libukai #41 unmerged) and `awesome-dsh-plugin-org` (PR #3148 unmerged).

> Note: on 2026-08-25 the workspace was renamed `首次开箱` → `Omi-DSH 端到端` (the desktop profile's link and new symlink were synced; takes effect after the desktop restarts); the old dev copy folder `Omi-dsh 端到端版本` was deleted (the v0.2.0 original is elsewhere, code is in engine/, zero loss).

## How to continue development

1. Read `AGENTS.md` → `docs/DESIGN.md` (architecture) → `docs/MEMORY.md` (gotchas).
2. Plugin: edit `client/lib/client.js` (run `node --check` after); desktop restart takes effect (link install).
3. Engine: `engine/Sources/...` → `engine/build/build-service.sh` → `ditto` to `~/Applications/Omi DSH.app` → restart.
4. Protocol: change `docs/API.md` first, then sync engine + plugin.
5. Publishing: see `docs/MEMORY.md` (Contents/git data API + update tag).

## Key file index

| Look for | Go to |
|---|---|
| Architecture/data flow | `docs/DESIGN.md` |
| Why this way | `docs/DECISIONS.md` |
| Gotchas/publishing methods | `docs/MEMORY.md` |
| Local protocol | `docs/API.md` |
| Engine build | `engine/README.md`, `engine/build/build-service.sh` |
| Button/interaction | `client/lib/client.js` |
| Engine HTTP service | `engine/Sources/ReadAloudService/LocalTTSService.swift` |
