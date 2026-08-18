import Foundation

struct ReadAloudPreparedText: Equatable, Sendable {
    let text: String
    let removedTableBlocks: Int
    var removedNonReadableBlocks: Int = 0
}

/// 在文本进入缓存、Keychain 和 TTS 网络请求前执行的本地预处理。
/// 只移除高置信度表格、代码围栏与纯图形行；普通段落、编号、项目符号和标点保持原样。
enum ReadAloudTextPreparation {
    /// 留出 JSON 编码和服务端限制余量，避免单段逼近 1024 UTF-8 字节。
    static let defaultMaximumSegmentBytes = 900

    static func prepare(plainText: String, html: String? = nil) -> ReadAloudPreparedText {
        let plainResult = removingPlainTextTables(from: plainText)

        let base: ReadAloudPreparedText
        if let html,
           containsHTMLTable(html),
           plainResult.removedTableBlocks == 0 {
            let htmlResult = removingHTMLTables(from: html)
            base = htmlResult.removedTableBlocks > 0 ? htmlResult : plainResult
        } else {
            base = plainResult
        }

        let cleaned = removingNonReadableBlocks(from: base.text)
        return ReadAloudPreparedText(
            text: cleaned.text,
            removedTableBlocks: base.removedTableBlocks,
            removedNonReadableBlocks: base.removedNonReadableBlocks + cleaned.removedNonReadableBlocks
        )
    }

