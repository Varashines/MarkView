import Foundation

enum MarkdownConverter {
    static func html(from markdown: String) -> String {
        let body = render(markdown)
        let css = Self.css()
        let script = Self.script()
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        </head>
        <body>\(body)</body>
        <script>\(script)</script>
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
                    result.append("<pre><code>\(code)</code></pre>")
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
            
            if line.range(of: "^[-*+]\\s+", options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let lLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if lLine.range(of: "^[-*+]\\s+", options: .regularExpression) != nil,
                       let suffixRange = lLine.range(of: "^[-*+]\\s+", options: .regularExpression) {
                        let item = String(lLine[suffixRange.upperBound...])
                        items.append("<li>\(renderListItem(item, lineIndex: i))</li>")
                        i += 1
                    } else if lLine.isEmpty {
                        i += 1
                        continue
                    } else {
                        break
                    }
                }
                result.append("<ul>\(items.joined())</ul>")
                continue
            }
            
            if line.range(of: "^\\d+\\.\\s+", options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let lLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if lLine.range(of: "^\\d+\\.\\s+", options: .regularExpression) != nil,
                       let suffixRange = lLine.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                        let item = String(lLine[suffixRange.upperBound...])
                        items.append("<li>\(renderListItem(item, lineIndex: i))</li>")
                        i += 1
                    } else if lLine.isEmpty {
                        i += 1
                        continue
                    } else {
                        break
                    }
                }
                result.append("<ol>\(items.joined())</ol>")
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
            result.append("<pre><code>\(code)</code></pre>")
        }
        
        return result.joined(separator: "\n")
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
        result = result.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\(([^)]+)\\)", with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        
        if result.hasSuffix("  ") {
            result = String(result.dropLast(2)) + "<br>"
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
    }
    
    private static func css() -> String {
        guard let url = Bundle.main.url(forResource: "markdown", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return css
    }
    
    private static func script() -> String {
        """
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
        """
    }
}
