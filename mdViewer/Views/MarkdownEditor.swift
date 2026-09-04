import SwiftUI
import AppKit

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13

    func makeNSView(context: Context) -> NSScrollView {
        let textView = LineNumberTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.currentLineHighlightColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35)
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.hasHorizontalRuler = false
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler

        let contentView = scrollView.contentView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.showFindPanel),
            name: .performEditorFind,
            object: nil
        )

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != font {
            textView.font = font
            (nsView.verticalRulerView as? LineNumberRulerView)?.invalidateLineCount()
            nsView.verticalRulerView?.needsDisplay = true
            textView.needsDisplay = true
        }
        if textView.string != text {
            textView.string = text
            (nsView.verticalRulerView as? LineNumberRulerView)?.invalidateLineCount()
            nsView.verticalRulerView?.needsDisplay = true
            textView.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: LineNumberTextView?
        weak var ruler: LineNumberRulerView?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            ruler?.invalidateLineCount()
            ruler?.needsDisplay = true
            textView.needsDisplay = true
        }

        @objc func boundsChanged() {
            ruler?.needsDisplay = true
        }

        @objc func showFindPanel() {
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            textView.performFindPanelAction(item)
        }
    }
}

final class LineNumberTextView: NSTextView {
    var currentLineHighlightColor: NSColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35)

    override func draw(_ dirtyRect: NSRect) {
        drawCurrentLineHighlight()
        super.draw(dirtyRect)
    }

    private func drawCurrentLineHighlight() {
        guard drawsBackground == false else { return }
        guard window?.firstResponder as? NSTextView === self else { return }
        guard let layoutManager else { return }
        let length = (string as NSString).length
        guard length > 0 else { return }

        let location = min(selectedRange().location, length)
        let glyphIndex = min(
            layoutManager.glyphIndexForCharacter(at: location),
            max(0, layoutManager.numberOfGlyphs - 1)
        )
        guard glyphIndex != NSNotFound else { return }
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard lineRect.height > 0 else { return }

        let y = textContainerOrigin.y + lineRect.minY
        let highlight = NSRect(x: 0, y: y, width: bounds.width, height: lineRect.height)
        currentLineHighlightColor.setFill()
        highlight.fill()
    }
}

final class LineNumberRulerView: NSRulerView {
    private weak var textView: LineNumberTextView?
    private var cachedLineCount: Int?

    init(textView: LineNumberTextView) {
        self.textView = textView
        super.init(scrollView: nil, orientation: .verticalRuler)
        clientView = textView
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func invalidateLineCount() {
        cachedLineCount = nil
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let content = textView.string as NSString
        let lineCount = cachedLineCount ?? {
            let count = content.components(separatedBy: .newlines).count
            cachedLineCount = count
            return count
        }()

        let digitWidth = max(1, String(lineCount).count)
        let width = max(34, CGFloat(digitWidth) * 9 + 18)
        if abs(ruleThickness - width) > 0.5 {
            ruleThickness = width
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        var glyphIndex = glyphRange.location
        var lastDrawnLine = -1

        while glyphIndex < NSMaxRange(glyphRange) {
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            guard characterIndex != NSNotFound else { break }

            let lineRange = content.lineRange(for: NSRange(location: characterIndex, length: 0))
            let lineNumber = content.substring(to: lineRange.location).components(separatedBy: "\n").count

            if lineNumber != lastDrawnLine {
                lastDrawnLine = lineNumber
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                guard lineRect.height > 0 else { break }
                let origin = convert(NSPoint(x: 0, y: lineRect.minY + textView.textContainerOrigin.y), from: textView)
                let label = String(lineNumber) as NSString
                let labelSize = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(
                        x: ruleThickness - labelSize.width - 8,
                        y: origin.y + (lineRect.height - labelSize.height) / 2
                    ),
                    withAttributes: attributes
                )
            }

            let nextCharacter = lineRange.upperBound
            if nextCharacter >= content.length { break }
            let nextGlyph = layoutManager.glyphIndexForCharacter(at: nextCharacter)
            if nextGlyph <= glyphIndex { break }
            glyphIndex = nextGlyph
        }

        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        separator.lineWidth = 1
        separator.stroke()
    }
}
