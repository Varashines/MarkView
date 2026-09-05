import AppKit
import WebKit

enum PDFExportMode {
    case paginated
    case continuous
}

@MainActor
final class PDFExporter: NSObject {
    private let html: String
    private let window: NSWindow?
    private let resourceBase: URL?
    private let mode: PDFExportMode
    private var webView: WKWebView?
    private var resourceHandler: DocumentResourceHandler?
    private static var activeExporter: PDFExporter?

    private init(html: String, window: NSWindow?, resourceBase: URL?, mode: PDFExportMode) {
        self.html = html
        self.window = window
        self.resourceBase = resourceBase
        self.mode = mode
        super.init()
    }

    static func export(from html: String, window: NSWindow?, resourceBase: URL?, mode: PDFExportMode = .paginated) {
        let exporter = PDFExporter(html: html, window: window, resourceBase: resourceBase, mode: mode)
        activeExporter = exporter
        exporter.start()
    }

    private func start() {
        let config = WKWebViewConfiguration()
        let handler = DocumentResourceHandler()
        handler.baseURL = resourceBase
        config.setURLSchemeHandler(handler, forURLScheme: DocumentResourceHandler.scheme)
        config.setURLSchemeHandler(BundleResourceHandler(), forURLScheme: BundleResourceHandler.scheme)
        // Continuous export re-lays-out at 860 CSS px (the preview's max content width),
        // so the measuring viewport must match that width.
        let frame = mode == .continuous
            ? NSRect(x: 0, y: 0, width: 860, height: 600)
            : NSRect.zero
        let webView = WKWebView(frame: frame, configuration: config)
        webView.underPageBackgroundColor = .clear
        self.webView = webView
        self.resourceHandler = handler
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func finish() {
        Self.activeExporter = nil
        webView = nil
    }
}

extension PDFExporter: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitForContent(webView, attempts: 0)
    }

    private func waitForContent(_ webView: WKWebView, attempts: Int) {
        webView.evaluateJavaScript("window.__contentDone === true") { [weak self] result, _ in
            if (result as? Bool) == true {
                self?.printWebView(webView)
            } else if attempts < 150 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.waitForContent(webView, attempts: attempts + 1)
                }
            } else {
                self?.printWebView(webView)
            }
        }
    }

    private func printWebView(_ webView: WKWebView) {
        if mode == .continuous {
            measureForContinuousPrint(webView)
        } else {
            printPaginated(webView)
        }
    }

    private func measureForContinuousPrint(_ webView: WKWebView) {
        webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] height, _ in
            let cssHeight = (height as? Double) ?? 0
            self?.printContinuous(webView, cssHeight: cssHeight)
        }
    }

    private func printContinuous(_ webView: WKWebView, cssHeight: Double) {
        defer { finish() }

        // 860 CSS px wide layout at 96dpi → 645pt; 1px = 0.75pt with zero scaling.
        let paperWidth: CGFloat = 645
        let paperHeight = cssHeight * 0.75
        let maxHeight: CGFloat = 14_390

        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: paperWidth, height: min(paperHeight, maxHeight))
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .clip
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true

        if let window = window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    private func printPaginated(_ webView: WKWebView) {
        defer { finish() }

        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSMakeSize(612, 792)
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true

        if let window = window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish()
    }
}
