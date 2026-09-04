import AppKit

enum MarkdownHighlighter {
    static func apply(to storage: NSTextStorage) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        let full = NSRange(location: 0, length: ns.length)

        let baseFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: [.boldFontMask])
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: [.italicFontMask])

        storage.beginEditing()

        func forEachMatch(_ pattern: String, _ options: NSRegularExpression.Options = [], _ handler: (NSTextCheckingResult) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            regex.enumerateMatches(in: ns as String, range: full) { match, _, _ in
                guard let match else { return }
                handler(match)
            }
        }

        func setForeground(_ color: NSColor, _ range: NSRange) {
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }

        func setFont(_ font: NSFont, _ range: NSRange) {
            storage.addAttribute(.font, value: font, range: range)
        }

        forEachMatch("^[ \\t]{0,3}#{1,6}[^\\n]*$", .anchorsMatchLines) { match in
            setFont(boldFont, match.range)
            setForeground(.systemBlue, match.range)
        }

        forEachMatch("(?<![\\w*])\\*\\*[^*\\n]+\\*\\*(?![\\w*])") { match in
            setFont(boldFont, match.range)
        }
        forEachMatch("(?<![\\w_])__[^_\\n]+__(?![\\w_])") { match in
            setFont(boldFont, match.range)
        }

        forEachMatch("(?<![\\w*])\\*[^*\\n]+\\*(?![\\w*])") { match in
            setFont(italicFont, match.range)
        }
        forEachMatch("(?<![\\w])_[^_\\n]+_(?![\\w])") { match in
            setFont(italicFont, match.range)
        }

        forEachMatch("`[^`\\n]+`") { match in
            setForeground(.systemPurple, match.range)
        }

        forEachMatch("\\[[^\\]\\n]+\\]\\([^)\\n]*\\)") { match in
            setForeground(.systemBlue, match.range)
        }

        forEachMatch("~~[^~\\n]+~~") { match in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            setForeground(.tertiaryLabelColor, match.range)
        }

        forEachMatch("^[ \\t]*>.*$", .anchorsMatchLines) { match in
            setForeground(.secondaryLabelColor, match.range)
        }

        forEachMatch("^[ \\t]*([-*+]|\\d{1,9}[.)])(?=[ \\t])", .anchorsMatchLines) { match in
            let markerRange = match.range(at: 1)
            if markerRange.location != NSNotFound {
                setForeground(.systemOrange, markerRange)
            }
        }

        forEachMatch("\\[[ xX]\\](?=[ \\t])") { match in
            setForeground(.secondaryLabelColor, match.range)
        }

        forEachMatch("^[ \\t]{0,3}([-*_])[ \\t]*\\1[ \\t]*\\1[-*_ \\t]*$", .anchorsMatchLines) { match in
            setForeground(.tertiaryLabelColor, match.range)
        }

        forEachMatch(
            "^[ \\t]{0,3}```[^\\n]*\\n[\\s\\S]*?(?:\\n[ \\t]{0,3}```[^\\n]*|\\Z)",
            [.anchorsMatchLines, .dotMatchesLineSeparators]
        ) { match in
            setFont(baseFont, match.range)
            setForeground(.secondaryLabelColor, match.range)
        }

        storage.endEditing()
        storage.edited(.editedAttributes, range: full, changeInLength: 0)
    }
}
