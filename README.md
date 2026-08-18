# dsh-omi-voice

> **豆包音质 · 对话内点读**：DeepSeek Harness 桌面端里，点一下 🔊 就能听 AI 回复（只读最终回答，工具日志/代码/表格/图形自动过滤）。语音由本地 Omi 引擎合成（豆包 seed-tts），**豆包 API Key 只留在你自己的钥匙串里（BYOK）**。

[![Awesome DSH Plugin](https://awesome-dsh-plugin.com/badge.svg)](https://awesome-dsh-plugin.com)

## 它解决什么

- DSH 内置朗读（浏览器 `speechSynthesis` / Edge TTS）音色机械、像上个时代的播报腔。
- 通用剪贴板朗读工具（如 Omi 本身）需要先复制再触发，不够"豆包"。
- `dsh-omi-voice` = **豆包自然音色 + 对话内直接点读**：点 🔊 即读，不复制、不自动读。

## 架构

```
┌──────────────────────────────┐   localhost:8765    ┌──────────────────────┐
│ DeepSeek Harness 桌面端 (DSH) │ ──────────────────▶ │ Omi 引擎 (macOS App)  │
│  dsh-omi-voice 插件 (client) │  /v1/speak /stop    │ 豆包 TTS 合成 + 播放   │
│  🔊 点读（仅此，无自动朗读）    │ ◀────────────────── │ Key 只在 Keychain     │
└──────────────────────────────┘   状态 / 错误码      └──────────────────────┘
```

插件只是遥控器，播放、变速、缓存、文本清洗（表格/代码/图形过滤）全部在 Omi 引擎里完成；协议见 [docs/API.md](docs/API.md)。

## 前置条件

- macOS（Apple Silicon）+ 已安装 **Omi 引擎** v0.1.4+（含本地 TTS 服务）
- 已开通豆包「语音合成 1.0」并在 **Omi 设置页保存一次 API Key**（Key 存入 macOS Keychain，插件侧零 Key）
- DeepSeek Harness（`dsh web`，含桌面端）

## 安装

```bash
dsh plugin --profile web add "github:PolinniZhong/dsh-omi-voice#v0.1.1&path:/"
```

重启 DSH（或重启桌面端）。本地开发时可直接装目录：

```bash
dsh plugin --profile web add /path/to/dsh-omi-voice
```

> 使用 DeepSeek Harness Desktop 桌面端时，用桌面端内置的 `dsh` CLI 并设置 `DSH_HOME` 指向桌面端的数据目录。

## 使用

1. 打开 Omi 引擎（可在「设置 > 应用偏好 > 开机启动」里设为常驻）。
2. 在 DSH 对话里，点回复旁的 **🔊** 朗读/停止该条回复。
   - 只读 AI 的**最终回答**：工具执行日志、思考过程不会读。
   - 代码围栏、表格、纯图形（盒绘图/ASCII 图）朗读前自动过滤；回复若只有这些内容，按钮呈禁用态并提示"没有可朗读的内容"。
3. 未打开引擎或未配 Key 时，点击会给出明确提示。

## 成本透明

豆包 TTS（`seed-tts-1.0`）按**字符数**计费（火山引擎「语音合成 1.0」），由你自己在火山引擎账户承担费用。

- 只有你**手动点 🔊** 才会合成，不自动朗读；
- 引擎对相同文本 3 秒内去重，连点不会重复计费；
- 长回复按 900 字节分段朗读，请留意火山引擎用量。

## FAQ

| 问题 | 回答 |
|---|---|
| 点 🔊 提示"请先打开 Omi 引擎" | 本地服务未启动：确认 Omi（v0.1.4+）已打开（菜单栏有图标） |
| 提示"请先在 Omi 设置页配置豆包 API Key" | 打开 Omi 设置，填一次 Key 并保存 |
| 按钮是灰的 / 点它没反应 | 这条回复没有可朗读的内容（纯代码/表格/图形），已自动过滤 |
| 音色能换吗 | 换音色在 Omi 设置页「音色 ID」改（当前 v1 插件不提供音色 UI） |
| 支持 Windows 吗 | 暂不支持：Omi 引擎仅 macOS Apple Silicon |
| 和 dsh-voice-chat 的区别 | 它零 Key 零成本但用系统机械音色；本插件用豆包自然音色，代价是 BYOK 按字符计费 |

## 相关

- 引擎：[PolinniZhong/omi-read-aloud](https://github.com/PolinniZhong/omi-read-aloud)
- 生态：[awesome-dsh-plugin](https://github.com/beancookie/awesome-dsh-plugin)

## License

MIT
