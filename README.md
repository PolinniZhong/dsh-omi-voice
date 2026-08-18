# dsh-omi-voice

> **豆包音质 · 对话内朗读**：DeepSeek Harness 桌面端点一下就能听 AI 回复，或设置成自动朗读。语音由本地 Omi 引擎合成（豆包 seed-tts），**豆包 API Key 只留在你自己的钥匙串里（BYOK）**。

[![Awesome DSH Plugin](https://awesome-dsh-plugin.com/badge.svg)](https://awesome-dsh-plugin.com)

## 它解决什么

- DSH 内置朗读（浏览器 `speechSynthesis` / Edge TTS）音色机械、像上个时代的播报腔。
- 通用剪贴板朗读工具（如 Omi 本身）需要先复制再触发，不够"豆包"。
- `dsh-omi-voice` = **豆包自然音色 + 对话内直接点读/自动朗读**，两条短板的补法。

## 架构

```
┌──────────────────────────────┐   localhost:8765    ┌──────────────────────┐
│ DeepSeek Harness 桌面端 (DSH) │ ──────────────────▶ │ Omi 引擎 (macOS App)  │
│  dsh-omi-voice 插件 (client) │  /v1/speak /stop    │ 豆包 TTS 合成 + 播放   │
│  🔊 点读 / 📢 自动朗读开关     │ ◀────────────────── │ Key 只在 Keychain     │
└──────────────────────────────┘   状态 / 错误码      └──────────────────────┘
```

插件只是遥控器，播放、变速、缓存全部在 Omi 引擎里完成；协议见 [docs/API.md](docs/API.md)。

## 前置条件

- macOS（Apple Silicon）+ 已安装 **Omi 引擎**（[omi-read-aloud](https://github.com/PolinniZhong/omi-read-aloud) v0.1.4+，含本地 TTS 服务）
- 已开通豆包「语音合成 1.0」并在 **Omi 设置页保存一次 API Key**（Key 存入 macOS Keychain，插件侧零 Key）
- DeepSeek Harness（`dsh web`，含桌面端）

## 安装

```bash
dsh plugin --profile web add "github:PolinniZhong/dsh-omi-voice#v0.1.0&path:/"
```

重启 DSH（或重启桌面端）。本地开发时可直接装目录：

```bash
dsh plugin --profile web add /path/to/dsh-omi-voice
```

> 使用 DeepSeek Harness Desktop 桌面端时，用桌面端内置的 `dsh` CLI 并设置 `DSH_HOME` 指向桌面端的数据目录。

## 使用

1. 打开 Omi 引擎（可在「设置 > 应用偏好 > 开机启动」里设为常驻）。
2. 在 DSH 对话里：
   - **🔊**：朗读/停止当前这条回复
   - **📢**：自动朗读开关（**默认关闭**，状态持久化——关掉后下次进入仍是关）
3. 未打开引擎或未配 Key 时，点击会给出明确提示。

## 成本透明

豆包 TTS（`seed-tts-1.0`）按**字符数**计费（火山引擎「语音合成 1.0」），由你自己在火山引擎账户承担费用。因此：

- 自动朗读**默认关闭**，需要时手动开启；
- 长回复自动朗读会累积字符消耗，请留意火山引擎用量。

## FAQ

| 问题 | 回答 |
|---|---|
| 点 🔊 提示"请先打开 Omi 引擎" | 本地服务未启动：确认 Omi 已打开（菜单栏有图标） |
| 提示"请先在 Omi 设置页配置豆包 API Key" | 打开 Omi 设置，填一次 Key 并保存 |
| 音色能换吗 | 换音色在 Omi 设置页「音色 ID」改（当前 v1 插件不提供音色 UI） |
| 支持 Windows 吗 | 暂不支持：Omi 引擎仅 macOS Apple Silicon |
| 和 dsh-voice-chat 的区别 | 它零 Key 零成本但用系统机械音色；本插件用豆包自然音色，代价是 BYOK 按字符计费 |

## 相关

- 引擎：[PolinniZhong/omi-read-aloud](https://github.com/PolinniZhong/omi-read-aloud)
- 生态：[awesome-dsh-plugin](https://github.com/beancookie/awesome-dsh-plugin)

## License

MIT
