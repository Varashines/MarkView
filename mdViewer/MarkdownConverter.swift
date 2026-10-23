import Foundation
import Markdown
import UniformTypeIdentifiers

struct MarkdownHeading: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let level: Int
}

private struct MathItem {
    let latex: String
    let isBlock: Bool
}

private struct HeadingSlugger {
    private var counts: [String: Int] = [:]

    mutating func id(for text: String) -> String {
        var slug = text.lowercased()
        slug = slug.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "section" }

        if let count = counts[slug] {
            counts[slug] = count + 1
            return "\(slug)-\(count)"
        }
        counts[slug] = 1
        return slug
    }
}

private func stripMathTokens(_ text: String) -> String {
    text.replacingOccurrences(
        of: "\u{F0000}[BI]\\d+\u{F0001}",
        with: "",
        options: .regularExpression
    )
}

private func escapeHTMLEntities(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private func resolveImageSource(_ source: String) -> String {
    let trimmed = source.trimmingCharacters(in: .whitespaces)
    let lower = trimmed.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") || lower.hasPrefix("mdresource://") {
        return trimmed
    }
    let relative = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
    let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
    return "mdresource:///\(encoded)"
}

private func exportedImageSource(_ source: String, baseURL: URL?) -> String {
    let trimmed = source.trimmingCharacters(in: .whitespaces)
    let lower = trimmed.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") {
        return trimmed
    }
    guard let baseURL else { return trimmed }

    let relative = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
    let decoded = relative.removingPercentEncoding ?? relative
    let fileURL = baseURL.appendingPathComponent(decoded)

    if let data = try? Data(contentsOf: fileURL), data.count <= 8_000_000 {
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
    return fileURL.absoluteString
}

private func plainText(from markup: Markup) -> String {
    if let text = markup as? Text { return text.string }
    if let code = markup as? InlineCode { return code.code }
    if markup is SoftBreak || markup is LineBreak { return " " }
    return markup.children.map(plainText).joined()
}

private func linkifyText(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s<>]+") else {
        return escapeHTMLEntities(text)
    }
    let ns = text as NSString
    let fullRange = NSRange(location: 0, length: ns.length)
    var result = ""
    var cursor = 0

    regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
        guard let match, match.range.location >= cursor else { return }
        if match.range.location > cursor {
            result += escapeHTMLEntities(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
        }

        var url = ns.substring(with: match.range)
        var trailing = ""
        while let last = url.last, ".,;:!?".contains(last) {
            trailing = String(last) + trailing
            url.removeLast()
        }
        while url.hasSuffix(")") {
            let opens = url.filter { $0 == "(" }.count
            let closes = url.filter { $0 == ")" }.count
            guard opens < closes else { break }
            trailing = ")" + trailing
            url.removeLast()
        }

        result += "<a href=\"\(escapeHTMLEntities(url))\">\(escapeHTMLEntities(url))</a>"
        result += escapeHTMLEntities(trailing)
        cursor = match.range.location + match.range.length
    }

    if cursor < ns.length {
        result += escapeHTMLEntities(ns.substring(from: cursor))
    }
    return result
}

enum MarkdownConverter {
    static func html(from markdown: String) -> String {
        buildHTML(from: markdown, baseURL: nil, exportMode: false)
    }

    static func exportedHTML(from markdown: String, baseURL: URL?) -> String {
        buildHTML(from: markdown, baseURL: baseURL, exportMode: true)
    }

