# Changelog

## [0.1.0] - 2026-08-18

首个版本（MVP）：

- 对话内朗读：每条 assistant 回复旁 🔊 按钮（朗读/停止）
- 自动朗读：📢 开关，默认关闭，状态持久化（localStorage）
- 新回复按消息序号去重，历史消息与刷新不重读
- 引擎未启动 / 未配置 Key 的友好提示
- 对接 Omi 引擎本地服务 `localhost:8765`（协议 v1，见 docs/API.md）
- 豆包 Key 完全留在 Omi 引擎 Keychain（BYOK）
- 不含翻译与文本预览功能
