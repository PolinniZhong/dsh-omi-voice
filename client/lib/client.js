window.__ModuleLoader__.load({
	id: "dsh-omi-voice",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
		let react = require("react");

		// ---- 样式 ----
		const css = [
			".ov-speak{width:26px;height:26px;border-radius:6px;border:none;cursor:pointer;font-size:12px;line-height:1;display:inline-flex;align-items:center;justify-content:center;background:rgba(127,127,127,.14);color:inherit;transition:background .15s}",
			".ov-speak:hover{background:rgba(127,127,127,.3)}",
			".ov-speak-active{background:rgba(76,175,80,.35)!important;color:#4caf50!important}",
			".ov-speak-disabled{opacity:.35;cursor:not-allowed}",
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
		function broadcastState() {
			window.dispatchEvent(new CustomEvent("dsh-omi-voice/state", { detail: { messageId: activeMessageId } }));
		}
		function setActiveMessage(id) { activeMessageId = id; broadcastState(); }

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
		function errorMessage(err) {
			if (!err || err.code === "unreachable") return "请先打开 Omi 引擎（本地朗读服务未启动）";
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
			var text = props.useSession ? props.useSession(function (s) { return findMessageText(s, props.messageId); }) : "";

			// 全局播放状态同步：别的按钮开始朗读时，本按钮同步高亮/复位
			react.useEffect(function () {
				var onState = function (ev) {
					var id = ev && ev.detail ? ev.detail.messageId : null;
					setSpeaking(id === props.messageId);
				};
				window.addEventListener("dsh-omi-voice/state", onState);
				return function () { window.removeEventListener("dsh-omi-voice/state", onState); };
			}, [props.messageId]);

			// 朗读完成自动复位；引擎断开时复位并提示一次
			react.useEffect(function () {
				if (!speaking[0]) return;
				var timer = setInterval(function () {
					engineStatus().then(function (st) {
						if (!st.playing && !st.preparing) {
							setSpeaking(false);
							setActiveMessage(null);
						}
					}).catch(function () {
						setSpeaking(false);
						setActiveMessage(null);
						toast("引擎已断开，请确认 Omi 引擎已打开");
					});
				}, 1000);
				return function () { clearInterval(timer); };
			}, [speaking[0]]);

			var onClick = function () {
				if (speaking[0]) {
					stopEngine();
					setActiveMessage(null);
					setSpeaking(false);
					return;
				}
				if (!text) { toast("这条回复没有可朗读的内容"); return; }
				speakText(text).then(function () {
					setActiveMessage(props.messageId);
				}).catch(function (err) {
					toast(errorMessage(err));
				});
			};

			return react.createElement("button", {
				className: "ov-speak" + (speaking[0] ? " ov-speak-active" : "") + (!text ? " ov-speak-disabled" : ""),
				title: !text ? "这条回复没有可朗读的内容" : (speaking[0] ? "停止朗读（豆包音色 · Omi 引擎）" : "朗读（豆包音色 · Omi 引擎）"),
				disabled: !text,
				onClick: onClick
			}, speaking[0] ? "⏹" : "🔊");
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
