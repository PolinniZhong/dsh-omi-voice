import AppKit
import Carbon
import Foundation
import ServiceManagement

private let readAloudHotKeySignature: OSType = 0x52444C44 // "RDLD"
private let readAloudHotKeyIdentifier: UInt32 = 1
private func serviceLog(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(ReadAloudDiagnostics.redact(message))\n"
    let url = URL(fileURLWithPath: "/tmp/readaloud-service.log")
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private enum GlobalHotKeyError: LocalizedError {
    case installHandler(OSStatus)
    case register(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandler(let status):
            return "全局快捷键事件处理器注册失败（\(status)）"
        case .register(let status):
            return "全局快捷键 ⌥⇧Q 注册失败（\(status)）"
        }
    }
}

@MainActor
private final class GlobalHotKeyBridge {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func start() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard parameterStatus == noErr,
                      identifier.signature == readAloudHotKeySignature,
                      identifier.id == readAloudHotKeyIdentifier else {
                    return OSStatus(eventNotHandledErr)
                }
                let bridge = Unmanaged<GlobalHotKeyBridge>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in bridge.fire() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw GlobalHotKeyError.installHandler(handlerStatus)
        }

        let identifier = EventHotKeyID(
            signature: readAloudHotKeySignature,
            id: readAloudHotKeyIdentifier
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Q),
            UInt32(optionKey | shiftKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr else {
            stop()
            throw GlobalHotKeyError.register(registerStatus)
        }
    }

    func stop() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func fire() {
        serviceLog("global-hotkey pressed")
        action()
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

@MainActor
private final class DiscreteRateSlider: NSControl {
    private let minimumStep = 10
    private let maximumStep = 20
    private let trackHeight: CGFloat = 24
    private let thumbDiameter: CGFloat = 26
    private(set) var step: Int

    var rate: Float {
        Float(step) / 10
    }

    init(rate: Float, target: AnyObject?, action: Selector?) {
        step = Int((rate * 10).rounded())
        super.init(frame: .zero)
        self.target = target
        self.action = action
        focusRingType = .exterior
        toolTip = "1.0× 到 2.0×，每次调整 0.1×"
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("朗读语速")
        updateAccessibility()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        isEnabled
    }

    override var isEnabled: Bool {
        didSet {
            needsDisplay = true
            setAccessibilityEnabled(isEnabled)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(trackHeight, thumbDiameter))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds.insetBy(
            dx: thumbDiameter / 2,
            dy: max(0, (bounds.height - trackHeight) / 2)
        )
        guard trackRect.width > 0 else { return }

        let fraction = CGFloat(step - minimumStep) / CGFloat(maximumStep - minimumStep)
        let thumbX = trackRect.minX + trackRect.width * fraction
        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackHeight / 2,
            yRadius: trackHeight / 2
        )
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.12 : 0.07).setFill()
        trackPath.fill()

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(0, thumbX - trackRect.minX),
            height: trackRect.height
        )
        NSColor.controlAccentColor.withAlphaComponent(isEnabled ? 1.0 : 0.28).setFill()
        fillRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        for tick in minimumStep...maximumStep {
            let tickFraction = CGFloat(tick - minimumStep) / CGFloat(maximumStep - minimumStep)
            let x = trackRect.minX + trackRect.width * tickFraction
            let dotRect = NSRect(x: x - 1.5, y: trackRect.midY - 1.5, width: 3, height: 3)
            let dot = NSBezierPath(ovalIn: dotRect)
            if tick <= step {
                NSColor.white.withAlphaComponent(isEnabled ? 0.72 : 0.42).setFill()
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(isEnabled ? 0.36 : 0.18).setFill()
            }
            dot.fill()
        }

        let thumbRect = NSRect(
            x: thumbX - thumbDiameter / 2,
            y: bounds.midY - thumbDiameter / 2,
            width: thumbDiameter,
            height: thumbDiameter
        )
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.windowBackgroundColor.withAlphaComponent(isEnabled ? 1.0 : 0.72).setFill()
        NSBezierPath(ovalIn: thumbRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.setStroke()
        let thumbBorder = NSBezierPath(ovalIn: thumbRect.insetBy(dx: 0.5, dy: 0.5))
        thumbBorder.lineWidth = 1
        thumbBorder.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        updateStep(from: event)
        while true {
            guard let nextEvent = window?.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else { break }
            updateStep(from: nextEvent)
            if nextEvent.type == .leftMouseUp { break }
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        switch event.keyCode {
        case 123, 125:
            setStep(step - 1)
        case 124, 126:
            setStep(step + 1)
        default:
            super.keyDown(with: event)
        }
    }

    private func updateStep(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let trackRect = bounds.insetBy(
            dx: thumbDiameter / 2,
            dy: max(0, (bounds.height - trackHeight) / 2)
        )
        guard trackRect.width > 0 else { return }
        let fraction = min(max((point.x - trackRect.minX) / trackRect.width, 0), 1)
        let rawStep = CGFloat(minimumStep) + fraction * CGFloat(maximumStep - minimumStep)
        setStep(Int(rawStep.rounded()))
    }

    private func setStep(_ newStep: Int) {
        let clampedStep = min(max(newStep, minimumStep), maximumStep)
        guard clampedStep != step else { return }
        step = clampedStep
        needsDisplay = true
        updateAccessibility()
        sendAction(action, to: target)
    }

    private func updateAccessibility() {
        setAccessibilityMinValue(NSNumber(value: minimumStep))
        setAccessibilityMaxValue(NSNumber(value: maximumStep))
        setAccessibilityValue(NSNumber(value: step))
        setAccessibilityValueDescription(String(format: "%.1f×", rate))
    }
}

