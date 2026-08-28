[English](HANDOFF.en.md)

# dsh-omi-voice 交接文档（HANDOFF）

> 项目当前状态 + 如何续作（对应 Omi 的 `HANDOFF.md`）。接手前先读本文件与 `AGENTS.md`。

## 当前状态（2026-08-18，更新至 2026-08-27）

- **版本**：v0.1.3（插件 package.json 与引擎 engine/VERSION 已统一）。
- **已发布**：GitHub 公开仓库 `PolinniZhong/dsh-omi-voice`，含插件（根）+ 引擎（engine/）+ 文档 + 截图/GIF + Release。
- **功能已落地并验证**：点读/暂停/继续/停止、失败原因回传、只读最终回答、代码/表格/图形过滤、LRU 缓存、去重/节流、BYOK。
- **界面国际化（2026-08-27）**：引擎 UI 自动跟随系统语言（NSLocalizedString + `en.lproj`），英文系统→英文、中文系统→中文；文档双语（README/AGENTS/engine README + 切换链接）。**已同步 GitHub**（main.swift + en.lproj + build-service.sh）。
- **本机运行态**：引擎安装于 `~/Applications/Omi DSH.app`（8765 服务）；桌面端以 `link:` 装入插件。

## 待办（按优先级）

1. **PR 状态**：
   - ✅ **beancookie/awesome-dsh-plugin #75 已合并（2026-08-19）**——插件已进 DSH 插件主清单。
   - ✅ fendouai #20 已收录：PR 被关闭但内容已由维护者并入 main（commit `ada8503`，分类 `ui`），见 `data/plugins.json`。
   - ✅ **npm 已发布（2026-08-25）：`dsh-omi-voice@0.1.2`**，`repository` 已关联 GitHub；安装 `dsh plugin add dsh-omi-voice`。
   - ⏳ **awesome-dsh-plugin org 主清单 PR #3148**（CI 通过、无冲突，待维护者合并，category `voice`）。
   - ⏳ libukai #41 待维护者合并（等对方，无需操作）。
2. **官方帖子**：deepseek-ai/deepseek-harness discussions #3084 已发（含 GIF 演示 + "轻量·类原生"定位），可回复互动提升可见度。
3. **推广文章**：✅ **已发布（2026-08-25）**——小红书/公众号/知乎（用户自写，带来主要流量，仓库 2★ → 46★）。PR #3148 合并后可发一篇"入选官方清单"的更新文章做第二波。 
4. **可选增强（v1.1）**：语速 UI、跳过段落、端口配置 UI、鉴权 token、Windows 引擎。
5. **fork 清理**：✅ **已完成（2026-08-25，用户网页手动删）**——已删 `awesome-dsh-plugin`（beancookie）、`awesome-deepseek-harness-fendouai`（fendouai）、`awesome-deepseek-harness-dominic`（Dominic，注意真实 fork 名是 `-dominic` 而非 `-1`）；**保留** `awesome-deepseek-harness`（libukai #41 未合并）与 `awesome-dsh-plugin-org`（PR #3148 未合并）。

> 注：2026-08-25 工作区已重命名 `首次开箱` → `Omi-DSH 端到端`（桌面端 profile 的 link 指向与新符号链接已同步，重启桌面端后生效）；旧开发副本文件夹 `Omi-dsh 端到端版本` 已删除（v0.2.0 原版在别处、代码在 engine/，零损失）。

## 如何继续开发

1. 读 `AGENTS.md` → `docs/DESIGN.md`（架构）→ `docs/MEMORY.md`（坑）。
2. 改插件：`client/lib/client.js`（改完 `node --check`）；桌面端重启即生效（link 安装）。
3. 改引擎：`engine/Sources/...` → `engine/build/build-service.sh` → `ditto` 到 `~/Applications/Omi DSH.app` → 重启。
4. 改协议：先 `docs/API.md`，再同步引擎 + 插件。
5. 发布：见 `docs/MEMORY.md`（Contents/git data API + 更新 tag）。

## 关键文件索引

| 想找 | 去 |
|---|---|
| 架构/数据流 | `docs/DESIGN.md` |
| 为什么这么做 | `docs/DECISIONS.md` |
| 坑/发布方法 | `docs/MEMORY.md` |
| 本地协议 | `docs/API.md` |
| 引擎构建 | `engine/README.md`、`engine/build/build-service.sh` |
| 按钮/交互 | `client/lib/client.js` |
| 引擎 HTTP 服务 | `engine/Sources/ReadAloudService/LocalTTSService.swift` |
