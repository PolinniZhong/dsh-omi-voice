window.__ModuleLoader__.load({
	id: "dsh-omi-voice",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
		let react = require("react");

		// ---- 样式 ----
		const css = [
			".ov-speak{width:26px;height:26px;border-radius:50%;border:none;cursor:pointer;font-size:12px;line-height:1;display:inline-flex;align-items:center;justify-content:center;background:transparent;color:inherit;transition:background .15s}",
			".ov-speak:hover{background:rgba(127,127,127,.16)}",
			".ov-speak-active{background:transparent!important}",
			".ov-speak-disabled{opacity:.35;cursor:not-allowed}",
			"@keyframes ov-eq-bounce{0%,100%{transform:scaleY(.3)}50%{transform:scaleY(1)}}",
			".ov-eq-bar{transform-box:fill-box;transform-origin:center;animation:ov-eq-bounce .9s ease-in-out infinite}",
			".ov-eq-bar:nth-child(1){animation-delay:0s}",
			".ov-eq-bar:nth-child(2){animation-delay:-.25s}",
			".ov-eq-bar:nth-child(3){animation-delay:-.45s}",
			".ov-eq-bar:nth-child(4){animation-delay:-.15s}",
			".ov-eq-static .ov-eq-bar{animation:none!important}",
			"#dsh-omi-voice-toast{position:fixed;left:50%;bottom:64px;transform:translateX(-50%);z-index:999999;max-width:80vw;background:#1b1b2f;color:#f5f5f5;border:1px solid #555;border-radius:8px;padding:8px 14px;font-size:13px;box-shadow:0 6px 24px rgba(0,0,0,.5);display:none;text-align:center}"
		].join("");
		const tagId = "dsh-omi-voice/styles";
		if (typeof document !== "undefined" && document.querySelector("style[data-plugin-css=\"" + tagId + "\"]") === null) {
			const tag = document.createElement("style");
			tag.dataset.plugin = "dsh-omi-voice";
			tag.dataset.pluginCss = tagId;
			tag.textContent = css;
			document.head.appendChild(tag);
		}

		// ---- 按钮图标（未朗读=原版喇叭 #8A8C93；朗读中=4 竖条循环跳动）----
		const SPEAKER_SVG = '<svg width="18" height="18" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">' +
			'<path d="M15.9729 9.29019C18.1552 7.01263 22 8.55734 22 11.7117V32.2798C22 35.4353 18.1528 36.9794 15.9712 34.6995L10.3052 28.7781C10.1107 28.5749 9.8397 28.463 9.55854 28.4698L7.07232 28.5297C5.38764 28.5704 4 27.2158 4 25.5306V18.597C4 16.9683 5.29947 15.6372 6.92768 15.5979L9.58744 15.5338C9.85162 15.5274 10.1025 15.4167 10.2854 15.2259L15.9729 9.29019Z" stroke="#8A8C93" stroke-width="3" stroke-linejoin="round"/>' +
			'<path d="M28 18C28.6281 19.1196 29 20.5093 29 22.0146C29 23.5069 28.6345 24.8854 28.0163 26" stroke="#8A8C93" stroke-width="3" stroke-linejoin="round"/>' +
			'<path d="M31.9836 13C31.9836 13 34.9999 16.2977 35 21.7649C35.0001 27.232 31.9999 31 31.9999 31" stroke="#8A8C93" stroke-width="3" stroke-linejoin="round"/>' +
			'</svg>';
		const EQ_SVG = '<svg width="18" height="18" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">' +
			'<rect class="ov-eq-bar" x="21.5" y="8" width="3" height="24" rx="1.5" fill="#4176E6"/>' +
			'<rect class="ov-eq-bar" x="14.5" y="14" width="3" height="13" rx="1.5" fill="#4176E6"/>' +
			'<rect class="ov-eq-bar" x="7.5" y="16" width="3" height="9" rx="1.5" fill="#4176E6"/>' +
			'<rect class="ov-eq-bar" x="28.5" y="14" width="3" height="13" rx="1.5" fill="#4176E6"/>' +
			'</svg>';

		// ---- 清理旧版本残留（自动朗读时代：settings / autoSeq）----
		try {
			localStorage.removeItem("dsh-omi-voice/settings");
			var staleKeys = [];
			for (var i = 0; i < localStorage.length; i++) {
				var k = localStorage.key(i);
				if (k && k.indexOf("dsh-omi-voice/autoSeq/") === 0) staleKeys.push(k);
			}
			for (var j = 0; j < staleKeys.length; j++) localStorage.removeItem(staleKeys[j]);
		} catch (_) {}

		// ---- 引擎地址（可选覆盖，默认 127.0.0.1:8765）----
		const DEFAULT_ENGINE_BASE = "http://127.0.0.1:8765";
		function engineBase() {
			try {
				var v = localStorage.getItem("dsh-omi-voice/engineBase");
				if (v) return v;
			} catch (_) {}
			return DEFAULT_ENGINE_BASE;
		}

		// 播放状态全局同步（引擎是权威播放器；插件只做乐观状态）
		let activeMessageId = null;
		let activePaused = false;
		function broadcastState() {
			window.dispatchEvent(new CustomEvent("dsh-omi-voice/state", { detail: { messageId: activeMessageId, paused: activePaused } }));
		}
		function setActiveMessage(id) { activeMessageId = id; broadcastState(); }
		function setActivePaused(p) { activePaused = p; broadcastState(); }

		// ---- Omi 引擎 HTTP 客户端（协议见 docs/API.md v1）----
		async function engineStatus() {
			const res = await fetch(engineBase() + "/v1/status", { method: "GET" });
			if (!res.ok) throw { code: "unreachable" };
			return res.json();
		}
		async function speakText(text) {
			const res = await fetch(engineBase() + "/v1/speak", {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify({ text: text })
			});
			let body = {};
			try { body = await res.json(); } catch (_) {}
			if (!res.ok) throw (body && body.error) || { code: "unknown", message: "朗读失败" };
			return body;
		}
		async function stopEngine() {
			try { await fetch(engineBase() + "/v1/stop", { method: "POST" }); } catch (_) {}
		}
		async function pauseEngine() {
			try { await fetch(engineBase() + "/v1/pause", { method: "POST" }); } catch (_) {}
		}
		async function resumeEngine() {
			try { await fetch(engineBase() + "/v1/resume", { method: "POST" }); } catch (_) {}
		}
		function errorMessage(err) {
			if (!err || err.code === "unreachable") return "未检测到 Omi DSH 引擎：请打开应用「Omi DSH」（应用程序文件夹或 ⌘空格 搜索），并在其设置中开启开机启动";
			if (err.code === "key_not_configured") return "请先在 Omi 设置页配置豆包 API Key";
			if (err.code === "invalid_text") return "这条回复没有可朗读的内容";
			return (err && err.message) || "朗读失败，请查看 Omi 面板状态";
		}
		function toast(msg) {
			let el = document.getElementById("dsh-omi-voice-toast");
			if (!el) {
				el = document.createElement("div");
				el.id = "dsh-omi-voice-toast";
				document.body.appendChild(el);
			}
			el.textContent = msg;
			el.style.display = "block";
			clearTimeout(el._t);
			el._t = setTimeout(function () { el.style.display = "none"; }, 3500);
		}

		// ---- 从会话快照提取 assistant 消息的"最终回答"文本 ----
		// 只保留 kind === 'text' 的块；工具调用/工具结果/命令/思考/图片/文件块一律不读。
		// 注意：不提供 node.text 整段回退——那会把工具日志一起读出来。
		function findAssistantNode(session, messageId) {
			if (!session || !messageId) return null;
			var nodes = session.nodes || [];
			for (var i = 0; i < nodes.length; i++) {
				var n = nodes[i];
				if (n && n.kind === "assistant" && n.messageId === messageId) return n;
			}
			if (session.chat && session.chat.nodes) {
				try {
					var store = session.chat.nodes;
					var all = (typeof store.values === "function") ? store.values() : [];
					for (var j = 0; j < all.length; j++) {
						var inner = (all[j] && all[j].node) || all[j];
						if (inner && inner.kind === "assistant" && inner.messageId === messageId) return inner;
					}
				} catch (_) {}
			}
			return null;
		}
		function findMessageText(session, messageId) {
			var node = findAssistantNode(session, messageId);
			if (!node) return "";
			var blocks = node.blocks || node.content || [];
			var out = "";
			for (var i = 0; i < blocks.length; i++) {
				var b = blocks[i];
				if (!b) continue;
				if (typeof b === "string") { out += b; continue; }
				if (b.kind === "text" && typeof b.text === "string") out += b.text;
			}
			return out.trim();
		}

		// ---- 每条 assistant 回复旁的朗读按钮 ----
		function SpeakButton(props) {
			var speaking = react.useState(false);
			var setSpeaking = speaking[1];
			var paused = react.useState(false);
			var setPaused = paused[1];
			var text = props.useSession ? props.useSession(function (s) { return findMessageText(s, props.messageId); }) : "";

			// 全局播放状态同步：别的按钮开始/暂停朗读时，本按钮同步
			react.useEffect(function () {
				var onState = function (ev) {
					var id = ev && ev.detail ? ev.detail.messageId : null;
					var isPaused = ev && ev.detail ? ev.detail.paused : false;
					setSpeaking(id === props.messageId);
					setPaused(isPaused);
				};
				window.addEventListener("dsh-omi-voice/state", onState);
				return function () { window.removeEventListener("dsh-omi-voice/state", onState); };
			}, [props.messageId]);

			// 轮询引擎状态：同步播放/暂停/失败，读完或失败自动复位
			react.useEffect(function () {
				if (!speaking[0]) return;
				var timer = setInterval(function () {
					engineStatus().then(function (st) {
						if (st.state === "playing") {
							setPaused(false);
						} else if (st.state === "paused") {
							setPaused(true);
						} else if (st.state === "failed") {
							setSpeaking(false);
							setPaused(false);
							setActiveMessage(null);
							toast(st.message || "朗读失败");
						} else if (st.state === "idle") {
							setSpeaking(false);
							setPaused(false);
							setActiveMessage(null);
						}
					}).catch(function () {
						setSpeaking(false);
						setPaused(false);
						setActiveMessage(null);
						toast("引擎已断开：请重新打开应用「Omi DSH」");
					});
				}, 1000);
				return function () { clearInterval(timer); };
			}, [speaking[0]]);

			var onClick = function () {
				if (speaking[0] && !paused[0]) {
					pauseEngine();
					setPaused(true);
					setActivePaused(true);
					return;
				}
				if (speaking[0] && paused[0]) {
					resumeEngine();
					setPaused(false);
					setActivePaused(false);
					return;
				}
				if (!text) { toast("这条回复没有可朗读的内容"); return; }
				speakText(text).then(function () {
					setActiveMessage(props.messageId);
					setActivePaused(false);
					setPaused(false);
				}).catch(function (err) {
					toast(errorMessage(err));
				});
			};

			var icon = SPEAKER_SVG;
			var title = "朗读（豆包音色 · Omi 引擎）";
			if (speaking[0]) {
				icon = EQ_SVG;
				title = paused[0] ? "继续朗读" : "暂停朗读";
			}

			return react.createElement("button", {
				className: "ov-speak" + (speaking[0] ? " ov-speak-active" : "") + (!text ? " ov-speak-disabled" : ""),
				title: !text ? "这条回复没有可朗读的内容" : title,
				disabled: !text,
				onClick: onClick
			}, react.createElement("span", {
				className: (speaking[0] && paused[0]) ? "ov-eq-static" : "",
				dangerouslySetInnerHTML: { __html: icon }
			}));
		}

		// ---- cordis client plugin ----
		var inject = ["slots"];

		function apply(ctx) {
			// 每条 assistant 回复旁的朗读按钮（仅点读，无自动朗读）
			ctx.slots.inject("conversation.chat.assistant-actions", function () {
				return ctx.slots.register(
					{ name: "conversation.chat.assistant-actions", id: "omi-voice-speak", order: 5, label: "朗读" },
					function (props) { return react.createElement(SpeakButton, props); }
				);
			});
		}

		exports.apply = apply;
		exports.inject = inject;
		return module.exports;
	}
});
