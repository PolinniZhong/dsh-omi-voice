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
			".ov-toggle{width:26px;height:26px;border-radius:6px;border:none;cursor:pointer;font-size:12px;line-height:1;display:inline-flex;align-items:center;justify-content:center;background:rgba(127,127,127,.14);color:inherit;transition:background .15s}",
			".ov-toggle:hover{background:rgba(127,127,127,.3)}",
			".ov-toggle-active{background:rgba(79,195,247,.3)!important;color:#4fc3f7!important}",
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

		// ---- 设置（localStorage 持久化 + 事件广播）----
		const SETTINGS_KEY = "dsh-omi-voice/settings";
		const SETTINGS_EVENT = "dsh-omi-voice/settings-changed";
		const STATE_EVENT = "dsh-omi-voice/state";
		const DEFAULT_ENGINE_BASE = "http://127.0.0.1:8765";

		function loadSettings() {
			try {
				const raw = JSON.parse(localStorage.getItem(SETTINGS_KEY) || "{}");
				return {
					autoSpeak: raw.autoSpeak === true, // D2: 默认关闭
					engineBase: typeof raw.engineBase === "string" && raw.engineBase ? raw.engineBase : DEFAULT_ENGINE_BASE
				};
			} catch (_) {
				return { autoSpeak: false, engineBase: DEFAULT_ENGINE_BASE };
			}
		}
		function saveSettings(s) {
			try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(s)); } catch (_) {}
			window.dispatchEvent(new CustomEvent(SETTINGS_EVENT));
		}
		function engineBase() { return loadSettings().engineBase; }

		// 播放状态全局同步（引擎是权威播放器；插件只做乐观状态）
		let activeMessageId = null;
		function broadcastState() {
			window.dispatchEvent(new CustomEvent(STATE_EVENT, { detail: { messageId: activeMessageId } }));
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

		// ---- 从会话快照提取 assistant 消息文本 / 序号 ----
		function blocksToText(blocks) {
			if (!Array.isArray(blocks)) return "";
			var out = "";
			for (var i = 0; i < blocks.length; i++) {
				var b = blocks[i];
				if (!b) continue;
				if (typeof b === "string") { out += b; continue; }
				if (b.kind === "text" && typeof b.text === "string") { out += b.text; continue; }
				if (typeof b.text === "string") { out += b.text; continue; }
			}
			return out;
		}
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
			var t = blocksToText(blocks).trim();
			if (t) return t;
			if (typeof node.text === "string") return node.text;
			return "";
		}
		function findMessageSeq(session, messageId) {
			var node = findAssistantNode(session, messageId);
			if (node && typeof node.seq === "number") return node.seq;
			return 0;
		}

		// ---- 自动朗读去重：只读比本会话已读到更新 seq 的回复 ----
		function lastAutoSeq(sessionId) {
			if (!sessionId) return 0;
			try { return Number(localStorage.getItem("dsh-omi-voice/autoSeq/" + sessionId) || 0); } catch (_) { return 0; }
		}
		function markAutoSeq(sessionId, seq) {
			if (!sessionId) return;
			try { localStorage.setItem("dsh-omi-voice/autoSeq/" + sessionId, String(seq)); } catch (_) {}
		}

		// ---- 每条 assistant 回复旁的朗读按钮 ----
		function SpeakButton(props) {
			var speaking = react.useState(false);
			var setSpeaking = speaking[1];
			var text = props.useSession ? props.useSession(function (s) { return findMessageText(s, props.messageId); }) : "";
			var seq = props.useSession ? props.useSession(function (s) { return findMessageSeq(s, props.messageId); }) : 0;

			// 全局播放状态同步：别的按钮开始朗读时，本按钮同步高亮/复位
			react.useEffect(function () {
				var onState = function (ev) {
					var id = ev && ev.detail ? ev.detail.messageId : null;
					setSpeaking(id === props.messageId);
				};
				window.addEventListener(STATE_EVENT, onState);
				return function () { window.removeEventListener(STATE_EVENT, onState); };
			}, [props.messageId]);

			// 自动朗读（默认关；开关状态持久化）
			var autoFired = react.useRef(false);
			react.useEffect(function () {
				if (autoFired.current) return;
				if (!loadSettings().autoSpeak || !text) return;
				if (!seq || seq <= lastAutoSeq(props.sessionId)) return;
				autoFired.current = true;
				markAutoSeq(props.sessionId, seq);
				var t = setTimeout(function () {
					speakText(text).then(function () {
						setActiveMessage(props.messageId);
					}).catch(function (err) {
						toast(errorMessage(err));
					});
				}, 500);
				return function () { clearTimeout(t); };
			}, [text, seq, props.sessionId]);

			var onClick = function () {
				if (speaking[0]) {
					stopEngine();
					setActiveMessage(null);
					setSpeaking(false);
					return;
				}
				if (!text) { toast("这条回复没有可朗读的文字"); return; }
				speakText(text).then(function () {
					setActiveMessage(props.messageId);
				}).catch(function (err) {
					toast(errorMessage(err));
				});
			};

			// 朗读完成自动复位：引擎是权威播放器，轮询 /v1/status 直到播放结束
			react.useEffect(function () {
				if (!speaking[0]) return;
				var timer = setInterval(function () {
					engineStatus().then(function (st) {
						if (!st.playing && !st.preparing) {
							setSpeaking(false);
							setActiveMessage(null);
						}
					}).catch(function () {});
				}, 1000);
				return function () { clearInterval(timer); };
			}, [speaking[0]]);

			return react.createElement("button", {
				className: "ov-speak" + (speaking[0] ? " ov-speak-active" : ""),
				title: speaking[0] ? "停止朗读（豆包音色 · Omi 引擎）" : "朗读（豆包音色 · Omi 引擎）",
				onClick: onClick
			}, speaking[0] ? "⏹" : "🔊");
		}

		// ---- 输入框旁的自动朗读开关（持久化，默认关闭）----
		function AutoSpeakToggle() {
			var s = loadSettings();
			var state = react.useState(s.autoSpeak);
			var auto = state[0];
			var setAuto = state[1];

			react.useEffect(function () {
				var onChg = function () { setAuto(loadSettings().autoSpeak); };
				window.addEventListener(SETTINGS_EVENT, onChg);
				return function () { window.removeEventListener(SETTINGS_EVENT, onChg); };
			}, []);

			var onClick = function () {
				var next = loadSettings();
				next.autoSpeak = !next.autoSpeak;
				saveSettings(next);
				setAuto(next.autoSpeak);
				if (next.autoSpeak) {
					engineStatus().then(function (st) {
						if (!st.keyConfigured) toast("自动朗读已开启；请先在 Omi 设置页配置豆包 API Key");
					}).catch(function () {
						toast("自动朗读已开启；但未检测到 Omi 引擎（请先打开 Omi）");
					});
				}
			};

			return react.createElement("button", {
				className: "ov-toggle" + (auto ? " ov-toggle-active" : ""),
				title: auto ? "自动朗读：开（新回复自动朗读，点击关闭）" : "自动朗读：关（点击开启）",
				onClick: onClick
			}, "📢");
		}

		// ---- cordis client plugin ----
		var inject = ["slots"];

		function apply(ctx) {
			// 每条 assistant 回复旁的朗读按钮
			ctx.slots.inject("conversation.chat.assistant-actions", function () {
				return ctx.slots.register(
					{ name: "conversation.chat.assistant-actions", id: "omi-voice-speak", order: 5, label: "朗读" },
					function (props) { return react.createElement(SpeakButton, props); }
				);
			});
			// 输入框旁的自动朗读开关
			ctx.slots.inject("conversation.input.left", function () {
				return ctx.slots.register(
					{ name: "conversation.input.left", id: "omi-voice-toggle", order: 9, label: "自动朗读开关" },
					function (props) { return react.createElement(AutoSpeakToggle, props); }
				);
			});
		}

		exports.apply = apply;
		exports.inject = inject;
		return module.exports;
	}
});
