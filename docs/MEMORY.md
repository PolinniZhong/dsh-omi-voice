# dsh-omi-voice 长期知识库（MEMORY）

> 记录跨版本仍有效的坑与已验证结论（对应 Omi 的 `MEMORY.md`）。倒序追加。

## 发布与推广（2026-08-25）

- **npm 发布要点**：包名 `dsh-omi-voice`（未被占用）；`package.json` 必须带 `repository` 字段（关联 GitHub，npm 下载量才回显到仓库）；`files` 精简为 `["host","client","cordis.patch.yml","docs/API.md","README.md","LICENSE"]`（不要把 docs/assets 图片打进包）；发布前 `npm pack --dry-run` 验证；npm 登录用户 `polinni`。
- **org 主清单（awesome-dsh-plugin/awesome-dsh-plugin）提交方式**：data-driven——一个插件一个 YAML `data/plugins/<owner>__<repo>.yml`（category 用 `voice`，description.en 必填、含 `: ` 必须加引号、以句号结尾、无营销词）；改完后跑 `npm ci && node scripts/generate-readme.mjs` 重新生成 README 一起提交；可选在 `data/screenshots.json` 加 GitHub 托管截图 URL。提交过 PR #3148（CI 通过）。
- **⚠️ org 清单 PR 会反复冲突（重要）**：上游太活跃（12K★，别人 PR 不断被合并），生成的 README/数据文件每次都撞。**修复流程（每次 2 分钟）**：① 拉最新上游 tarball（`codeload.github.com/.../tar.gz/refs/heads/main`）② 重新写入 YAML + screenshots.json 条目 ③ `npm ci && node scripts/generate-readme.mjs` 重生成 README ④ git data API 以"最新上游 sha 为父提交 + 上游 tree 为 base"重建 fork 分支并 `force:true` 更新 → PR 变为"最新上游 + 我的改动"，天然无冲突。用户选定的方案：**每次报冲突就发我重跑**。
- **截图新规则（维护者 fkysly 2026-08-26 要求，重要）**：**不要改上游 `data/screenshots.json`**（所有人共用、108 个 PR 抢同一个文件必冲突）——改为在**插件仓库根目录放 `screenshots.json`**（相对路径指向仓库内图片，如 `docs/assets/reading.png`），下一次构建自动生效；换截图只推自己仓库即可。我们已照做：`dsh-omi-voice/screenshots.json`。PR #3148 最终只含 YAML + 两个生成的 README（已 CLEAN、CI 绿，等维护者合并）。
- 修复 PR 冲突时注意：python urllib 可能因 SSL 证书报错（framework Python 无 certifi），改用 **`gh api --input <json文件>`**（先 printf 出 tree/commit 的 JSON body）即可；`gh api -F` 传 JSON 数组不可靠。
- **本环境 npm 技巧**：沙箱挡 `~/.npm` 写入，用 `npm --cache /tmp/npm-cacheX <cmd>` 绕开。
- **沙箱网络限制**：`git push` 与 `github.com/login/oauth/access_token`（gh 令牌换新 scope）在本环境会超时——令牌扩容（如 `delete_repo`）必须让用户在**自己终端**跑 `gh auth refresh -h github.com -s <scope>`，本环境无法完成。
- **沙箱与工作区重命名**：工作区文件夹改名后，沙箱仍绑定旧路径，对新路径的写入会间歇报"Operation not permitted / sandbox-exec ENOENT"——用文件工具的完整权限重试即可，或改用绝对路径 + 显式 workdir。


- **dsh.so 插件市场已收录（2026-08-27）**：https://www.dsh.so/artifact/dsh-omi-voice —— 自动收录 + 静态安全扫描 clean（100/100）+ L4 沙盒安装实测通过（win32/x64, DSH 0.1.1-rc.2）；README 已嵌入其安全/安装徽章（机器人 ihuajiu 发 issue #1 通知，关闭 issue 可退订通知）。

## 插件列表收录（awesome 生态）

- **fendouai/awesome-deepseek-harness 是 data-driven 列表**：README 与资源页由 `data/*.json` 自动生成，**更新条目走 `data/plugins.json` 提 PR，不手改 README**（维护者规则）。
- **已收录状态（2026-08-18）**：fendouai 列表 PR #20 被关闭但内容已由维护者手动并入 main（commit `ada8503`），条目在 `data/plugins.json`（分类 `ui`，能力 `ui`+`multimodal`，英文/中文描述均准确），并生成了专属资源页 `docs/en/resources/dsh-omi-voice.md`。
- **PR 关闭 ≠ 内容没收录**：data-driven 列表的维护者常"关闭 PR + 手动并入自己的批量提交"，看 commit 是否含条目，别只看 PR 状态。
- 同一维护者生态注意：**同名仓库 fork 会撞名**，用 `gh repo fork owner/repo --fork-name 自定义名`。

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

## 本地化（引擎 UI）

- **"中文串作 key"**：`NSLocalizedString("中文", comment: "")` + `en.lproj/Localizable.strings`（中文→英文）。中文系统自动回退（不命中的 key 返回 key 本身=中文），**只需 en.lproj、无需 zh-Hans.lproj**。
- **含插值字符串不能这样翻**：`"全局快捷键...（\(status)）"` 的 `\(...)` 会先求值再当 key → 查不到。这类保留原样或改用 `String(format:)`。用脚本包裹时正则跳过含 `\` 的字符串即可。
- **build-service.sh 必须复制 en.lproj**：`cp -R "$ROOT/Resources/en.lproj" "$APP/Contents/Resources/"`，否则 bundle 里没语言资源、回退中文。
- **验证**：`Bundle(path: "<.app 路径>")` + `UserDefaults.set(["en"], forKey: "AppleLanguages")` + `bundle.localizedString(forKey:value:table:)`（注意用 App 的 Bundle，不是 CLI 脚本的 `Bundle.main`）。
- 文档国际化：`README.en.md` / `AGENTS.en.md` / `engine/README.en.md`，中文原版顶部加 `中文 | [English](...)` 切换链接。
