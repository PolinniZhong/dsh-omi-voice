中文 | [English](AGENTS.en.md)

# AGENTS.md — dsh-omi-voice

> 给 AI 编码代理（Codex / Claude Code / DSH 等）的项目说明。修改本仓库前请先读本文件。

## 一句话

DeepSeek Harness 对话内朗读插件：点回复旁 🔊，用豆包 TTS 自然音色朗读 AI 回复（仅点读，BYOK）。**插件（JS）与本地引擎（Swift）同仓**。

## 仓库结构

```
根目录（插件，dsh.bundle）
├── client/lib/client.js   # 客户端：🔊 按钮、三态（播放/暂停/继续）、状态轮询
├── host/lib/index.js      # 极简 Node 入口（空占位）
├── cordis.patch.yml       # 挂 host 入口
├── package.json           # dsh.bundle.patch + dsh.client.platform: web
├── docs/API.md            # 本地协议（唯一事实源）
└── docs/DESIGN.md | DECISIONS.md | MEMORY.md | HANDOFF.md

engine/                    # 本地引擎（macOS App，Swift）
├── Sources/               # ReadAloudService（App 壳）+ ReadAloudConfig（引擎内核）
├── Resources/             # 图标（OmiDSH.icns / Omi_logo.svg）+ Info.plist
├── build/build-service.sh # 构建脚本（swiftc 全量编译 + codesign）
└── VERSION                # 引擎版本（须与插件 package.json 一致，当前 0.1.2）
```

## 关键约定

1. **协议单一事实源**：任何端点/字段改动，先改 `docs/API.md`，再同步引擎（`engine/Sources/ReadAloudService/LocalTTSService.swift`）与插件（`client/lib/client.js`）。
2. **引擎构建**：`engine/build/build-service.sh`，产物 `build/ReadAloudService.app`，安装到 `~/Applications/Omi DSH.app`（`ditto` + 重新 `codesign`）。
3. **版本一致**：插件 `package.json` 的 `version` 与引擎 `engine/VERSION` 必须同步（当前 `0.1.2`）。
4. **只点读、无自动朗读**：产品决策（v0.1.1 起），不要重新引入自动朗读。
5. **Key 不出本机**：豆包 Key 只存 Omi 引擎的 Keychain，插件侧零 Key；日志/响应永不携带 Key。

## 发布（重要）

- 本机 git push 到 GitHub 可能被网络限速/拦截；改用 **GitHub Contents API**（单文件）或 **git data API**（blobs/trees/commits 批量单次提交）上传，见 `docs/MEMORY.md`。
- 上传后把 tag 更新到最新 `main`（`PATCH /git/refs/tags/vX.Y.Z`，`force: true`）。

## 常见改动路径

- 改按钮行为/图标 → `client/lib/client.js`（改完 `node --check` 校验）
- 改引擎逻辑/端点 → `engine/Sources/...`，重跑 `build-service.sh` + 重装
- 改协议 → `docs/API.md` 优先

## 详见

- 架构/设计：`docs/DESIGN.md`
- 决策记录：`docs/DECISIONS.md`
- 长期知识库（坑/结论）：`docs/MEMORY.md`
- 交接/续作：`docs/HANDOFF.md`