@MainActor
private final class CopyableStatusTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            copyFullText()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(
            title: "复制完整信息",
            action: #selector(copyFullTextFromMenu),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)
        return menu
    }

    @objc private func copyFullTextFromMenu() {
        copyFullText()
    }

    private func copyFullText() {
        guard !string.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

@MainActor
private final class PlaybackButton: NSButton {
    private let waveformLayer = CALayer()
    private let waveformBars = (0..<4).map { _ in CALayer() }
    private var isShowingWaveform = false

    init(image: NSImage, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.image = image
        self.target = target
        self.action = action
        wantsLayer = true
        waveformLayer.isHidden = true
        waveformBars.forEach { bar in
            bar.backgroundColor = NSColor.systemBlue.cgColor
            waveformLayer.addSublayer(bar)
        }
        layer?.addSublayer(waveformLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var firstBaselineOffsetFromTop: CGFloat {
        // The waveform has no text baseline. Treat its visual centre as the
        // baseline so the icon aligns with the status copy rather than the
        // taller status text view.
        bounds.height > 0 ? bounds.midY : 15
    }

    override func layout() {
        super.layout()
        waveformLayer.frame = bounds
        waveformLayer.contentsScale = window?.backingScaleFactor ?? 2

        let scale = max(waveformLayer.contentsScale, 1)
        let barWidth = 2 / scale
        let barGap = 3 / scale
        let barHeights: [CGFloat] = [8, 16 - (4 / scale), 11, 14]
        let totalWidth = (barWidth * 4) + (barGap * 3)
        let leadingX = round((bounds.midX - (totalWidth / 2)) * scale) / scale

        for (index, bar) in waveformBars.enumerated() {
            let height = barHeights[index]
            bar.frame = NSRect(
                x: leadingX + CGFloat(index) * (barWidth + barGap),
                y: bounds.midY - (height / 2),
                width: barWidth,
                height: height
            )
            bar.cornerRadius = 0
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWaveformAnimation()
    }

    func showSymbol(named name: String, accessibilityDescription: String, tint: NSColor) {
        isShowingWaveform = false
        waveformLayer.isHidden = true
        waveformBars.forEach { $0.removeAnimation(forKey: "waveform-scale") }
        image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        contentTintColor = tint
    }

    func showWaveform() {
        isShowingWaveform = true
        image = nil
        waveformLayer.isHidden = false
        waveformBars.forEach { $0.backgroundColor = NSColor.systemBlue.cgColor }
        updateWaveformAnimation()
    }

    private func updateWaveformAnimation() {
        waveformBars.forEach { $0.removeAnimation(forKey: "waveform-scale") }
        guard isShowingWaveform,
              window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }

        let patterns: [[NSNumber]] = [
            [0.55, 1.0, 0.70, 0.90, 0.55],
            [0.95, 0.50, 0.82, 0.62, 0.95],
            [0.62, 0.88, 0.48, 1.0, 0.62],
            [0.82, 0.54, 1.0, 0.68, 0.82]
        ]

        for (bar, values) in zip(waveformBars, patterns) {
            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = values
            animation.keyTimes = [0, 0.28, 0.52, 0.76, 1]
            animation.duration = 0.88
            animation.repeatCount = .infinity
            animation.timingFunctions = Array(
                repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                count: values.count - 1
            )
            bar.add(animation, forKey: "waveform-scale")
        }
    }
}

@MainActor
private final class ReadAloudPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

private enum PanelReadingState: Equatable {
    case waiting
    case preparing
    case playing
    case paused
    case completed
    case stopped
    case failed
}

/// dsh-omi-voice 本地服务（LocalTTSService）调用朗读入口时的错误。
enum RemoteSpeakError: LocalizedError {
    case invalidText
    case keyNotConfigured

    var errorDescription: String? {
        switch self {
        case .invalidText:
            return "文本为空或没有可朗读的内容"
        case .keyNotConfigured:
            return "请先在 Omi 设置页配置豆包 API Key"
        }
    }
}

/// 引擎朗读状态快照（供本地 HTTP 服务返回，不暴露内部枚举类型）。
struct RemoteEngineStatus: Sendable {
    let playing: Bool
    let paused: Bool
    let preparing: Bool
    let state: String
    let message: String?
}

@MainActor
final class ReadAloudServiceProvider: NSObject, NSWindowDelegate {
    private let controller = ReadAloudController()
    private var panel: NSPanel?
    private var rootStack: NSStackView?
    private var statusRow: NSStackView?
    private var statusLabel: CopyableStatusTextView?
    private var playbackButton: PlaybackButton?
    private var speedHeader: NSStackView?
    private var speedValueLabel: NSTextField?
    private var speedSlider: DiscreteRateSlider?
    private var settingsStack: NSStackView?
    private var readingSettingsStack: NSStackView?
    private var settingsButton: NSButton?
    private var settingsAccessoryController: NSTitlebarAccessoryViewController?
    private var modelField: NSTextField?
    private var apiKeyField: NSSecureTextField?
    private var resourceIDField: NSTextField?
    private var voiceIDField: NSTextField?
    private var settingsStateLabel: NSTextField?
    private var launchAtLoginSwitch: NSSwitch?
    private var providerSettings = ReadAloudProviderSettings.load()
    private var isSettingsVisible = false
    private var currentText = ""
    private var currentRate = ReadAloudPlaybackPreferences.loadRate()
    private var requestGeneration = 0
    private var readingTask: Task<Void, Never>?
    private var panelReadingState: PanelReadingState = .waiting
    private var panelReadingMessage: String?
    private var isPanelHiddenByUser = false
    private let audioCache = ReadAloudLastAudioCache()
    private var activeRequestKey: ReadAloudAudioCacheKey?

    /// macOS Services 入口：接收当前应用选中的纯文本。
    @objc(readAloud:userData:error:)
    func readAloud(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            serviceLog("service-request rejected: empty-text")
            error.pointee = "没有可朗读的选中文本。" as NSString
            return
        }
        enqueue(text, html: pboard.string(forType: .html), source: "service")
    }

    /// Codex 网页容器不派发 macOS Services 时的可靠回退：用户先复制选中文本，再从菜单栏触发。
    @objc func readClipboard() {
        let pasteboard = NSPasteboard.general
        let typeNames = (pasteboard.types ?? []).map(\.rawValue).joined(separator: ",")
        let text = pasteboard.string(forType: .string)
        serviceLog(
            "clipboard-read changeCount=\(pasteboard.changeCount) hasText=\(text != nil) types=\(typeNames)"
        )
        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showPanelForReadingRequestIfAllowed()
            guard !isReadingActive else {
                serviceLog("clipboard-request rejected: empty-text active-session-preserved")
                return
            }
            updateReadingPresentation(.waiting, message: "请先复制选中的文本")
            return
        }
        enqueue(text, html: pasteboard.string(forType: .html), source: "clipboard")
    }

    private var isReadingActive: Bool {
        panelReadingState == .preparing
            || panelReadingState == .playing
            || panelReadingState == .paused
    }

    @discardableResult
    private func enqueue(_ text: String, html: String? = nil, source: String) -> Int {
        showPanelForReadingRequestIfAllowed()
        let prepared = ReadAloudTextPreparation.prepare(plainText: text, html: html)
        let hasSpeakableContent = ReadAloudTextPreparation.containsSpeakableContent(prepared.text)
        let segments = hasSpeakableContent
            ? ReadAloudTextPreparation.segments(for: prepared.text)
            : []
        serviceLog(
            "reading-text prepared source=\(source) rawCharacters=\(text.count) sentCharacters=\(prepared.text.count) removedTableBlocks=\(prepared.removedTableBlocks) removedNonReadable=\(prepared.removedNonReadableBlocks) hasSpeakableContent=\(hasSpeakableContent) segments=\(segments.count)"
        )
        guard !segments.isEmpty else {
            guard !isReadingActive else {
                serviceLog("request rejected: no-readable-text active-session-preserved")
                return 0
            }
            currentText = ""
            activeRequestKey = nil
            updateReadingPresentation(
                .waiting,
                message: prepared.text.isEmpty && prepared.removedTableBlocks > 0
                    ? "表格内容暂不支持朗读"
                    : "没有可朗读的文字内容"
            )
            serviceLog("request rejected: no-readable-text")
            return 0
        }

        let preparedText = prepared.text
        let cacheKey = makeAudioCacheKey(text: preparedText, rate: currentRate)
        guard !(isReadingActive && cacheKey == activeRequestKey) else {
            serviceLog("request deduplicated source=\(source) textLength=\(preparedText.count) active-session-preserved")
            return segments.count
        }
        serviceLog("request accepted source=\(source) textLength=\(preparedText.count)")
        currentText = preparedText
        startReading(preparedText, segments: segments, cacheKey: cacheKey)
        return segments.count
    }

    private func showPanelForReadingRequestIfAllowed() {
        guard panel == nil || !isPanelHiddenByUser else {
            serviceLog("panel-kept-hidden source=reading-request")
            return
        }
        showPanel()
    }

    private func showPanel() {
        if let panel {
            if panel.isMiniaturized {
                panel.deminiaturize(nil)
            }
            panel.orderFrontRegardless()
            return
        }

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
        let status = CopyableStatusTextView(frame: .zero)
        status.string = "正在准备朗读"
        status.font = .systemFont(ofSize: NSFont.systemFontSize)
        status.textColor = .secondaryLabelColor
        status.isSelectable = true
        status.isEditable = false
        status.drawsBackground = false
        status.isRichText = false
        status.importsGraphics = false
        status.allowsUndo = false
        status.textContainerInset = .zero
        status.textContainer?.lineFragmentPadding = 0
        status.textContainer?.maximumNumberOfLines = 2
        status.textContainer?.lineBreakMode = .byTruncatingTail
        status.textContainer?.widthTracksTextView = true
        status.textContainer?.heightTracksTextView = true
        status.isHorizontallyResizable = false
        status.isVerticallyResizable = false
        status.toolTip = "点入后按 ⌘C，或右键复制完整状态或错误信息"
        status.setAccessibilityLabel("朗读状态")
        status.setAccessibilityHelp("点入后按 Command C，或右键复制完整状态或错误信息")
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel = status

        let playbackButton = PlaybackButton(
            image: NSImage(
                systemSymbolName: "speaker.wave.2.fill",
                accessibilityDescription: "开始朗读"
            ) ?? NSImage(),
            target: self,
            action: #selector(togglePlayback)
        )
        playbackButton.bezelStyle = .inline
        playbackButton.isBordered = false
        playbackButton.imageScaling = .scaleProportionallyDown
        playbackButton.toolTip = "开始朗读"
        playbackButton.setAccessibilityLabel("开始朗读")
        playbackButton.isEnabled = false
        playbackButton.translatesAutoresizingMaskIntoConstraints = false
        self.playbackButton = playbackButton

        let statusRow = NSStackView(views: [status, NSView(), playbackButton])
        statusRow.orientation = .horizontal
        statusRow.alignment = .firstBaseline
        statusRow.distribution = .fill
        statusRow.spacing = 8
        self.statusRow = statusRow

        let settingsStack = makeSettingsStack()
        settingsStack.isHidden = true
        self.settingsStack = settingsStack

        let speedTitle = NSTextField(labelWithString: "语速")
        speedTitle.font = .systemFont(ofSize: 11)
        speedTitle.textColor = .secondaryLabelColor
        let speedValue = NSTextField(labelWithString: rateText(currentRate))
        speedValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        speedValue.alignment = .right
        speedValueLabel = speedValue
        let speedHeader = NSStackView(views: [speedTitle, NSView(), speedValue])
        speedHeader.orientation = .horizontal
        speedHeader.alignment = .centerY
        self.speedHeader = speedHeader

        let speedSlider = DiscreteRateSlider(
            rate: currentRate,
            target: self,
            action: #selector(rateChanged(_:))
        )
        self.speedSlider = speedSlider

        let stack = NSStackView(views: [statusRow, settingsStack, speedHeader, speedSlider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootStack = stack
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            statusRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            settingsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            speedHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            speedSlider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.heightAnchor.constraint(equalToConstant: 34),
            playbackButton.widthAnchor.constraint(equalToConstant: 30),
            playbackButton.heightAnchor.constraint(equalToConstant: 30),
            speedHeader.heightAnchor.constraint(equalToConstant: 16),
            speedSlider.heightAnchor.constraint(equalToConstant: 32)
        ])

        let window = ReadAloudPanel(
            contentRect: content.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Omi dsh"
        window.delegate = self
        window.contentView = content
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 300, height: 140)
        window.contentMaxSize = NSSize(width: 300, height: 470)
        window.setContentSize(NSSize(width: 300, height: 140))
        let minimumFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: window.contentMinSize)
        ).size
        let maximumFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: window.contentMaxSize)
        ).size
        window.minSize = minimumFrameSize
        window.maxSize = maximumFrameSize
        installSettingsButton(on: window)
        window.center()
        window.orderFrontRegardless()
        panel = window
        serviceLog("panel-shown source=request")
    }

    private func makeSettingsStack() -> NSStackView {
        let readingStack = makeReadingSettingsStack()
        readingSettingsStack = readingStack

        let stack = NSStackView(views: [readingStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 12
        readingStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeReadingSettingsStack() -> NSStackView {
        let modelField = NSTextField(string: providerSettings.model)
        modelField.placeholderString = ReadAloudProviderSettings.defaultModel
        modelField.toolTip = "产品配置标识；当前 V3 服务实际由 Resource ID 选择"
        modelField.setAccessibilityHelp("产品配置标识；当前 V3 服务实际由 Resource ID 选择")
        self.modelField = modelField

        let apiKeyField = NSSecureTextField(string: "")
        apiKeyField.placeholderString = "输入新 Key；留空则保持现有 Key"
        apiKeyField.toolTip = "已保存的 API Key 不会回显"
        self.apiKeyField = apiKeyField

        let resourceIDField = NSTextField(string: providerSettings.resourceID)
        resourceIDField.placeholderString = ReadAloudProviderSettings.defaultResourceID
        self.resourceIDField = resourceIDField

        let voiceIDField = NSTextField(string: providerSettings.voiceID)
        voiceIDField.placeholderString = ReadAloudProviderSettings.defaultVoiceID
        self.voiceIDField = voiceIDField

        let state = NSTextField(labelWithString: "API Key 不回显")
        state.font = .systemFont(ofSize: 11)
        state.textColor = .secondaryLabelColor
        state.lineBreakMode = .byTruncatingTail
        state.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        settingsStateLabel = state

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .regular
        saveButton.setAccessibilityLabel("保存朗读配置")

        let actionRow = NSStackView(views: [state, NSView(), saveButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        actionRow.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let modelRow = makeSettingsRow(title: "模型", field: modelField)
        let apiKeyRow = makeSettingsRow(title: "API Key", field: apiKeyField)
        let resourceIDRow = makeSettingsRow(title: "Resource ID", field: resourceIDField)
        let voiceIDRow = makeSettingsRow(title: "音色 ID", field: voiceIDField)
        let divider = NSBox()
        divider.boxType = .separator

        let preferencesTitle = NSTextField(labelWithString: "应用偏好")
        preferencesTitle.font = .systemFont(ofSize: 11)
        preferencesTitle.textColor = .secondaryLabelColor

        let launchAtLoginLabel = NSTextField(labelWithString: "开机启动")
        launchAtLoginLabel.font = .systemFont(ofSize: 13)
        launchAtLoginLabel.setAccessibilityLabel("开机启动")

        let launchAtLoginSwitch = NSSwitch()
        launchAtLoginSwitch.controlSize = .small
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginSwitch.setAccessibilityLabel("开机启动")
        launchAtLoginSwitch.setAccessibilityHelp("登录 Mac 后自动启动 Omi")
        self.launchAtLoginSwitch = launchAtLoginSwitch
        refreshLaunchAtLoginSwitch()

        let launchAtLoginRow = NSStackView(views: [launchAtLoginLabel, NSView(), launchAtLoginSwitch])
        launchAtLoginRow.orientation = .horizontal
        launchAtLoginRow.alignment = .centerY
        launchAtLoginRow.spacing = 8
        launchAtLoginRow.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let rows = [modelRow, apiKeyRow, resourceIDRow, voiceIDRow, actionRow, divider, preferencesTitle, launchAtLoginRow]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 8
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func makeSettingsRow(title: String, field: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: 12)
        field.controlSize = .small
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let row = NSStackView(views: [label, field])
        row.orientation = .vertical
        row.alignment = .leading
        row.distribution = .fill
        row.spacing = 4
        field.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        return row
    }

    private func installSettingsButton(on window: NSWindow) {
        let symbol = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "打开设置"
        )
        let button = NSButton(image: symbol ?? NSImage(), target: self, action: #selector(toggleSettings))
        button.bezelStyle = .inline
        button.isBordered = false
        button.toolTip = "打开设置"
        button.setButtonType(.toggle)
        button.setAccessibilityLabel("打开设置")
        button.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 34, height: 28))
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(accessory)
        settingsButton = button
        settingsAccessoryController = accessory
    }

    @objc private func toggleSettings() {
        isSettingsVisible.toggle()
        settingsStack?.isHidden = !isSettingsVisible
        settingsButton?.state = isSettingsVisible ? .on : .off
        settingsButton?.toolTip = isSettingsVisible ? "关闭设置" : "打开设置"
        settingsButton?.setAccessibilityLabel(isSettingsVisible ? "关闭设置" : "打开设置")
        if isSettingsVisible {
            refreshSettingsFields()
        } else {
            statusRow?.isHidden = false
            speedHeader?.isHidden = false
            speedSlider?.isHidden = false
            updateReadingPresentation(panelReadingState, message: panelReadingMessage)
        }
        resizePanelForCurrentMode()
        serviceLog("settings-panel \(isSettingsVisible ? "opened" : "closed")")
    }

    func textDidChange(_ notification: Notification) {
        // 文本预览功能已移除；保留占位避免误删未来委托入口。
    }

    private func refreshSettingsFields() {
        providerSettings = ReadAloudProviderSettings.load()
        modelField?.stringValue = providerSettings.model
        resourceIDField?.stringValue = providerSettings.resourceID
        voiceIDField?.stringValue = providerSettings.voiceID
        apiKeyField?.stringValue = ""
        settingsStateLabel?.stringValue = "API Key 不回显；留空保持不变"
        settingsStateLabel?.textColor = .secondaryLabelColor
        refreshLaunchAtLoginSwitch()
    }

    private func refreshLaunchAtLoginSwitch() {
        guard let launchAtLoginSwitch else { return }
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            launchAtLoginSwitch.state = .on
        case .notRegistered, .notFound:
            launchAtLoginSwitch.state = .off
        @unknown default:
            launchAtLoginSwitch.state = .off
        }
    }

    @objc private func launchAtLoginChanged(_ sender: NSSwitch) {
        let service = SMAppService.mainApp
        do {
            if sender.state == .on {
                try service.register()
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            refreshLaunchAtLoginSwitch()
            serviceLog("launch-at-login updated enabled=\(sender.state == .on)")
            if service.status == .requiresApproval {
                presentLaunchAtLoginApproval()
            }
        } catch {
            refreshLaunchAtLoginSwitch()
            serviceLog("launch-at-login update-failed \(ReadAloudDiagnostics.logFields(for: error))")
            presentLaunchAtLoginFailure(error)
        }
    }

    private func presentLaunchAtLoginApproval() {
        let alert = NSAlert()
        alert.messageText = "请允许 Omi 开机启动"
        alert.informativeText = "请在系统设置的“登录项”中允许 Omi。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func presentLaunchAtLoginFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "无法更新开机启动"
        alert.informativeText = userFacingErrorMessage(error)
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func saveSettings() {
        let model = normalized(modelField?.stringValue)
        let resourceID = normalized(resourceIDField?.stringValue)
        let voiceID = normalized(voiceIDField?.stringValue)
        guard let model, let resourceID, let voiceID else {
            settingsStateLabel?.stringValue = "模型、Resource ID 和音色 ID 不能为空"
            settingsStateLabel?.textColor = .systemRed
            return
        }

        do {
            let replacementKey = normalized(apiKeyField?.stringValue)
            if let replacementKey {
                try KeychainStore().save(replacementKey)
            }

            let newSettings = ReadAloudProviderSettings(
                model: model,
                resourceID: resourceID,
                voiceID: voiceID
            )
            newSettings.save()
            providerSettings = newSettings
            apiKeyField?.stringValue = ""

            settingsStateLabel?.stringValue = replacementKey == nil
                ? "配置已保存；API Key 保持不变"
                : "配置已保存；API Key 已更新且不回显"
            settingsStateLabel?.textColor = .secondaryLabelColor
            statusLabel?.string = "配置已保存"
            serviceLog("provider-settings saved keyUpdated=\(replacementKey != nil)")
        } catch {
            settingsStateLabel?.stringValue = userFacingErrorMessage(error)
            settingsStateLabel?.textColor = .systemRed
            serviceLog("provider-settings save-failed \(ReadAloudDiagnostics.logFields(for: error))")
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func resizePanelForCurrentMode() {
        guard let window = panel else { return }
        let targetHeight: CGFloat = isSettingsVisible ? 450 : 140
        let targetContentSize = NSSize(width: 300, height: targetHeight)
        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size
        var targetFrame = window.frame
        targetFrame.origin.y += targetFrame.height - targetFrameSize.height
        targetFrame.size = targetFrameSize
        window.setFrame(targetFrame, display: true, animate: false)
    }

    private func makeAudioCacheKey(text: String, rate: Float) -> ReadAloudAudioCacheKey {
        ReadAloudAudioCacheKey(
            text: text,
            model: providerSettings.model,
            resourceID: providerSettings.resourceID,
            voiceID: providerSettings.voiceID,
            speechRate: Int(((rate - 1.0) * 100).rounded()),
            sampleRate: 24_000
        )
    }

    private func readAPIKeyWithRetry() async throws -> String {
        let store = KeychainStore()
        do {
            return try store.read()
        } catch KeychainError.accessDenied {
            for delay in [300_000_000, 700_000_000] {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: UInt64(delay))
                do {
                    return try store.read()
                } catch KeychainError.accessDenied {
                    continue
                }
            }
            throw KeychainError.accessDenied
        }
    }

    private func startReading(
        _ text: String,
        segments suppliedSegments: [String]? = nil,
        cacheKey suppliedCacheKey: ReadAloudAudioCacheKey? = nil
    ) {
        readingTask?.cancel()
        updateReadingPresentation(.preparing)
        requestGeneration += 1
        let generation = requestGeneration
        let synthesisRate = currentRate
        let segments = suppliedSegments ?? ReadAloudTextPreparation.segments(for: text)
        let cacheKey = suppliedCacheKey ?? makeAudioCacheKey(text: text, rate: synthesisRate)
        activeRequestKey = cacheKey
        setRateControlEnabled(false)
        controller.setRate(1.0)
        readingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                await controller.stop()
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }
                serviceLog("previous-session-cleared")
                let client: any TTSClient
                if let cachedAudio = await audioCache.audio(for: cacheKey) {
                    serviceLog(
                        "tts-cache hit chunks=\(cachedAudio.chunks.count) bytes=\(cachedAudio.totalBytes)"
                    )
                    client = CachedAudioTTSClient(audio: cachedAudio)
                } else {
                    serviceLog("tts-cache miss")
                    let key = try await readAPIKeyWithRetry()
                    try Task.checkCancellation()
                    guard generation == requestGeneration else { return }
                    ReadAloudDiagnostics.registerSensitiveValue(key)
                    serviceLog("keychain-read ok")
                    var configuration = TTSConfiguration(apiKey: key)
                    configuration.model = providerSettings.model
                    configuration.resourceID = providerSettings.resourceID
                    configuration.voiceType = providerSettings.voiceID
                    configuration.speechRate = cacheKey.speechRate
                    serviceLog(
                        "tts-request profile=configured speechRate=\(configuration.speechRate) targetRate=\(rateText(synthesisRate))"
                    )
                    let networkClient = SegmentedTTSClient(
                        base: DoubaoHTTPStreamingClient(configuration: configuration),
                        segments: segments
                    )
                    serviceLog(
                        "tts-request segmented count=\(segments.count) maximumBytes=\(ReadAloudTextPreparation.defaultMaximumSegmentBytes)"
                    )
                    client = RecordingTTSClient(
                        base: networkClient,
                        key: cacheKey,
                        cache: audioCache,
                        onStored: { stored, chunkCount, byteCount in
                            Task { @MainActor in
                                serviceLog(
                                    "tts-cache store=\(stored) chunks=\(chunkCount) bytes=\(byteCount)"
                                )
                            }
                        }
                    )
                }
                try await controller.start(text: text, client: client) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, generation == requestGeneration else { return }
                        updateReadingPresentation(.playing)
                        serviceLog("playback-started")
                    }
                }
                try Task.checkCancellation()
                serviceLog("controller-started")
                await controller.waitUntilFinished()
                guard generation == requestGeneration else { return }
                switch await controller.session.state {
                case .failed(let message):
                    serviceLog("session-failed \(message)")
                    updateReadingPresentation(.failed, message: message)
                case .stopped:
                    serviceLog("session-stopped")
                    updateReadingPresentation(.stopped)
                default:
                    serviceLog("session-finished")
                    updateReadingPresentation(.completed)
                }
                readingTask = nil
                setRateControlEnabled(true)
            } catch {
                guard generation == requestGeneration else { return }
                readingTask = nil
                serviceLog("service-error \(ReadAloudDiagnostics.logFields(for: error))")
                updateReadingPresentation(.failed, message: userFacingErrorMessage(error))
                setRateControlEnabled(true)
            }
        }
    }

    private func updateReadingPresentation(_ state: PanelReadingState, message: String? = nil) {
        panelReadingState = state
        panelReadingMessage = message

        let symbolName: String
        let symbolTint: NSColor
        let actionLabel: String
        let isButtonEnabled: Bool

        switch state {
        case .waiting:
            statusLabel?.string = message ?? "等待朗读"
            symbolName = "speaker.wave.2.fill"
            symbolTint = .controlAccentColor
            actionLabel = "开始朗读"
            isButtonEnabled = !currentText.isEmpty
        case .preparing:
            statusLabel?.string = "正在准备朗读"
            symbolName = "speaker.slash"
            symbolTint = .labelColor
            actionLabel = "停止朗读"
            isButtonEnabled = true
        case .playing:
            statusLabel?.string = "朗读中"
            symbolName = "speaker.slash"
            symbolTint = .controlAccentColor
            actionLabel = "暂停朗读"
            isButtonEnabled = true
        case .paused:
            statusLabel?.string = "已暂停朗读"
            symbolName = "speaker.wave.2"
            symbolTint = .secondaryLabelColor
            actionLabel = "继续朗读"
            isButtonEnabled = true
        case .completed:
            statusLabel?.string = "朗读完成"
            symbolName = "speaker.wave.2.fill"
            symbolTint = .controlAccentColor
            actionLabel = "重新朗读"
            isButtonEnabled = !currentText.isEmpty
        case .stopped:
            statusLabel?.string = "已停止朗读"
            symbolName = "speaker.wave.2.fill"
            symbolTint = .controlAccentColor
            actionLabel = "重新朗读"
            isButtonEnabled = !currentText.isEmpty
        case .failed:
            statusLabel?.string = message ?? "朗读失败"
            symbolName = "speaker.wave.2.fill"
            symbolTint = .controlAccentColor
            actionLabel = "重新朗读"
            isButtonEnabled = !currentText.isEmpty
        }

        if state == .playing {
            playbackButton?.showWaveform()
        } else {
            playbackButton?.showSymbol(
                named: symbolName,
                accessibilityDescription: actionLabel,
                tint: symbolTint
            )
        }
        playbackButton?.toolTip = actionLabel
        playbackButton?.setAccessibilityLabel(actionLabel)
        playbackButton?.isEnabled = isButtonEnabled
    }

    @objc private func togglePlayback() {
        switch panelReadingState {
        case .preparing:
            stopReading()
        case .playing:
            pauseReading()
        case .paused:
            resumeReading()
        case .waiting, .completed, .stopped, .failed:
            guard !currentText.isEmpty else { return }
            startReading(currentText)
        }
    }

    private func pauseReading() {
        let generation = requestGeneration
        Task { @MainActor [weak self] in
            guard let self, generation == requestGeneration else { return }
            guard await controller.pause() else { return }
            guard generation == requestGeneration else { return }
            updateReadingPresentation(.paused)
            serviceLog("reading-paused")
        }
    }

    private func resumeReading() {
        let generation = requestGeneration
        Task { @MainActor [weak self] in
            guard let self, generation == requestGeneration else { return }
            guard await controller.resume() else { return }
            guard generation == requestGeneration else { return }
            updateReadingPresentation(.playing)
            serviceLog("reading-resumed")
        }
    }

    private func userFacingErrorMessage(_ error: Error) -> String {
        ReadAloudDiagnostics.userFacingMessage(error)
    }

    private func rateText(_ rate: Float) -> String {
        String(format: "%.1f×", rate)
    }

    @objc private func rateChanged(_ sender: DiscreteRateSlider) {
        guard sender.isEnabled else { return }
        currentRate = sender.rate
        ReadAloudPlaybackPreferences.saveRate(currentRate)
        let text = rateText(currentRate)
        speedValueLabel?.stringValue = text
        serviceLog("speech-rate selected rate=\(text) appliesTo=next-request")
    }

    private func setRateControlEnabled(_ enabled: Bool) {
        speedSlider?.isEnabled = enabled
        speedSlider?.toolTip = enabled
            ? "1.0× 到 2.0×，每次调整 0.1×"
            : "朗读结束后可调整语速"
        speedValueLabel?.textColor = enabled ? .labelColor : .disabledControlTextColor
    }

    @objc private func stopReading() {
        requestGeneration += 1
        readingTask?.cancel()
        readingTask = nil
        let generation = requestGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            await controller.stop()
            guard generation == requestGeneration else { return }
            updateReadingPresentation(.stopped)
            setRateControlEnabled(true)
            serviceLog("reading-stopped source=menu")
        }
    }

    @objc func stopReadingFromMenu() {
        stopReading()
    }

    func showPanelFromUserAction(source: String) {
        isPanelHiddenByUser = false
        showPanel()
        if currentText.isEmpty {
            updateReadingPresentation(.waiting)
        }
        serviceLog("panel-shown source=\(source)")
    }

    func windowDidMiniaturize(_ notification: Notification) {
        isPanelHiddenByUser = true
        serviceLog("panel-hidden source=window-minimize")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        isPanelHiddenByUser = true
        sender.orderOut(nil)
        serviceLog("panel-hidden source=window-close")
        return false
    }

    // MARK: - dsh-omi-voice 本地服务入口（LocalTTSService 调用，均需 MainActor）

    var remoteEngineStatus: RemoteEngineStatus {
        switch panelReadingState {
        case .playing:
            return RemoteEngineStatus(playing: true, paused: false, preparing: false, state: "playing", message: nil)
        case .paused:
            return RemoteEngineStatus(playing: false, paused: true, preparing: false, state: "paused", message: nil)
        case .preparing:
            return RemoteEngineStatus(playing: false, paused: false, preparing: true, state: "preparing", message: nil)
        case .failed:
            return RemoteEngineStatus(playing: false, paused: false, preparing: false, state: "failed", message: panelReadingMessage)
        case .waiting, .completed, .stopped:
            return RemoteEngineStatus(playing: false, paused: false, preparing: false, state: "idle", message: nil)
        }
    }

    var remoteKeyConfigured: Bool {
        (try? KeychainStore().read()) != nil
    }

    var remoteVoiceID: String {
        providerSettings.voiceID
    }

    func remoteStop() {
        stopReading()
    }

    func remotePause() {
        pauseReading()
    }

    func remoteResume() {
        resumeReading()
    }

    func remoteSpeak(text: String, rate: Float?) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RemoteSpeakError.invalidText }
        // 内容校验先于 Key 校验：无有效内容时，即使未配 Key 也返回 invalid_text
        let prepared = ReadAloudTextPreparation.prepare(plainText: trimmed, html: nil)
        let hasSpeakableContent = ReadAloudTextPreparation.containsSpeakableContent(prepared.text)
        let segments = hasSpeakableContent
            ? ReadAloudTextPreparation.segments(for: prepared.text)
            : []
        guard !segments.isEmpty else { throw RemoteSpeakError.invalidText }
        guard remoteKeyConfigured else { throw RemoteSpeakError.keyNotConfigured }
        if let rate {
            let step = Int((rate * 10).rounded())
            let normalizedRate = Float(step) / 10
            if (10...20).contains(step), abs(rate - normalizedRate) < 0.0001 {
                currentRate = normalizedRate
                ReadAloudPlaybackPreferences.saveRate(normalizedRate)
                serviceLog("localtts speech-rate applied rate=\(rateText(normalizedRate))")
            }
        }
        enqueue(trimmed, html: nil, source: "dsh-plugin")
        return segments.count
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let provider = ReadAloudServiceProvider()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let localTTS = LocalTTSService(provider: provider)
        do {
            try localTTS.start()
            localTTSService = localTTS
            serviceLog("localtts start ok port=\(localTTS.port)")
        } catch {
            serviceLog("localtts start-failed \(ReadAloudDiagnostics.logFields(for: error))")
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = provider
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let logoURL = Bundle.main.url(forResource: "Omi_logo", withExtension: "svg"),
           let logoImage = NSImage(contentsOf: logoURL) {
            logoImage.size = NSSize(width: 20, height: 20)
            logoImage.size = NSSize(width: 20, height: 20)
            // Omi dsh 版本：彩色显示，与安装版（模板图标）区分
            logoImage.isTemplate = false
            logoImage.accessibilityDescription = "Omi dsh"
            item.button?.image = logoImage
        } else {
            item.button?.image = NSImage(
                systemSymbolName: "speaker.wave.2",
                accessibilityDescription: "Omi dsh"
            )
            serviceLog("menu-bar-logo fallback=system-symbol")
        }
        item.button?.setAccessibilityLabel("Omi dsh")
        item.button?.toolTip = "Omi dsh（本地朗读引擎）"
        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        let hint = NSMenuItem(title: "复制文本后按 ⌥⇧Q", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        let readItem = NSMenuItem(title: "朗读剪贴板内容", action: #selector(readClipboard), keyEquivalent: "")
        readItem.target = self
        menu.addItem(readItem)
        let stopItem = NSMenuItem(title: "停止朗读", action: #selector(stopReading), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 Omi dsh", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        let bridge = GlobalHotKeyBridge { [weak self] in
            self?.provider.readClipboard()
        }
        do {
            try bridge.start()
            hotKeyBridge = bridge
            serviceLog("global-hotkey registered modifiers=option+shift key=Q")
        } catch {
            serviceLog("global-hotkey registration-failed \(ReadAloudDiagnostics.logFields(for: error))")
        }
        serviceLog("application-launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        localTTSService?.stop()
        localTTSService = nil
        hotKeyBridge?.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        provider.showPanelFromUserAction(source: "status-item")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        provider.showPanelFromUserAction(source: "reopen")
        return true
    }

    @objc private func readClipboard() {
        provider.readClipboard()
    }

    @objc private func stopReading() {
        provider.stopReadingFromMenu()
    }

    @objc private func quitApplication() {
        serviceLog("application-quit requested")
        NSApp.terminate(nil)
    }

    private var hotKeyBridge: GlobalHotKeyBridge?
    private var localTTSService: LocalTTSService?
}

@main
struct ReadAloudServiceApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