    /// 至少包含一个 Unicode 字母或数字，才值得进入语音服务。
    /// 语言是否与音色匹配属于独立节点，这里不判断具体语种。
    static func containsSpeakableContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                 .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber:
                return true
            default:
                return false
            }
        }
    }

    static func segments(
        for text: String,
        maximumUTF8Bytes: Int = defaultMaximumSegmentBytes
    ) -> [String] {
        precondition(maximumUTF8Bytes > 0)
        var remaining = text[...]
        var result: [String] = []

        while !remaining.isEmpty {
            if remaining.utf8.count <= maximumUTF8Bytes {
                appendSegment(String(remaining), to: &result)
                break
            }

            var byteCount = 0
            var maximumEnd = remaining.startIndex
            var strongBoundary: (index: String.Index, bytes: Int)?
            var secondaryBoundary: (index: String.Index, bytes: Int)?
            var cursor = remaining.startIndex

            while cursor < remaining.endIndex {
                let next = remaining.index(after: cursor)
                let character = remaining[cursor]
                let characterBytes = String(character).utf8.count
                guard byteCount + characterBytes <= maximumUTF8Bytes else { break }
                byteCount += characterBytes
                maximumEnd = next

                if isStrongBoundary(character) {
                    strongBoundary = (next, byteCount)
                } else if isSecondaryBoundary(character) {
                    secondaryBoundary = (next, byteCount)
                }
                cursor = next
            }

            guard maximumEnd > remaining.startIndex else { break }
            let minimumPreferredBytes = maximumUTF8Bytes / 2
            let splitEnd: String.Index
            if let strongBoundary, strongBoundary.bytes >= minimumPreferredBytes {
                splitEnd = strongBoundary.index
            } else if let secondaryBoundary {
                splitEnd = secondaryBoundary.index
            } else if let strongBoundary {
                splitEnd = strongBoundary.index
            } else {
                splitEnd = maximumEnd
            }

            appendSegment(String(remaining[..<splitEnd]), to: &result)
            remaining = remaining[splitEnd...]
            while let first = remaining.first, first.isWhitespace {
                remaining = remaining.dropFirst()
            }
        }

        return result
    }

    private static func appendSegment(_ value: String, to result: inout [String]) {
        let segment = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { return }
        result.append(segment)
    }

    private static func isStrongBoundary(_ character: Character) -> Bool {
        character == "。" || character == "！" || character == "？"
            || character == "!" || character == "?" || character == "；"
            || character == ";" || character == "\n"
    }

    private static func isSecondaryBoundary(_ character: Character) -> Bool {
        character == "，" || character == "," || character == "、"
            || character == "：" || character == ":" || character.isWhitespace
    }

    private static func removingPlainTextTables(from sourceText: String) -> ReadAloudPreparedText {
        let normalized = sourceText.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var removed = Array(repeating: false, count: lines.count)
        var tableCount = 0
        var index = 0

        while index < lines.count {
            if index + 1 < lines.count,
               isMarkdownHeader(lines[index]),
               isMarkdownDelimiter(lines[index + 1]) {
                var end = index + 2
                while end < lines.count, isPipeRow(lines[end]) {
                    end += 1
                }
                for lineIndex in index..<end {
                    removed[lineIndex] = true
                }
                tableCount += 1
                index = end
                continue
            }

            if isTabularRow(lines[index]) {
                var end = index + 1
                while end < lines.count, isTabularRow(lines[end]) {
                    end += 1
                }
                if end - index >= 2 {
                    for lineIndex in index..<end {
                        removed[lineIndex] = true
                    }
                    tableCount += 1
                    index = end
                    continue
                }
            }
            index += 1
        }

        let retained = lines.enumerated().compactMap { offset, line in
            removed[offset] ? nil : line
        }
        return ReadAloudPreparedText(
            text: retained.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            removedTableBlocks: tableCount
        )
    }

    private static func isMarkdownHeader(_ line: String) -> Bool {
        guard let cells = pipeCells(in: line), cells.count >= 2 else { return false }
        return cells.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func isMarkdownDelimiter(_ line: String) -> Bool {
        guard let cells = pipeCells(in: line), cells.count >= 2 else { return false }
        return cells.allSatisfy { cell in
            let compact = cell.filter { !$0.isWhitespace && $0 != ":" }
            return !compact.isEmpty && compact.allSatisfy { $0 == "-" || $0 == "–" || $0 == "—" }
        }
    }

    private static func isPipeRow(_ line: String) -> Bool {
        guard let cells = pipeCells(in: line), cells.count >= 2 else { return false }
        return cells.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func pipeCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var body = trimmed
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        let cells = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return cells.count >= 2 ? cells : nil
    }

    private static func isTabularRow(_ line: String) -> Bool {
        let cells = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard cells.count >= 2 else { return false }
        return cells.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
    }

    // MARK: - 代码围栏与图形行过滤

    /// 移除代码围栏（``` / ~~~）内容与高置信度图形行（盒绘框线、ASCII 连接线），
    /// 避免 TTS 念出代码和图表噪音。未闭合的围栏视为持续到文末（EOF 即闭合）。
    private static func removingNonReadableBlocks(from sourceText: String) -> ReadAloudPreparedText {
        let normalized = sourceText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var removed = Array(repeating: false, count: lines.count)
        var removedCount = 0
        var inCodeFence = false
        var index = 0

        while index < lines.count {
            if isCodeFenceLine(lines[index]) {
                removed[index] = true
                removedCount += 1
                inCodeFence.toggle()
                index += 1
                continue
            }
            if inCodeFence {
                removed[index] = true
                removedCount += 1
                index += 1
                continue
            }
            if isDiagramLine(lines[index]) {
                removed[index] = true
                removedCount += 1
            }
            index += 1
        }

        let retained = lines.enumerated().compactMap { offset, line in
            removed[offset] ? nil : line
        }
        return ReadAloudPreparedText(
            text: retained.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            removedTableBlocks: 0,
            removedNonReadableBlocks: removedCount
        )
    }

    /// 行首（允许前导空白）至少 3 个连续反引号或波浪号即视为围栏行。
    private static func isCodeFenceLine(_ line: String) -> Bool {
        let leading = line.trimmingCharacters(in: .whitespaces)
        for marker: Character in ["`", "~"] {
            var count = 0
            for character in leading {
                if character == marker {
                    count += 1
                } else {
                    break
                }
            }
            if count >= 3 { return true }
        }
        return false
    }

    private static let boxDrawingScalars: Set<Unicode.Scalar> = {
        var set = Set<Unicode.Scalar>()
        for value in 0x2500...0x257F {
            if let scalar = Unicode.Scalar(value) { set.insert(scalar) }
        }
        for value in 0x2580...0x259F {
            if let scalar = Unicode.Scalar(value) { set.insert(scalar) }
        }
        return set
    }()

    private static let asciiConnectorCharacters: Set<Character> = {
        Set("-+=|:*<>^v/\\#".map { $0 })
    }()

    /// 高置信度图形行：整行剔除空白与盒绘字符后无剩余内容（纯框线），
    /// 或非空白字符全部属于连接符集合且不少于 3 个（ASCII 图形/分隔线）。
    /// 含文字的行走文本处理，不删除。
    private static func isDiagramLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }

        var boxRemainder = ""
        for character in trimmed {
            let scalar = character.unicodeScalars.first
            let isBox = scalar.map { boxDrawingScalars.contains($0) } ?? false
            if !isBox && !character.isWhitespace {
                boxRemainder.append(character)
            }
        }
        if boxRemainder.isEmpty { return true }

        let nonWhitespace = trimmed.filter { !$0.isWhitespace }
        if nonWhitespace.count >= 3,
           nonWhitespace.allSatisfy({ asciiConnectorCharacters.contains($0) }) {
            return true
        }
        return false
    }

    private static func containsHTMLTable(_ html: String) -> Bool {
        html.range(of: #"<\s*table\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func removingHTMLTables(from html: String) -> ReadAloudPreparedText {
        guard let tableRegex = try? NSRegularExpression(
            pattern: #"(?is)<\s*table\b[^>]*>.*?<\s*/\s*table\s*>"#
        ) else {
            return ReadAloudPreparedText(text: "", removedTableBlocks: 0)
        }
        let source = html as NSString
        let matches = tableRegex.matches(in: html, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else {
            return ReadAloudPreparedText(text: "", removedTableBlocks: 0)
        }

        let withoutTables = tableRegex.stringByReplacingMatches(
            in: html,
            range: NSRange(location: 0, length: source.length),
            withTemplate: "\n"
        )
        let converted = HTMLListPlainTextConverter.convert(withoutTables)
            ?? genericPlainText(fromHTML: withoutTables)
        let plainResult = removingPlainTextTables(from: converted)
        return ReadAloudPreparedText(
            text: plainResult.text,
            removedTableBlocks: matches.count + plainResult.removedTableBlocks
        )
    }

    private static func genericPlainText(fromHTML html: String) -> String {
        var text = html
        let blockPatterns = [
            #"(?i)<\s*br\s*/?\s*>"#,
            #"(?i)<\s*/\s*(?:p|div|h[1-6]|li|section|article)\s*>"#
        ]
        for pattern in blockPatterns {
            text = text.replacingOccurrences(of: pattern, with: "\n", options: .regularExpression)
        }
        text = text.replacingOccurrences(
            of: #"(?is)<\s*(?:script|style)\b[^>]*>.*?<\s*/\s*(?:script|style)\s*>"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: "", options: .regularExpression)
        text = decodeCommonHTMLEntities(text)

        let lines = text.components(separatedBy: .newlines).map {
            $0.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        var retained: [String] = []
        for line in lines {
            if line.isEmpty { continue }
            retained.append(line)
        }
        return retained.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeCommonHTMLEntities(_ text: String) -> String {
        var result = text
        let replacements = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (entity, value) in replacements {
            result = result.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return result
    }
}

/// 将一个长文本按本地安全段顺序请求，向上层暴露为一条连续 PCM 流。
struct SegmentedTTSClient: TTSClient {
    let base: any TTSClient
    let segments: [String]

    func stream(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        let preparedSegments = segments.isEmpty ? ReadAloudTextPreparation.segments(for: text) : segments
        guard !preparedSegments.isEmpty else { throw TTSClientError.emptyText }

        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    for segment in preparedSegments {
                        try Task.checkCancellation()
                        let stream = try await base.stream(text: segment)
                        for try await chunk in stream {
                            try Task.checkCancellation()
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}
