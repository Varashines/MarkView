import SwiftUI
import WebKit
import AppKit

struct MarkdownPreview: NSViewRepresentable {
    let text: String
    var onToggleTask: ((Int, Bool) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "copyCode")
        config.userContentController.add(context.coordinator, name: "toggleTask")
        config.userContentController.add(context.coordinator, name: "mermaidDone")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard context.coordinator.lastMarkdownText != text else { return }
        if context.coordinator.skipNextLoad {
            context.coordinator.skipNextLoad = false
            context.coordinator.lastMarkdownText = text
            return
        }
        context.coordinator.lastMarkdownText = text
        context.coordinator.loadVersion += 1
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
        private var restoredVersion: UInt = 0

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
            case "mermaidDone":
                let y = savedScrollY
                guard y > 0, let webView = webView else { return }
                webView.evaluateJavaScript("window.scrollTo(0, \(y))")
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard loadVersion != restoredVersion else { return }
            restoredVersion = loadVersion
            let y = savedScrollY
            guard y > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                webView.evaluateJavaScript("window.scrollTo(0, \(y))")
            }
        }
    }
}
