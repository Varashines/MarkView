import AppKit
import WebKit

@MainActor
final class PDFExporter: NSObject {
    private let html: String
    private let window: NSWindow?
    private var webView: WKWebView?
    private static var activeExporter: PDFExporter?

    private init(html: String, window: NSWindow?) {
        self.html = html
        self.window = window
        super.init()
    }

    static func export(from html: String, window: NSWindow?) {
        let exporter = PDFExporter(html: html, window: window)
        activeExporter = exporter
        exporter.start()
    }

    private func start() {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        self.webView = webView
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
