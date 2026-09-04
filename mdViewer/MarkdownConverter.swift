import Foundation

enum MarkdownConverter {
    static func html(from markdown: String) -> String {
        let body = render(markdown)
        let css = Self.css()
        let hasMermaid = body.contains("<div class=\"mermaid\">")
        let hasCode = body.contains("<pre><code") || body.contains("<pre data-lang")
        let scripts = Self.scripts(hasMermaid: hasMermaid, hasCode: hasCode)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        </head>
        <body>\(body)</body>
        \(scripts)
        </html>
        """
    }
    
    private static func render(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var result: [String] = []
        var i = 0
        var inCodeBlock = false
        var codeBuffer: [String] = []
        
        while i < lines.count {
            let rawLine = lines[i]
            
            if rawLine.hasPrefix("```") {
                if inCodeBlock {
                    let code = codeBuffer.dropFirst().joined(separator: "\n")
                    let language = fenceLanguage(codeBuffer.first ?? "")
                    if language == "mermaid" {
                        result.append("<div class=\"mermaid\">\(code)</div>")
                    } else {
                        result.append(codeBlockHTML(code: code, language: language))
                    }
                    codeBuffer = []
                    inCodeBlock = false
                } else {
                    codeBuffer = [rawLine]
                    inCodeBlock = true
                }
                i += 1
                continue
            }
            
            if inCodeBlock {
                codeBuffer.append(escapeHtml(rawLine))
                i += 1
                continue
            }
            
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty {
                result.append("")
                i += 1
                continue
            }
            
            if line == "---" || line == "***" || line == "___" {
                result.append("<hr>")
                i += 1
                continue
            }
            
            if i + 1 < lines.count,
               let setext = parseSetextHeader(current: line, next: lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                result.append(setext)
                i += 2
                continue
            }
            
            if let header = parseHeader(line) {
                result.append(header)
                i += 1
                continue
            }
            
            if line.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let qLine = lines[i]
                    if qLine.hasPrefix(">") {
                        let content = String(qLine.dropFirst()).trimmingCharacters(in: .whitespaces)
                        quoteLines.append(content)
                        i += 1
                    } else if qLine.trimmingCharacters(in: .whitespaces).isEmpty {
                        i += 1
                        continue
                    } else {
                        break
                    }
                }
                let content = quoteLines.map { inlineRender($0) }.joined(separator: " ")
                result.append("<blockquote><p>\(content)</p></blockquote>")
                continue
            }
            
            if itemInfo(for: rawLine) != nil {
                let list = parseListBlock(lines: lines, startIndex: i, indent: indentWidth(of: rawLine))
                result.append(list.html)
                i = list.nextIndex
                continue
            }
            
            if line.contains("|"),
               let table = parseTable(lines: lines, startIndex: i) {
                result.append(table.html)
                i = table.nextIndex
                continue
            }
            
            result.append("<p>\(inlineRender(line))</p>")
            i += 1
        }
        
        if inCodeBlock {
            let code = codeBuffer.dropFirst().joined(separator: "\n")
            let language = fenceLanguage(codeBuffer.first ?? "")
            if language == "mermaid" {
                result.append("<div class=\"mermaid\">\(code)</div>")
            } else {
                result.append(codeBlockHTML(code: code, language: language))
            }
        }

        return result.joined(separator: "\n")
    }

    private static func codeBlockHTML(code: String, language: String) -> String {
        guard !language.isEmpty else {
            return "<pre><code>\(code)</code></pre>"
        }
        let escapedLanguage = escapeHtml(language)
        return "<pre data-lang=\"\(escapedLanguage)\"><code class=\"language-\(escapedLanguage)\">\(code)</code></pre>"
    }

    private static func fenceLanguage(_ openingFence: String) -> String {
        let info = String(openingFence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let name = info.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first
        return name.map { $0.lowercased() } ?? ""
    }

    private struct ListItemInfo {
        let indent: Int
        let ordered: Bool
        let content: String
    }

    private static let listItemRegex = try! NSRegularExpression(pattern: "^[ \\t]*([-*+]|\\d{1,9}[.)])[ \\t]+(.*)$")

    private static func itemInfo(for rawLine: String) -> ListItemInfo? {
        let range = NSRange(rawLine.startIndex..., in: rawLine)
        guard let match = listItemRegex.firstMatch(in: rawLine, range: range),
              match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound,
              let markerRange = Range(match.range(at: 1), in: rawLine),
              let contentRange = Range(match.range(at: 2), in: rawLine) else {
            return nil
        }
        let marker = String(rawLine[markerRange])
        let ordered = marker.rangeOfCharacter(from: .decimalDigits) != nil
        return ListItemInfo(
            indent: indentWidth(of: rawLine),
            ordered: ordered,
            content: String(rawLine[contentRange])
        )
    }

    private static func indentWidth(of line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " {
                width += 1
            } else if character == "\t" {
                width += 4
            } else {
                break
            }
        }
        return width
    }

    private static func parseListBlock(lines: [String], startIndex: Int, indent: Int) -> (html: String, nextIndex: Int) {
        guard let first = itemInfo(for: lines[startIndex]) else {
            return (html: "", nextIndex: startIndex)
        }
        let ordered = first.ordered
        var itemContents: [String] = []
        var i = startIndex

        while i < lines.count {
            let rawLine = lines[i]

            if rawLine.trimmingCharacters(in: .whitespaces).isEmpty {
                var j = i
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    j += 1
                }
                if j < lines.count, let next = itemInfo(for: lines[j]), next.indent >= indent {
                    i = j
                    continue
                }
                break
            }

            guard let info = itemInfo(for: rawLine) else {
                if let last = itemContents.indices.last, indentWidth(of: rawLine) > indent {
                    itemContents[last] += " " + inlineRender(rawLine.trimmingCharacters(in: .whitespaces))
                    i += 1
                    continue
                }
                break
            }

            if info.indent < indent || (info.indent == indent && info.ordered != ordered) {
                break
            }

            if info.indent > indent, !itemContents.isEmpty {
                let nested = parseListBlock(lines: lines, startIndex: i, indent: info.indent)
                itemContents[itemContents.count - 1] += nested.html
                i = nested.nextIndex
                continue
            }

            itemContents.append(renderListItem(info.content, lineIndex: i))
            i += 1
        }

        let tag = ordered ? "ol" : "ul"
        let html = "<\(tag)>" + itemContents.map { "<li>\($0)</li>" }.joined() + "</\(tag)>"
        return (html: html, nextIndex: i > startIndex ? i : startIndex + 1)
    }
    
    private static func parseHeader(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let prefix = line.prefix(while: { $0 == "#" })
        let level = prefix.count
        guard level >= 1 && level <= 6 else { return nil }
        let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        return "<h\(level)>\(inlineRender(text))</h\(level)>"
    }
    
    private static func parseSetextHeader(current: String, next: String) -> String? {
        guard !current.isEmpty, !next.isEmpty else { return nil }
        if next.allSatisfy({ $0 == "=" }) {
            return "<h1>\(inlineRender(current))</h1>"
        } else if next.allSatisfy({ $0 == "-" }) {
            return "<h2>\(inlineRender(current))</h2>"
        }
        return nil
    }
    
    private static func renderListItem(_ item: String, lineIndex: Int) -> String {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[ ]") {
            let task = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return "<input type=\"checkbox\" data-line=\"\(lineIndex)\"> \(inlineRender(task))"
        } else if trimmed.lowercased().hasPrefix("[x]") {
            let task = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return "<input type=\"checkbox\" checked data-line=\"\(lineIndex)\"> \(inlineRender(task))"
        }
        return inlineRender(item)
    }
    
    private static func inlineRender(_ text: String) -> String {
        var result = escapeHtml(text)

        result = result.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: "__([^_]+)__", with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*([^*]+)\\*", with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: "_([^_]+)_", with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: "~~([^~]+)~~", with: "<del>$1</del>", options: .regularExpression)
        result = renderImages(result)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        result = autolink(result)

        if result.hasSuffix("  ") {
            result = String(result.dropLast(2)) + "<br>"
        }

        return result
    }

    private static func renderImages(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)") else {
            return text
        }
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var result = ""
        var cursor = 0

        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match, match.range.location >= cursor else { return }
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let alt = ns.substring(with: match.range(at: 1))
            let source = resolveImageSource(ns.substring(with: match.range(at: 2)))
            result += "<img src=\"\(source)\" alt=\"\(alt)\">"
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func resolveImageSource(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") || lower.hasPrefix("mdresource://") {
            return trimmed
        }
        let relative = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
        return "mdresource:///\(encoded)"
    }

    private static func autolink(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?<!href=\")(?<!src=\")(?<!>)https?://[^\\s<]+") else {
            return text
        }
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var result = ""
        var cursor = 0

        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match, match.range.location >= cursor else { return }
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            var url = ns.substring(with: match.range)
            while let last = url.last, ".,;:!?".contains(last) {
                url.removeLast()
            }
            while url.hasSuffix(")") {
                let opens = url.filter { $0 == "(" }.count
                let closes = url.filter { $0 == ")" }.count
                guard opens < closes else { break }
                url.removeLast()
            }
            result += "<a href=\"\(url)\">\(url)</a>"
            cursor = match.range.location + url.utf16.count
        }

        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }
    
    private struct TableResult {
        let html: String
        let nextIndex: Int
    }
    
    private static func parseTable(lines: [String], startIndex: Int) -> TableResult? {
        guard startIndex + 1 < lines.count else { return nil }
        
        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        
        guard headerLine.contains("|"), separatorLine.contains("|") else { return nil }
        
        let separatorChars = CharacterSet(charactersIn: "|-: ")
        guard separatorLine.rangeOfCharacter(from: separatorChars.inverted) == nil,
              separatorLine.contains("-") else { return nil }
        
        let headerCells = parseTableCells(headerLine)
        let alignments = parseTableAlignments(separatorLine)
        guard headerCells.count == alignments.count, !headerCells.isEmpty else { return nil }
        
        var rows: [[String]] = []
        var i = startIndex + 2
        while i < lines.count {
            let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
            if rowLine.isEmpty { break }
            if !rowLine.contains("|") { break }
            let cells = parseTableCells(rowLine)
            guard cells.count == headerCells.count else { break }
            rows.append(cells)
            i += 1
        }
        
        var html = "<table><thead><tr>"
        for (index, cell) in headerCells.enumerated() {
            html += "<th\(alignmentAttr(alignments[index]))>\(inlineRender(cell))</th>"
        }
        html += "</tr></thead>"
        
        if !rows.isEmpty {
            html += "<tbody>"
            for row in rows {
                html += "<tr>"
                for (index, cell) in row.enumerated() {
                    html += "<td\(alignmentAttr(alignments[index]))>\(inlineRender(cell))</td>"
                }
                html += "</tr>"
            }
            html += "</tbody>"
        }
        
        html += "</table>"
        return TableResult(html: html, nextIndex: i)
    }
    
    private static func parseTableCells(_ line: String) -> [String] {
        var cells = line.components(separatedBy: "|")
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeFirst()
        }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeLast()
        }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    private static func parseTableAlignments(_ line: String) -> [String] {
        parseTableCells(line).map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":"), trimmed.hasSuffix(":") {
                return "center"
            } else if trimmed.hasSuffix(":") {
                return "right"
            } else if trimmed.hasPrefix(":") {
                return "left"
            }
            return ""
        }
    }
    
    private static func alignmentAttr(_ alignment: String) -> String {
        alignment.isEmpty ? "" : " style=\"text-align: \(alignment);\""
    }
    
    private static func escapeHtml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    
    private static func css() -> String {
        guard let url = Bundle.main.url(forResource: "markdown", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return highlightCss() + css
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

    private static func scripts(hasMermaid: Bool, hasCode: Bool) -> String {
        var scripts = "<script>\(script())</script>"
        if hasCode, let library = highlightLibrary() {
            scripts += "<script>\(library)</script>"
            scripts += "<script>\(highlightInitScript())</script>"
        }
        if hasMermaid {
            if let library = mermaidLibrary() {
                scripts += "<script>\(library)</script>"
                scripts += "<script>\(mermaidInitScript())</script>"
            } else {
                scripts += "<script>window.__contentDone = true;</script>"
            }
        }
        return scripts
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

    private static func mermaidLibrary() -> String? {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return js
    }

    private static func mermaidInitScript() -> String {
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
            if (!window.mermaid || !blocks.length) { complete(); return; }
            var dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
            try {
                mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default' });
                mermaid.run({ nodes: blocks }).then(complete).catch(complete);
            } catch (e) {
                complete();
            }
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

                var button = document.createElement('button');
                button.className = 'copy-code-button';
                button.textContent = 'Copy';
                button.setAttribute('aria-label', 'Copy code');
                button.addEventListener('click', function() {
                    var text = code.textContent || '';
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copyCode) {
                        window.webkit.messageHandlers.copyCode.postMessage(text);
                    }
                    button.textContent = 'Copied';
                    setTimeout(function() { button.textContent = 'Copy'; }, 1500);
                });

                pre.style.position = 'relative';
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

        window.__contentDone = true;
        """
    }
}