    private static func buildHTML(from markdown: String, baseURL: URL?, exportMode: Bool) -> String {
        let source = strippingFrontMatter(from: markdown)
        let (processed, mathItems) = extractMath(from: source)
        let document = Document(parsing: processed, options: .disableSmartOpts)
        var renderer = HTMLRenderer()
        renderer.exportMode = exportMode
        renderer.imageBaseURL = baseURL
        let rendered = renderer.render(document)
        let body = replacingMathTokens(in: rendered, items: mathItems)

        let hasMermaid = body.contains("<div class=\"mermaid\">")
        let hasCode = body.contains("<pre")
        let hasMath = !mathItems.isEmpty
        let scripts = Self.scripts(hasMermaid: hasMermaid, hasCode: hasCode, hasMath: hasMath)
        let styleContent: String
        if hasMath {
            styleContent = css() + (exportMode ? exportedKatexCss() : katexCss())
        } else {
            styleContent = css()
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(styleContent)</style>
        </head>
        <body>\(body)</body>
        \(scripts)
        </html>
        """
    }

    static func outline(from markdown: String) -> [MarkdownHeading] {
        let source = strippingFrontMatter(from: markdown)
        let (processed, _) = extractMath(from: source)
        let document = Document(parsing: processed, options: .disableSmartOpts)
        var slugger = HeadingSlugger()
        var headings: [MarkdownHeading] = []

        func walk(_ markup: Markup) {
            if let heading = markup as? Heading {
                let rawTitle = plainText(from: heading).trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = stripMathTokens(rawTitle)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                headings.append(MarkdownHeading(
                    id: slugger.id(for: displayTitle),
                    title: displayTitle.isEmpty ? "Section" : displayTitle,
                    level: heading.level
                ))
            }
            for child in markup.children {
                walk(child)
            }
        }

        walk(document)
        return headings
    }

    private static func strippingFrontMatter(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first == "---" || first == "+++" else {
            return markdown
        }
        let closing = first == "---" ? ["---", "..."] : ["+++"]
        guard let end = lines.dropFirst().firstIndex(where: {
            closing.contains($0.trimmingCharacters(in: .whitespaces))
        }) else {
            return markdown
        }
        let inner = lines[1..<end]
        let looksLikeFrontMatter = inner.contains {
            first == "---" ? $0.contains(":") : $0.contains("=")
        }
        guard looksLikeFrontMatter else { return markdown }
        var result = lines
        for index in 0...end {
            result[index] = ""
        }
        return result.joined(separator: "\n")
    }

    private static func mathToken(index: Int, isBlock: Bool) -> String {
        "\u{F0000}\(isBlock ? "B" : "I")\(index)\u{F0001}"
    }

    private static func extractMath(from markdown: String) -> (String, [MathItem]) {
        var items: [MathItem] = []
        var output: [String] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var fence: (character: Character, length: Int)?

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let currentFence = fence {
                output.append(line)
                if isClosingFence(trimmed, character: currentFence.character, length: currentFence.length) {
                    fence = nil
                }
                i += 1
                continue
            }

            if let opening = fenceOpening(trimmed) {
                fence = opening
                output.append(line)
                i += 1
                continue
            }

            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                output.append(line)
                i += 1
                continue
            }

            if trimmed.hasPrefix("$$"), !trimmed.hasPrefix("\\$") {
                if trimmed.count > 4, trimmed.hasSuffix("$$") {
                    let latex = String(trimmed.dropFirst(2).dropLast(2))
                    let index = items.count
                    items.append(MathItem(latex: latex, isBlock: true))
                    output.append(mathToken(index: index, isBlock: true))
                    i += 1
                    continue
                }

                var collected: [String] = []
                let firstContent = String(trimmed.dropFirst(2))
                if !firstContent.isEmpty {
                    collected.append(firstContent)
                }
                var j = i + 1
                var closed = false
                while j < lines.count {
                    let candidate = lines[j]
                    let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                    if candidateTrimmed.hasSuffix("$$"), !candidateTrimmed.hasSuffix("\\$$") {
                        let prefix = String(candidateTrimmed.dropLast(2))
                        if !prefix.isEmpty {
                            collected.append(prefix)
                        }
                        closed = true
                        j += 1
                        break
                    }
                    collected.append(candidate)
                    j += 1
                }
                if closed {
                    let index = items.count
                    items.append(MathItem(latex: collected.joined(separator: "\n"), isBlock: true))
                    output.append(mathToken(index: index, isBlock: true))
                    if j - i > 1 {
                        output.append(contentsOf: Array(repeating: "", count: j - i - 1))
                    }
                    i = j
                    continue
                }
            }

            output.append(extractInlineMath(from: line, items: &items))
            i += 1
        }

        return (output.joined(separator: "\n"), items)
    }

    private static func extractInlineMath(from line: String, items: inout [MathItem]) -> String {
        var result = ""
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if character == "\\" {
                let next = line.index(after: index)
                result.append(character)
                if next < line.endIndex {
                    result.append(line[next])
                    index = line.index(after: next)
                } else {
                    index = next
                }
                continue
            }

            if character == "`" {
                let runEnd = line[index...].prefix(while: { $0 == "`" }).endIndex
                let runLength = line.distance(from: index, to: runEnd)
                var search = runEnd
                var closed = false
                while search < line.endIndex {
                    if line[search] == "`" {
                        let closeEnd = line[search...].prefix(while: { $0 == "`" }).endIndex
                        let closeLength = line.distance(from: search, to: closeEnd)
                        if closeLength == runLength {
                            result += String(line[index..<closeEnd])
                            index = closeEnd
                            closed = true
                            break
                        }
                        search = closeEnd
                    } else {
                        search = line.index(after: search)
                    }
                }
                if !closed {
                    result += String(line[index...])
                    index = line.endIndex
                }
                continue
            }

            if character == "$" {
                let delimiter = line[index...].prefix(while: { $0 == "$" }).count
                let delimiterLength = min(delimiter, 2)
                let contentStart = line.index(index, offsetBy: delimiterLength)
                if contentStart < line.endIndex,
                   !line[contentStart].isWhitespace {
                    var closing: String.Index?
                    var cursor = contentStart
                    while cursor < line.endIndex {
                        if line[cursor] == "\\" {
                            cursor = line.index(after: cursor)
                            if cursor < line.endIndex {
                                cursor = line.index(after: cursor)
                            }
                            continue
                        }
                        if line[cursor] == "$" {
                            let run = line[cursor...].prefix(while: { $0 == "$" }).count
                            if run >= delimiterLength,
                               cursor > contentStart,
                               !line[line.index(before: cursor)].isWhitespace {
                                closing = cursor
                                break
                            }
                        }
                        cursor = line.index(after: cursor)
                    }
                    if let closing {
                        let latex = String(line[contentStart..<closing])
                        let itemIndex = items.count
                        items.append(MathItem(latex: latex, isBlock: false))
                        result += mathToken(index: itemIndex, isBlock: false)
                        index = line.index(closing, offsetBy: delimiterLength)
                        continue
                    }
                }
            }

            result.append(character)
            index = line.index(after: index)
        }

        return result
    }

    private static func fenceOpening(_ trimmed: String) -> (character: Character, length: Int)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix(while: { $0 == first })
        guard run.count >= 3 else { return nil }
        return (first, run.count)
    }

    private static func isClosingFence(_ trimmed: String, character: Character, length: Int) -> Bool {
        guard let first = trimmed.first, first == character else { return false }
        let run = trimmed.prefix(while: { $0 == character })
        guard run.count >= length else { return false }
        return trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func replacingMathTokens(in html: String, items: [MathItem]) -> String {
        var result = html
        for (index, item) in items.enumerated() {
            let token = mathToken(index: index, isBlock: item.isBlock)
            let escaped = escapeHTMLEntities(item.latex)
            if item.isBlock {
                result = result.replacingOccurrences(
                    of: "<p>\(token)</p>",
                    with: "<div class=\"math-block\">\(escaped)</div>"
                )
            }
            result = result.replacingOccurrences(
                of: token,
                with: "<span class=\"math-inline\">\(escaped)</span>"
            )
        }
        return result
    }

    private static func css() -> String {
        guard let url = Bundle.main.url(forResource: "markdown", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return highlightCss() + css
    }

    private static func katexCSSText() -> String {
        guard let url = Bundle.main.url(forResource: "katex.min", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return css
    }

    private static func katexCss() -> String {
        katexCSSText().replacingOccurrences(of: "url(fonts/", with: "url(appresource:///fonts/")
    }

    private static func exportedKatexCss() -> String {
        var css = katexCSSText()
        guard let regex = try? NSRegularExpression(pattern: "url\\(fonts/([^)]+)\\)") else {
            return css
        }

        let matches = regex.matches(in: css, range: NSRange(location: 0, length: (css as NSString).length))
        for match in matches.reversed() {
            let fileName = (css as NSString).substring(with: match.range(at: 1))
            let file = fileName as NSString
            guard let url = Bundle.main.url(
                forResource: file.deletingPathExtension,
                withExtension: file.pathExtension,
                subdirectory: "fonts"
            ), let data = try? Data(contentsOf: url) else {
                continue
            }
            let mime = fontMIME(for: file.pathExtension)
            let replacement = "url(data:\(mime);base64,\(data.base64EncodedString()))"
            css = (css as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return css
    }

    private static func fontMIME(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "eot": return "application/vnd.ms-fontobject"
        default: return "application/octet-stream"
        }
    }

    private static func highlightCss() -> String {
        guard let lightURL = Bundle.main.url(forResource: "github.min", withExtension: "css"),
              let light = try? String(contentsOf: lightURL, encoding: .utf8) else {
            return ""
        }
        var css = light
        if let darkURL = Bundle.main.url(forResource: "github-dark.min", withExtension: "css"),
           let dark = try? String(contentsOf: darkURL, encoding: .utf8) {
            css += "@media (prefers-color-scheme: dark){\(dark)}"
        }
        return css
    }

    private static func scripts(hasMermaid: Bool, hasCode: Bool, hasMath: Bool) -> String {
        var scripts = "<script>\(script())</script>"
        if hasCode, let library = highlightLibrary() {
            scripts += "<script>\(library)</script>"
            scripts += "<script>\(highlightInitScript())</script>"
        }
        if hasMath {
            if let library = katexLibrary() {
                scripts += "<script>\(library)</script>"
                scripts += "<script>\(mathInitScript())</script>"
            } else {
                scripts += "<script>window.__contentDone = true;</script>"
            }
        }
        if hasMermaid {
            if let library = peleLibrary() {
                scripts += "<script>\(library)</script>"
                scripts += "<script>\(peleInitScript())</script>"
            } else {
                scripts += "<script>window.__contentDone = true;</script>"
            }
        }
        return scripts
    }

    private static func katexLibrary() -> String? {
        guard let url = Bundle.main.url(forResource: "katex.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return js
    }

    private static func mathInitScript() -> String {
        """
        (function() {
            var blocks = document.querySelectorAll('.math-inline, .math-block');
            var complete = function() {
                window.__contentDone = true;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contentDone) {
                    window.webkit.messageHandlers.contentDone.postMessage('');
                }
            };
            if (!window.katex || !blocks.length) { complete(); return; }
            blocks.forEach(function(el) {
                try {
                    katex.render(el.textContent, el, {
                        displayMode: el.classList.contains('math-block'),
                        throwOnError: false
                    });
                } catch (e) {}
            });
            complete();
        })();
        """
    }

    private static func highlightLibrary() -> String? {
        guard let url = Bundle.main.url(forResource: "highlight.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return js
    }

    private static func highlightInitScript() -> String {
        """
        (function() {
            var blocks = document.querySelectorAll('pre code');
            if (!blocks.length || !window.hljs) { return; }
            blocks.forEach(function(el) {
                if (el.getAttribute('data-highlighted')) { return; }
                try { hljs.highlightElement(el); } catch (e) {}
            });
            window.__contentDone = true;
        })();
        """
    }

    private static func peleLibrary() -> String? {
        guard let url = Bundle.main.url(forResource: "pele.global", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return js
    }

    private static func peleInitScript() -> String {
        """
        window.__contentDone = false;
        (function() {
            var blocks = document.querySelectorAll('div.mermaid');
            var complete = function() {
                window.__contentDone = true;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contentDone) {
                    window.webkit.messageHandlers.contentDone.postMessage('');
                }
            };
            if (!window.pele || !blocks.length) { complete(); return; }
            blocks.forEach(function(el) {
                var source = el.textContent;
                try {
                    if (el.clientWidth > 0) {
                        pele.mount(el, source, { zoom: 'auto' });
                    } else {
                        el.innerHTML = pele.render(source, { responsive: true }).svg;
                    }
                } catch (e) {
                    el.textContent = source;
                }
            });
            complete();
        })();
        """
    }

    private static func script() -> String {
        """
        window.__contentDone = false;
        document.addEventListener('DOMContentLoaded', function() {
            document.querySelectorAll('pre').forEach(function(pre) {
                var code = pre.querySelector('code');
                if (!code) return;

                var language = pre.getAttribute('data-lang') || '';
                if (!language) {
                    var match = (code.className || '').match(/(?:^|\\s)language-([^\\s]+)/);
                    if (match) { language = match[1]; }
                }

                function idleText() {
                    return language ? language.toUpperCase() : 'Copy';
                }

                var button = document.createElement('button');
                button.className = 'copy-code-button';
                button.textContent = idleText();
                button.setAttribute('aria-label', 'Copy code');
                if (language) { button.title = 'Copy ' + language + ' code'; }

                button.addEventListener('click', function() {
                    var text = code.textContent || '';
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copyCode) {
                        window.webkit.messageHandlers.copyCode.postMessage(text);
                    }
                    button.textContent = 'Copied';
                    button.classList.add('copied');
                    setTimeout(function() {
                        button.classList.remove('copied');
                        button.textContent = pre.matches(':hover') ? 'Copy' : idleText();
                    }, 1500);
                });

                pre.addEventListener('mouseenter', function() {
                    if (button.textContent !== 'Copied') { button.textContent = 'Copy'; }
                });

                pre.addEventListener('mouseleave', function() {
                    if (button.textContent !== 'Copied') { button.textContent = idleText(); }
                });

                pre.appendChild(button);
            });
        });

        document.addEventListener('change', function(e) {
            if (e.target && e.target.type === 'checkbox' && e.target.hasAttribute('data-line')) {
                var lineIndex = parseInt(e.target.getAttribute('data-line'));
                var checked = e.target.checked;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.toggleTask) {
                    window.webkit.messageHandlers.toggleTask.postMessage({l: lineIndex, c: checked});
                }
            }
        });

        var scrollSyncScheduled = false;
        window.addEventListener('scroll', function() {
            if (scrollSyncScheduled) { return; }
            scrollSyncScheduled = true;
            setTimeout(function() {
                scrollSyncScheduled = false;
                var d = document.documentElement;
                var max = d.scrollHeight - window.innerHeight;
                var fraction = max > 0 ? Math.min(Math.max(window.scrollY / max, 0), 1) : 0;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollSync) {
                    window.webkit.messageHandlers.scrollSync.postMessage(fraction);
                }
            }, 50);
        }, { passive: true });

        window.__contentDone = true;
        """
    }
}

private struct HTMLRenderer {
    var exportMode = false
    var imageBaseURL: URL?
    private var slugger = HeadingSlugger()
    private var tableAlignments: [Table.ColumnAlignment?] = []
    private var tableColumn = 0
    private var inTableHead = false

    mutating func render(_ markup: Markup) -> String {
        render(markup, inLink: false)
    }

    private mutating func render(_ markup: Markup, inLink: Bool) -> String {
        switch markup {
        case let document as Document:
            return renderChildren(document, inLink: inLink)
        case let paragraph as Paragraph:
            return "<p>\(renderChildren(paragraph, inLink: inLink))</p>\n"
        case let heading as Heading:
            let title = stripMathTokens(plainText(from: heading))
            let id = slugger.id(for: title)
            return "<h\(heading.level) id=\"\(id)\">\(renderChildren(heading, inLink: inLink))</h\(heading.level)>\n"
        case let blockQuote as BlockQuote:
            return "<blockquote>\n\(renderChildren(blockQuote, inLink: inLink))</blockquote>\n"
        case let codeBlock as CodeBlock:
            let language = (codeBlock.language ?? "").trimmingCharacters(in: .whitespaces)
            if language.lowercased() == "mermaid" {
                return "<div class=\"mermaid\">\(escapeHTMLEntities(codeBlock.code))</div>\n"
            }
            var attributes = ""
            if !language.isEmpty {
                let escapedLanguage = escapeHTMLEntities(language)
                attributes += " data-lang=\"\(escapedLanguage)\""
            }
            let codeAttributes = language.isEmpty ? "" : " class=\"language-\(escapeHTMLEntities(language))\""
            return "<pre\(attributes)><code\(codeAttributes)>\(escapeHTMLEntities(codeBlock.code))</code></pre>\n"
        case let htmlBlock as HTMLBlock:
            return "<p>\(escapeHTMLEntities(htmlBlock.rawHTML))</p>\n"
        case is ThematicBreak:
            return "<hr>\n"
        case let list as UnorderedList:
            return "<ul>\n\(renderChildren(list, inLink: inLink))</ul>\n"
        case let list as OrderedList:
            let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
            return "<ol\(start)>\n\(renderChildren(list, inLink: inLink))</ol>\n"
        case let item as ListItem:
            var prefix = ""
            if let checkbox = item.checkbox {
                var attributes = ""
                if let line = item.range?.lowerBound.line {
                    attributes += " data-line=\"\(line - 1)\""
                }
                if checkbox == .checked {
                    attributes += " checked"
                }
                prefix = "<input type=\"checkbox\"\(attributes)> "
            }

            let children = Array(item.children)
            var content = ""
            for (index, child) in children.enumerated() {
                if !prefix.isEmpty, index == 0, let paragraph = child as? Paragraph {
                    content += renderChildren(paragraph, inLink: inLink)
                } else {
                    content += render(child, inLink: inLink)
                }
            }
            return "<li>\(prefix)\(content)</li>\n"
        case let table as Table:
            let previous = tableAlignments
            tableAlignments = table.columnAlignments
            let content = renderChildren(table, inLink: inLink)
            tableAlignments = previous
            return "<table>\n\(content)</table>\n"
        case let head as Table.Head:
            let previous = inTableHead
            inTableHead = true
            let content = renderChildren(head, inLink: inLink)
            inTableHead = previous
            return "<thead>\n<tr>\n\(content)</tr>\n</thead>\n"
        case let body as Table.Body:
            guard !body.isEmpty else { return "" }
            return "<tbody>\n\(renderChildren(body, inLink: inLink))</tbody>\n"
        case let row as Table.Row:
            tableColumn = 0
            return "<tr>\n\(renderChildren(row, inLink: inLink))</tr>\n"
        case let cell as Table.Cell:
            let tag = inTableHead ? "th" : "td"
            var attributes = ""
            if tableAlignments.indices.contains(tableColumn),
               let alignment = tableAlignments[tableColumn] {
                attributes += " style=\"text-align: \(alignment);\""
            }
            if cell.colspan > 1 {
                attributes += " colspan=\"\(cell.colspan)\""
            }
            if cell.rowspan > 1 {
                attributes += " rowspan=\"\(cell.rowspan)\""
            }
            tableColumn += 1
            return "<\(tag)\(attributes)>\(renderChildren(cell, inLink: inLink))</\(tag)>\n"
        case let text as Text:
            return inLink ? escapeHTMLEntities(text.string) : linkifyText(text.string)
        case let inlineCode as InlineCode:
            return "<code>\(escapeHTMLEntities(inlineCode.code))</code>"
        case let emphasis as Emphasis:
            return "<em>\(renderChildren(emphasis, inLink: inLink))</em>"
        case let strong as Strong:
            return "<strong>\(renderChildren(strong, inLink: inLink))</strong>"
        case let strikethrough as Strikethrough:
            return "<del>\(renderChildren(strikethrough, inLink: inLink))</del>"
        case let link as Link:
            var attributes = ""
            if let destination = link.destination, !destination.isEmpty {
                attributes += " href=\"\(escapeHTMLEntities(destination))\""
            }
            if let title = link.title, !title.isEmpty {
                attributes += " title=\"\(escapeHTMLEntities(title))\""
            }
            return "<a\(attributes)>\(renderChildren(link, inLink: true))</a>"
        case let image as Image:
            let rawSource = image.source ?? ""
            let source = exportMode
                ? exportedImageSource(rawSource, baseURL: imageBaseURL)
                : resolveImageSource(rawSource)
            var attributes = " src=\"\(escapeHTMLEntities(source))\" alt=\"\(escapeHTMLEntities(plainText(from: image)))\""
            if let title = image.title, !title.isEmpty {
                attributes += " title=\"\(escapeHTMLEntities(title))\""
            }
            return "<img\(attributes)>"
        case is SoftBreak:
            return "\n"
        case is LineBreak:
            return "<br>\n"
        case let inlineHTML as InlineHTML:
            return escapeHTMLEntities(inlineHTML.rawHTML)
        case let symbolLink as SymbolLink:
            return "<code>\(escapeHTMLEntities(symbolLink.destination ?? ""))</code>"
        default:
            return renderChildren(markup, inLink: inLink)
        }
    }

    private mutating func renderChildren(_ markup: Markup, inLink: Bool) -> String {
        markup.children.map { render($0, inLink: inLink) }.joined()
    }
}
