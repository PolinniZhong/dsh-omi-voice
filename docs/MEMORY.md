# dsh-omi-voice 长期知识库（MEMORY）

> 记录跨版本仍有效的坑与已验证结论（对应 Omi 的 `MEMORY.md`）。倒序追加。

## 发布与工具链

- **本机 git push 被限速/拦截**：git 上传到 GitHub 会超时（"Recv failure / too slow"），但 `gh api` / `curl` / Contents API 正常。发布统一走：
  - 单文件：`gh api --method PUT /repos/PolinniZhong/dsh-omi-voice/contents/<path>`（base64 content）
  - 批量：git data API（`POST /git/blobs` → `POST /git/trees` → `POST /git/commits` → `PATCH /git/refs/heads/main`）
- 上传后**更新 tag 指向最新 main**：`PATCH /git/refs/tags/vX.Y.Z`，`force:true`。
- 同名的 awesome 仓库（多个 `awesome-deepseek-harness`）fork 到同一账号会**撞名**：第二个 fork 自动改名成 `xxx-1`。用 `gh repo fork owner/repo --fork-name 自定义名`。

## 引擎（Swift）坑

- **Keychain v3 条目带 App ACL**（旧版 makeStableAccess），新版 dev 构建读不到 → 用户在新版设置里**重存一次 Key**（生成无 ACL 的 v4 条目）即可。
- **data protection keychain 在 ad-hoc 签名下必失败**（errSecMissingEntitlement -34018）：`usesDataProtectionKeychain` 必须保持 `false`。
- 构建脚本在 `engine/build/`，曾被误删；它在 git 里，`git checkout -- build/` 可恢复（但恢复的是原始版，需重打补丁：LocalTTSService.swift、`-framework Network`、OmiDSH.icns）。
- 引擎 App 是 `.accessory`（无 Dock 图标）；菜单栏图标用 `Omi_logo.svg`，App/Finder 图标用 `OmiDSH.icns`（CFBundleIconFile）。
- 引擎启动慢：`open` 后 8765 就绪可能要 5~7 秒，测试前多等或重试。

## 图标/视觉坑

- `omi_dsh_app_logo.svg` 里的 `<filter>`（两个 inner shadow）会在渲染时变成**鲸鱼周围一圈描边**；纯鲸鱼满幅需去掉底板 + 滤镜 + 收紧 viewBox。
- `fill="white"` 的鲸鱼在**浅色菜单栏不可见**；顶栏用白色版（深色菜单栏），App 图标用黑灰渐变版。
- GitHub README **不能渲染 SVG/视频**：logo 用 PNG（已转 `docs/assets/logo.png`），视频转 GIF（`ffmpeg` 双 pass 调色板）再嵌入。
- macOS 自带 curl 不支持 `--jq`，改用 `gh api ... --jq`。

## 插件（client.js）约定

- 客户端是 `window.__ModuleLoader__.load({id, factory})` 格式，`exports.apply` + `exports.inject = ["slots"]`。
- 回复文本提取：`props.useSession((s) => findMessageText(s, props.messageId))`，只取 `kind==='text'` 块；**不要提供 `node.text` 整段回退**（会把工具日志读出来）。
- 引擎是权威播放器：按钮状态靠轮询 `/v1/status` 同步，别只做乐观状态。

## 桌面端安装（开发态）

- 桌面端 profile 用 `dsh plugin --profile web add <本地绝对路径>` 会以 `link:` 方式装入 → 改 client.js 无需重装，重启桌面端即生效。
- 桌面端打包的 dsh CLI 入口是 `node_modules/@deepseek-ai/dsh/lib/bin.js`（不是 `.bin/dsh`，后者因目录结构报错）；pnpm 用桌面端自带的 `dependencies/pnpm/bin/pnpm.cjs`。
