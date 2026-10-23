import SwiftUI
import WebKit
import AppKit

struct MarkdownPreview: NSViewRepresentable {
    let text: String
    var documentURL: URL?
    var zoom: Double = 1.0
    var findQuery: String = ""
    var findGeneration: Int = 0
    var findForward: Bool = true
    var onToggleTask: ((Int, Bool) -> Void)?
    var onFindResult: ((Bool) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let resourceHandler = DocumentResourceHandler()
        config.setURLSchemeHandler(resourceHandler, forURLScheme: DocumentResourceHandler.scheme)
        config.setURLSchemeHandler(BundleResourceHandler(), forURLScheme: BundleResourceHandler.scheme)
        config.userContentController.add(context.coordinator, name: "copyCode")
        config.userContentController.add(context.coordinator, name: "toggleTask")
        config.userContentController.add(context.coordinator, name: "contentDone")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = false
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.resourceHandler = resourceHandler
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.resourceHandler?.baseURL = documentURL?.deletingLastPathComponent()
        if nsView.pageZoom != zoom {
            nsView.pageZoom = zoom
        }
        guard context.coordinator.lastMarkdownText != text else {
            context.coordinator.applyFind(to: nsView)
            return
        }
        if context.coordinator.skipNextLoad {
            context.coordinator.skipNextLoad = false
            context.coordinator.lastMarkdownText = text
            context.coordinator.applyFind(to: nsView)
            return
        }
        context.coordinator.lastMarkdownText = text
        context.coordinator.loadVersion += 1
        context.coordinator.resetFind()
        nsView.evaluateJavaScript("window.scrollY") { value, _ in
            if let y = value as? CGFloat {
                context.coordinator.savedScrollY = y
            }
        }
        let html = MarkdownConverter.html(from: text)
        nsView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MarkdownPreview
        var savedScrollY: CGFloat = 0
        var loadVersion: UInt = 0
        var skipNextLoad = false
        var lastMarkdownText: String?
        weak var webView: WKWebView?
        var resourceHandler: DocumentResourceHandler?
        private var restoredVersion: UInt = 0
        private var lastFindQuery: String?
        private var lastFindGeneration = -1
        private var lastFindForward = true

        init(parent: MarkdownPreview) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "copyCode":
                guard let code = message.body as? String else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            case "toggleTask":
                guard let dict = message.body as? [String: Any],
                      let line = dict["l"] as? Int,
                      let checked = dict["c"] as? Bool,
                      let webView = webView else { return }
                skipNextLoad = true
                webView.evaluateJavaScript("document.querySelector('input[data-line=\"\(line)\"]').checked = \(checked)")
                parent.onToggleTask?(line, checked)
            case "contentDone":
                let y = savedScrollY
                guard y > 0, let webView = webView else { return }
                webView.evaluateJavaScript("window.scrollTo(0, \(y))")
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFind(to: webView)
            guard loadVersion != restoredVersion else { return }
            restoredVersion = loadVersion
            let y = savedScrollY
            guard y > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                webView.evaluateJavaScript("window.scrollTo(0, \(y))")
            }
        }

        func resetFind() {
            lastFindQuery = nil
            lastFindGeneration = -1
        }

        func applyFind(to webView: WKWebView) {
            let query = parent.findQuery
            if query.isEmpty {
                if lastFindQuery != nil {
                    lastFindQuery = nil
                    lastFindGeneration = -1
                    webView.find("", configuration: WKFindConfiguration()) { _ in }
                }
                return
            }
            guard query != lastFindQuery
                    || parent.findGeneration != lastFindGeneration
                    || parent.findForward != lastFindForward else {
                return
            }
            lastFindQuery = query
            lastFindGeneration = parent.findGeneration
            lastFindForward = parent.findForward

            let configuration = WKFindConfiguration()
            configuration.backwards = !parent.findForward
            configuration.wraps = true
            webView.find(query, configuration: configuration) { [weak self] result in
                self?.parent.onFindResult?(result.matchFound)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased()

            if url.fragment != nil, url.host == nil, scheme == nil || scheme == "about" {
                decisionHandler(.allow)
                return
            }

            switch scheme {
            case "http", "https", "mailto":
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            case nil:
                openRelativeLink(url)
                decisionHandler(.cancel)
            default:
                decisionHandler(.cancel)
            }
        }

        private func openRelativeLink(_ url: URL) {
            guard let base = resourceHandler?.baseURL else { return }
            let target = base.appendingPathComponent(url.path).standardizedFileURL
            let ext = target.pathExtension.lowercased()
            if ["md", "markdown", "txt"].contains(ext) {
                NotificationCenter.default.post(name: .openFileURL, object: target)
            } else {
                NSWorkspace.shared.open(target)
            }
        }
    }
}
