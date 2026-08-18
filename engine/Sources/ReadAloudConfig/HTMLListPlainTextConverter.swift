import Foundation

enum HTMLListPlainTextConverter {
    private enum ListKind {
        case ordered
        case unordered
    }

    private struct ListContext {
        let kind: ListKind
        var nextNumber: Int
    }

    static func convert(_ html: String) -> String? {
        guard html.range(of: #"<\s*li\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let tokenizer = try? NSRegularExpression(pattern: #"(?s)<[^>]+>|[^<]+"#) else {
            return nil
        }

        let source = html as NSString
        let matches = tokenizer.matches(
            in: html,
            range: NSRange(location: 0, length: source.length)
        )
        var output = ""
        var lists: [ListContext] = []

        for match in matches {
            let token = source.substring(with: match.range)
            if token.hasPrefix("<") {
                handleTag(token, output: &output, lists: &lists)
            } else {
                appendText(token, to: &output)
            }
        }

        let normalized = normalize(output)
        return normalized.isEmpty ? nil : normalized
    }

    private static func handleTag(
        _ rawTag: String,
        output: inout String,
        lists: inout [ListContext]
    ) {
        var body = rawTag.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.hasPrefix("!") && !body.hasPrefix("?") else { return }

        let isClosing = body.hasPrefix("/")
        if isClosing {
            body = body.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let tagName = body
            .split(whereSeparator: { $0.isWhitespace || $0 == "/" })
            .first?
            .lowercased() ?? ""

        switch (tagName, isClosing) {
        case ("ol", false):
            appendLineBreakIfNeeded(to: &output)
            lists.append(
                ListContext(
                    kind: .ordered,
                    nextNumber: integerAttribute("start", in: rawTag) ?? 1
                )
            )
        case ("ul", false):
            appendLineBreakIfNeeded(to: &output)
            lists.append(ListContext(kind: .unordered, nextNumber: 1))
        case ("ol", true), ("ul", true):
            if !lists.isEmpty {
                lists.removeLast()
            }
            appendLineBreakIfNeeded(to: &output)
        case ("li", false):
            appendLineBreakIfNeeded(to: &output)
            let indentation = String(repeating: "  ", count: max(0, lists.count - 1))
            let marker: String
            if lists.isEmpty {
                marker = "•"
            } else {
                let index = lists.count - 1
                switch lists[index].kind {
                case .ordered:
                    let itemNumber = integerAttribute("value", in: rawTag) ?? lists[index].nextNumber
                    marker = "\(itemNumber)."
                    lists[index].nextNumber = itemNumber + 1
                case .unordered:
                    marker = "•"
                }
            }
            output += "\(indentation)\(marker) "
        case ("li", true), ("br", false):
            appendLineBreakIfNeeded(to: &output)
        case ("p", true), ("div", true):
            appendLineBreakIfNeeded(to: &output)
        default:
            break
        }
    }

    private static func appendText(_ rawText: String, to output: inout String) {
        let decoded = decodeHTMLEntities(rawText)
        let hasLeadingWhitespace = decoded.first?.isWhitespace == true
        let hasTrailingWhitespace = decoded.last?.isWhitespace == true
        let words = decoded.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return }

        if hasLeadingWhitespace,
           let last = output.last,
           !last.isWhitespace {
            output.append(" ")
        }
        output += words.joined(separator: " ")
        if hasTrailingWhitespace {
            output.append(" ")
        }
    }

    private static func appendLineBreakIfNeeded(to output: inout String) {
        while output.last == " " || output.last == "\t" {
            output.removeLast()
        }
        guard !output.isEmpty, output.last != "\n" else { return }
        output.append("\n")
    }

    private static func integerAttribute(_ name: String, in tag: String) -> Int? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b"# + escapedName + #"\s*=\s*["']?(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let source = tag as NSString
        guard let match = regex.firstMatch(
            in: tag,
            range: NSRange(location: 0, length: source.length)
        ), match.numberOfRanges > 1 else {
            return nil
        }
        return Int(source.substring(with: match.range(at: 1)))
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"&(#x[0-9a-f]+|#\d+|[a-z]+);"#,
            options: .caseInsensitive
        ) else {
            return text
        }

        let source = text as NSString
        var result = text
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        for match in matches.reversed() {
            let entity = source.substring(with: match.range(at: 1))
            guard let replacement = decodedEntity(entity) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    private static func decodedEntity(_ entity: String) -> String? {
        switch entity.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39": return "'"
        case "nbsp": return " "
        default:
            let value: UInt32?
            if entity.lowercased().hasPrefix("#x") {
                value = UInt32(entity.dropFirst(2), radix: 16)
            } else if entity.hasPrefix("#") {
                value = UInt32(entity.dropFirst(), radix: 10)
            } else {
                value = nil
            }
            guard let value, let scalar = UnicodeScalar(value) else { return nil }
            return String(scalar)
        }
    }

    private static func normalize(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(
                    of: #"[ \t]+$"#,
                    with: "",
                    options: .regularExpression
                )
            }
        var normalizedLines: [String] = []
        for line in lines {
            if line.isEmpty, normalizedLines.last?.isEmpty == true {
                continue
            }
            normalizedLines.append(line)
        }
        while normalizedLines.first?.isEmpty == true {
            normalizedLines.removeFirst()
        }
        while normalizedLines.last?.isEmpty == true {
            normalizedLines.removeLast()
        }
        return normalizedLines.joined(separator: "\n")
    }
}
