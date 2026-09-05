import AppKit
import WebKit

@MainActor
final class PDFExporter: NSObject {
    private let html: String
    private let window: NSWindow?
    private let resourceBase: URL?
    private var webView: WKWebView?
    private var resourceHandler: DocumentResourceHandler?
    private static var activeExporter: PDFExporter?

    private init(html: String, window: NSWindow?, resourceBase: URL?) {
        self.html = html
        self.window = window
        self.resourceBase = resourceBase
        super.init()
    }

    static func export(from html: String, window: NSWindow?, resourceBase: URL?) {
        let exporter = PDFExporter(html: html, window: window, resourceBase: resourceBase)
        activeExporter = exporter
        exporter.start()
    }

    private func start() {
        let config = WKWebViewConfiguration()
        let handler = DocumentResourceHandler()
        handler.baseURL = resourceBase
        config.setURLSchemeHandler(handler, forURLScheme: DocumentResourceHandler.scheme)
        config.setURLSchemeHandler(BundleResourceHandler(), forURLScheme: BundleResourceHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
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
