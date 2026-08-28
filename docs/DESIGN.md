# dsh-omi-voice 架构设计（DESIGN）

> 本文件是架构与设计的唯一权威来源（对应 Omi 的 `DESIGN.md`）。改动架构前先改这里。

## 1. 总架构

```
┌──────────────────────────────┐   localhost:8765   ┌──────────────────────────────┐
│ DeepSeek Harness 桌面端        │ ─────────────────▶ │ Omi DSH 引擎（macOS App）      │
│  dsh-omi-voice 插件 (client.js)│  /v1/speak/pause/  │  LocalTTSService（新增）        │
│  🔊 按钮（播放/暂停/继续）       │    resume/stop/status│  ├─ ReadAloudTextPreparation   │
│  状态轮询 / 失败 toast         │ ◀───────────────── │  ├─ DoubaoHTTPStreamingClient │
└──────────────────────────────┘   状态/错误 JSON      │  ├─ PCMStreamPlayer → 扬声器   │
                                                      │  └─ KeychainStore（Key，不出机）│
                                                      └──────────────┬───────────────┘
                                                                     ▼ 豆包 TTS 云
                                                        openspeech.bytedance.com（WSS/HTTPS）
```

## 2. 组件职责

| 组件 | 文件 | 职责 |
|---|---|---|
| 插件（客户端） | `client/lib/client.js` | 提取回复最终回答文本、三态按钮、轮询引擎状态、失败 toast；零 Key |
| 插件（Node 占位） | `host/lib/index.js` | 空占位，让 bundle 干净挂载 |
| 引擎 HTTP 服务 | `engine/Sources/ReadAloudService/LocalTTSService.swift` | NWListener 手写最小 HTTP/1.1，路由 `/v1/*`，CORS loopback，去重/节流 |
| 引擎朗读管线 | `engine/Sources/ReadAloudConfig/*` | 清洗→分段→豆包流式合成→本地播放（AVAudioEngine）；缓存/变速/暂停 |
| App 壳 | `engine/Sources/ReadAloudService/main.swift` | 菜单栏、设置页、Keychain、把 LocalTTSService 接到现有管线 |

## 3. 数据流（一次点读）

1. 插件 `findMessageText` 从会话快照提取 assistant 节点中 `kind === 'text'` 的块（排除 tool-call/tool-result/think 等）。
2. `POST /v1/speak {text}` → 引擎校验（内容→Key）→ `ReadAloudTextPreparation` 清洗（表格/代码围栏/图形）→ 按 ≤900 字节分段。
3. 取 Keychain 的豆包 Key → 组豆包请求 → WSS 流式回传 PCM → `PCMStreamPlayer` 边收边播。
4. 插件每秒轮询 `/v1/status`，同步 playing/paused/idle/failed 状态；读完自动复位，失败 toast `message`。

## 4. 协议 v1（唯一事实源：docs/API.md）

- `GET /v1/status`：健康 + `state`（idle/preparing/playing/paused/failed）+ `message` + `keyConfigured`
- `POST /v1/speak`：朗读（打断语义），返回 `segments`
- `POST /v1/pause` / `/v1/resume`：暂停/继续（保留播放位置）
- `POST /v1/stop`：停止（幂等）
- 仅监听 127.0.0.1；CORS 放行任意 loopback origin

## 5. 安全与隐私边界

- 豆包 Key 只存 macOS Keychain，永不进日志/响应/插件。
- 无鉴权 token（v1）：本机任意进程可触发 TTS。影响面仅"本机扬声器出声"，无数据外泄；若未来加"读本地文件"类能力必须加 token。
- 文本只在内存流转，不落盘、不写历史。

## 6. 成本控制设计

- 仅手动点读，无自动朗读。
- 引擎内存 LRU 缓存：3 条 / ≤5MB，LRU 淘汰，退出即清。
- 同文本 3 秒去重 + 任意朗读 300ms 节流。
- 无有效内容（纯表格/代码/图形）在请求前返回 `invalid_text`，不发豆包请求。

## 7. 关键约束

- 引擎仅 macOS（Apple Silicon）。插件跨任何 `dsh web`。
- 版本：插件 `package.json` 与引擎 `engine/VERSION` 必须一致。
- 协议改动三处同步：API.md → LocalTTSService → client.js。

## 8. 本地化 / 国际化

- 引擎 UI **自动跟随系统语言**：`main.swift` 用 `NSLocalizedString("中文串", comment: "")`（中文串即 key），配套 `Resources/en.lproj/Localizable.strings`（中文→英文）+ **`zh-Hans.lproj/Localizable.strings`（key=中文值）**。
- ⚠️ **必须同时提供 en + zh-Hans 两个 .lproj**：macOS 的 Bundle 按 `.lproj` 判定"App 可用语言"，**只有 en.lproj 会被判定为"只会英文"，无论系统语言是中文还是英文都恒解析英文（真实 Bug 教训）**；两个都有才会正确按系统语言切换（中文系统→zh-Hans，英文系统→en）。
- 构建：`engine/build/build-service.sh` 复制 `en.lproj` 与 `zh-Hans.lproj` 进 App 包 `Contents/Resources`。
- 范围：用户可见 UI（设置面板/状态/菜单/按钮/错误提示/无障碍标签）；日志（`serviceLog`）、开发诊断保持中文。
- **坑**：含插值（`\(...)`）的字符串不能用"字面量作 key"（会把展开后的值当 key，查不到），保留原样或改用 `String(format:)`。
