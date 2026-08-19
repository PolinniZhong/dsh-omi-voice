# dsh-omi-voice 交接文档（HANDOFF）

> 项目当前状态 + 如何续作（对应 Omi 的 `HANDOFF.md`）。接手前先读本文件与 `AGENTS.md`。

## 当前状态（2026-08-18）

- **版本**：v0.1.2（插件 package.json 与引擎 engine/VERSION 已统一）。
- **已发布**：GitHub 公开仓库 `PolinniZhong/dsh-omi-voice`，含插件（根）+ 引擎（engine/）+ 文档 + 截图/GIF + Release。
- **功能已落地并验证**：点读/暂停/继续/停止、失败原因回传、只读最终回答、代码/表格/图形过滤、LRU 缓存、去重/节流、BYOK。
- **本机运行态**：引擎安装于 `~/Applications/Omi DSH.app`（8765 服务）；桌面端以 `link:` 装入插件。

## 待办（按优先级）

1. **等 PR 合并**：beancookie/awesome-dsh-plugin #75、libukai #41 待维护者合并。
   - ✅ fendouai #20 已收录：PR 被关闭但内容已由维护者并入 main（commit `ada8503`，分类 `ui`），见 `data/plugins.json`。
2. **官方帖子**：deepseek-ai/deepseek-harness discussions #3084 已发（含 GIF 演示 + "轻量·类原生"定位），可回复互动提升可见度。
3. **推广文章**：用户自写（公众号/V2EX/掘金），引用 README 截图/GIF + 官方帖子链接。
4. **可选增强（v1.1）**：语速 UI、跳过段落、端口配置 UI、鉴权 token、Windows 引擎。
5. **fork 清理**：PR 合并后删除账号下 `PolinniZhong/awesome-deepseek-harness*` 等临时 fork。

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
