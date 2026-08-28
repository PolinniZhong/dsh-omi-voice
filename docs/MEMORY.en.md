[中文](MEMORY.md) | **English**

# dsh-omi-voice Long-term Knowledge (MEMORY)

> Gitches and verified conclusions that remain valid across versions. Append in reverse-chronological order.

## Release & promotion (2026-08-25)

- **npm publishing basics**: package name `dsh-omi-voice` (unclaimed); `package.json` must have a `repository` field (links GitHub so npm downloads mirror back to the repo); `files` is trimmed to `["host","client","cordis.patch.yml","docs/API.md","README.md","LICENSE"]` (don't bundle docs/assets images); verify with `npm pack --dry-run` before publishing; npm login user `polinni`.
- **org main list (awesome-dsh-plugin) submission**: data-driven — one YAML per plugin at `data/plugins/<owner>__<repo>.yml` (category `voice`, `description.en` required, quote values containing `: `, end with a period, no marketing words); after editing run `npm ci && node scripts/generate-readme.mjs` to regenerate the README and commit together; optionally add a GitHub-hosted screenshot URL to `data/screenshots.json`. Submitted PR #3148 (CI passed).
- **⚠️ org-list PRs conflict repeatedly (important)**: upstream is very active (12K★, others' PRs keep merging), so generated README/data files always collide. **Fix flow (2 min each time)**: ① pull latest upstream tarball (`codeload.github.com/.../tar.gz/refs/heads/main`) ② rewrite YAML + screenshots.json entries ③ `npm ci && node scripts/generate-readme.mjs` regenerate README ④ use git data API with "latest upstream sha as parent + upstream tree as base" to rebuild the fork branch and `force:true` update → PR becomes "latest upstream + my change", naturally conflict-free. Chosen plan: **report each conflict and I'll re-run**.
- **Screenshot rule (maintainer fkysly 2026-08-26, important)**: **do not edit upstream `data/screenshots.json`** (shared by everyone; 108 PRs fight over the same file, must conflict) — instead put a `screenshots.json` in **the plugin repo root** (relative paths to in-repo images, e.g. `docs/assets/reading.png`), picked up on the next build; changing screenshots only pushes your own repo. Done: `dsh-omi-voice/screenshots.json`. PR #3148 now only has YAML + the two generated READMEs (CLEAN, CI green, awaiting merge).
- When fixing PR conflicts: python urllib may throw SSL cert errors (framework Python lacks certifi) — use **`gh api --input <json file>`** (printf the tree/commit JSON body first) instead; `gh api -F` with JSON arrays is unreliable.
- **npm trick in this env**: the sandbox blocks `~/.npm` writes; use `npm --cache /tmp/npm-cacheX <cmd>` to work around.
- **Sandbox network limits**: `git push` and `github.com/login/oauth/access_token` (gh token scope refresh) time out here — token widening (e.g. `delete_repo`) must be run by the user **in their own terminal** with `gh auth refresh -h github.com -s <scope>`; can't be done in this env.
- **Sandbox & workspace rename**: after a workspace folder rename, the sandbox stays bound to the old path, so writes to the new path intermittently fail with "Operation not permitted / sandbox-exec ENOENT" — retry with full tool permissions, or use absolute paths + explicit workdir.

- **dsh.so marketplace listed (2026-08-27)**: https://www.dsh.so/artifact/dsh-omi-voice — auto-listed + static security scan clean (100/100) + L4 sandbox install verified (win32/x64, DSH 0.1.1-rc.2); README embeds its security/install badges (bot ihuajiu sent issue #1 as a notice; closing the issue unsubscribes).

## Plugin-list inclusion (awesome ecosystem)

- **fendouai/awesome-deepseek-harness is data-driven**: README & resource pages are auto-generated from `data/*.json`; **update entries via `data/plugins.json` PR, don't hand-edit README** (maintainer rule).
- **Inclusion status (2026-08-18)**: fendouai PR #20 was closed but its content was manually merged into main by the maintainer (commit `ada8503`), entry in `data/plugins.json` (category `ui`, capabilities `ui`+`multimodal`, EN/CN descriptions accurate), and a dedicated resource page `docs/en/resources/dsh-omi-voice.md` was generated.
- **PR closed ≠ not included**: data-driven list maintainers often "close the PR + manually merge into their batch commit" — check the commit for the entry, don't just look at PR status.
- Same-maintainer ecosystem note: **same-name repo forks collide** — use `gh repo fork owner/repo --fork-name <custom>`.

## Release & toolchain

- **Local `git push` is rate-limited/blocked**: git uploads to GitHub time out ("Recv failure / too slow"), but `gh api`/`curl`/Contents API work. For publishing:
  - Single file: `gh api --method PUT /repos/PolinniZhong/dsh-omi-voice/contents/<path>` (base64 content)
  - Batch: git data API (`POST /git/blobs` → `POST /git/trees` → `POST /git/commits` → `PATCH /git/refs/heads/main`)
- After uploading **update the tag to latest main**: `PATCH /git/refs/tags/vX.Y.Z`, `force:true`.
- Same-name awesome repos (multiple `awesome-deepseek-harness`) fork to one account and **collide**: the second fork auto-renames to `xxx-1`. Use `gh repo fork owner/repo --fork-name <custom>`.

## Engine (Swift) gotchas

- **Keychain v3 entries carry an app ACL** (old makeStableAccess), so the new dev build can't read them → the user **re-saves the key once** in the new build's settings (creating an ACL-free v4 entry).
- **data protection keychain always fails under ad-hoc signature** (errSecMissingEntitlement -34018): `usesDataProtectionKeychain` must stay `false`.
- Build scripts live in `engine/build/` and were deleted once; they're in git, so `git checkout -- build/` restores them (but the restored copy is the original — re-apply the LocalTTSService.swift / `-framework Network` / OmiDSH.icns patches).
- The engine app is `.accessory` (no Dock icon); the menu-bar icon is `Omi_logo.svg`, the app/Finder icon is `OmiDSH.icns` (CFBundleIconFile).
- Engine startup is slow: after `open`, port 8765 may take 5–7s to be ready; wait or retry before testing.

## Icon / visual gotchas

- The `<filter>` in `omi_dsh_app_logo.svg` (two inner shadows) renders as a stroke/outline around the whale; a clean full-bleed whale needs the tile + filter removed and the viewBox tightened.
- A `fill="white"` whale is **invisible on a light menu bar**; use the white version for the top bar (dark menu bar) and the dark-gray gradient for the app icon.
- GitHub README **can't render SVG/video**: the logo uses PNG (converted to `docs/assets/logo.png`), videos become animated GIFs (`ffmpeg` two-pass palette).
- macOS's bundled curl doesn't support `--jq`; use `gh api ... --jq`.

## Plugin (client.js) conventions

- Client is `window.__ModuleLoader__.load({id, factory})` with `exports.apply` + `exports.inject = ["slots"]`.
- Reply text extraction: `props.useSession((s) => findMessageText(s, props.messageId))`, only `kind==='text'` blocks; **don't provide a `node.text` full-text fallback** (it would read tool logs).
- The engine is the authoritative player: sync button state by polling `/v1/status`, don't rely only on optimistic state.

## Desktop install (dev mode)

- `dsh plugin --profile web add <local absolute path>` installs via `link:` → editing client.js needs no reinstall, just restart the desktop.
- The desktop app's packaged dsh CLI entry is `node_modules/@deepseek-ai/dsh/lib/bin.js` (not `.bin/dsh`, which errors due to directory layout); use the bundled `dependencies/pnpm/bin/pnpm.cjs` for pnpm.

## Localization (engine UI)

- **"Chinese literal as key"**: `NSLocalizedString("Chinese", comment: "")` + `en.lproj/Localizable.strings` (Chinese→English) **+ `zh-Hans.lproj/Localizable.strings` (key=Chinese)**.
- ⚠️ **Only adding en.lproj is wrong (bug lesson)**: the macOS Bundle determines the app's available languages from `.lproj` dirs; with only en.lproj it's treated as "English-only" and **always shows English even on a Chinese system** (confirmed by the user). **Both .lproj must be added** so it switches by system language (zh-Hans → Chinese, en → English).
- **Interpolated strings can't be translated this way**: in `"快捷键...（\(status)）"` the `\(...)` is evaluated first and becomes the key → not found. Keep them as-is or use `String(format:)`; when scripting, skip strings containing `\`.
- **build-service.sh must copy both .lproj**: `cp -R "$ROOT/Resources/en.lproj" ...` and `cp -R "$ROOT/Resources/zh-Hans.lproj" ...`, otherwise the bundle lacks the language resources.
- **Verification**: use `Bundle.preferredLocalizations(from: systemLangs, forPreferences: bundle.localizations)` (the app's real runtime logic); `Bundle(path:)` + script `UserDefaults.set(AppleLanguages)` **can't drive a non-main bundle's resolution** — don't use that to test (misleading).
- Doc internationalization: `README.en.md` / `AGENTS.en.md` / `engine/README.en.md`, with `中文 | [English](...)` switching links at the top of the Chinese originals.
