# dsh-omi-voice 本地协议 v1

> **单一事实源**：本文件同时被 `dsh-omi-voice`（插件）与 `omi-read-aloud`（引擎）遵守。
> 协议版本：`1`（路径前缀 `/v1`）
> 传输：HTTP/1.1 over **127.0.0.1 only**，默认端口 `8765`（引擎设置可改）
> 内容类型：`application/json; charset=utf-8`
> 认证：v1 无鉴权（仅本地回环；见 §安全）

---

## 1. 总览

插件是**遥控器**，引擎是**权威播放器**（D1 决策）。插件只负责：界面按钮、把文本发给引擎；播放、变速、暂停/继续、缓存、Key 全部在引擎侧。

```
GET  /v1/status           健康/状态检查（含是否已配 Key、播放状态、失败原因）
POST /v1/speak            朗读一段文本（打断当前播放）
POST /v1/pause            暂停当前朗读（保留位置）
POST /v1/resume           从暂停位置继续朗读
POST /v1/stop             停止当前朗读（幂等）
```

v1 不提供（预留 v1.1）：`GET /v1/voices` 音色列表、分段预取。

## 2. 端点定义

### 2.1 GET /v1/status

引擎健康检查 + 状态查询（合并了 /v1/state，保持端点最少）。

**200 OK**

```json
{
  "ok": true,
  "engine": "omi",
  "engineVersion": "0.1.2",
  "protocolVersion": 1,
  "keyConfigured": true,
  "voice": "zh_female_shuangkuaisisi_moon_bigtts",
  "state": "idle",
  "playing": false,
  "paused": false,
  "message": null,
  "currentTaskId": null
}
```

| 字段 | 说明 |
|---|---|
| `engine` | 固定 `"omi"` |
| `keyConfigured` | 引擎 Keychain 里是否有豆包 Key（插件据此决定提示文案） |
| `voice` | 当前音色 ID（v1.1 才开放切换） |
| `state` | `idle` / `preparing` / `playing` / `paused` / `failed` |
| `playing` | 是否正在播放（`state == "playing"`） |
| `paused` | 是否已暂停（`state == "paused"`） |
| `message` | `state == "failed"` 时的失败原因（面向用户的中文文案），否则 `null` |
| `currentTaskId` | 当前朗读任务 id（占位，v1 可忽略） |

**失败**：引擎未启动时 fetch 直接连接失败（插件侧处理，见 §4）。

### 2.2 POST /v1/speak

请求引擎朗读一段文本。**语义：打断**——若正在播放，先停止再朗读新文本（符合「点新回复马上听新的」的用户预期；队列留 v1.1）。

**请求体**

```json
{
  "text": "要朗读的文本（插件传入原始 Markdown，引擎负责清洗）",
  "rate": 1.2
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `text` | ✅ | 1–100,000 字符。引擎执行现有清洗（Markdown/HTML/表格过滤）→ 按 ≤900 UTF-8 字节自然分段 → 顺序播放 |
| `rate` | ❌ | `1.0–2.0` 浮点，缺省用引擎已保存的语速偏好；引擎负责 clamp |

**202 Accepted**

```json
{
  "ok": true,
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "segments": 3
}
```

**错误响应（统一错误结构，见 §3）**

| 状态码 | code | 场景 |
|---|---|---|
| 400 | `invalid_request` | 请求体不是合法 JSON 对象 |
| 400 | `invalid_text` | text 缺失 / 空 / 超长 / 清洗后无有效内容（纯表格、纯 Markdown 噪音） |
| 403 | `key_not_configured` | 引擎未配置豆包 Key |
| 429 | `rate_limited` | 豆包侧限流（透传，附 `retryAfterSec`） |
| 500 | `tts_failed` | 豆包请求失败（附引擎侧诊断信息，不含 Key） |

### 2.3 POST /v1/stop

停止当前朗读。**幂等**：未在播放时调用也返回成功。

**请求体**：`{}`（可空）

**200 OK**

```json
{ "ok": true }
```

### 2.4 POST /v1/pause

暂停当前朗读，**保留播放位置**（继续时从暂停处接着读）。未在播放时调用为幂等空操作。

**请求体**：`{}`（可空）

**200 OK**

```json
{ "ok": true }
```

### 2.5 POST /v1/resume

从暂停位置继续朗读。未在暂停态时调用为幂等空操作。

**请求体**：`{}`（可空）

**200 OK**

```json
{ "ok": true }
```

## 3. 统一错误结构

所有非 2xx 响应体：

```json
{
  "ok": false,
  "error": {
    "code": "key_not_configured",
    "message": "请先在 Omi 设置页配置豆包 API Key",
    "retryAfterSec": null
  }
}
```

`message` 面向最终用户（中文）；`code` 供插件做分支逻辑；`retryAfterSec` 仅 `rate_limited` 时非空。

插件对错误码的展示建议：
- `key_not_configured` → 提示「请先在 Omi 引擎设置页填写豆包 API Key」
- `invalid_text` → 提示「这条回复没有可朗读的内容」
- 其余 / 连接失败 → 提示「请确认 Omi 引擎已打开」

## 4. CORS 与浏览器同源策略

插件运行在 DSH Web（`http://127.0.0.1:3080`），fetch 引擎属于跨源请求，引擎必须：

1. 对 `OPTIONS` 预检返回 `204`，并带：
   - `Access-Control-Allow-Origin`（默认放行 `http://127.0.0.1:3080` 与 `http://localhost:3080`，可在引擎设置追加）
   - `Access-Control-Allow-Methods: GET, POST, OPTIONS`
   - `Access-Control-Allow-Headers: Content-Type`
2. 对真实请求返回同样的 `Access-Control-Allow-Origin`。

## 5. 安全

- 引擎**只监听 127.0.0.1**，不接受局域网/公网连接。
- **Key 永不离开本机**：任何请求/响应/日志都不携带豆包 Key；Key 只存在 macOS Keychain。
- v1 无鉴权 token。风险说明：本机任意进程可触发 TTS 朗读。影响面仅「本机扬声器出声」，无数据外泄面（Key 不透明、文本不回传），v1 可接受；若未来加入「读出任意本地文件」类能力，必须加 token。
- 引擎对 `text` 只做本地合成播放，**不落盘、不写历史、不回调任何远程端点**（沿用 Omi 隐私设计）。

## 6. 版本与兼容

- `protocolVersion` 字段常驻 `/v1/status`。协议破坏性变更时 bump 到 2，路径改为 `/v2`，引擎可同时提供 `/v1` 与 `/v2`。
- 插件与引擎各自独立发布；升级互不强制。
