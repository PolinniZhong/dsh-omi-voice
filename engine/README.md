# Omi DSH 引擎（engine）

dsh-omi-voice 的**本地朗读引擎**：一个 macOS 菜单栏应用，内置豆包 TTS 合成与本地 HTTP 服务（`127.0.0.1:8765`），供 dsh-omi-voice 插件在 DeepSeek Harness 对话内朗读。

## 功能

- 对话内点读 / 暂停 / 继续（从暂停位置续播）/ 停止
- 只朗读最终回答：工具日志、代码围栏、表格、盒绘/ASCII 图形在请求前本地过滤
- 豆包 TTS 1.0（`seed-tts-1.0`）流式合成 + 本地播放（AVAudioEngine，可变速）
- 内存 LRU 缓存（3 条 / 5MB，退出即清）+ 同文本去重，避免重复计费
- BYOK：豆包 API Key 只存 macOS Keychain，不出本机

## 构建与安装

前置：Apple Silicon Mac、macOS 13+、Xcode（或 Command Line Tools）、已开通豆包「语音合成 1.0」。

```bash
./build/build-service.sh
mkdir -p "$HOME/Applications"
ditto build/ReadAloudService.app "$HOME/Applications/Omi DSH.app"
open "$HOME/Applications/Omi DSH.app"
```

首次使用在「设置 > API Key」保存一次豆包 Key；建议开启「设置 > 应用偏好 > 开机启动」。

## 本地服务协议

见仓库根目录的 [docs/API.md](../docs/API.md)（`/v1/status`、`/v1/speak`、`/v1/pause`、`/v1/resume`、`/v1/stop`）。协议是插件与引擎之间的唯一契约。

## 目录

- `Sources/` — Swift 源码（`ReadAloudService` App 壳 + `ReadAloudConfig` 引擎内核）
- `Resources/` — 图标（`OmiDSH.icns`、`Omi_logo.svg`）与 `Info.plist`
- `build/` — 构建脚本（`build-service.sh` / `build-launcher.sh`）
