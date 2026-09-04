import SwiftUI
import AppKit

struct WindowChrome: NSViewRepresentable {
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.apply(colorScheme: colorScheme)
        return view
    }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.apply(colorScheme: colorScheme)
    }
}

final class ChromeView: NSView {
    private var lastColorScheme: ColorScheme?

    func apply(colorScheme: ColorScheme) {
        lastColorScheme = colorScheme
        configureWindow()
    }

    override func viewDidMoveToWindow() {
        configureWindow()
    }

    private func configureWindow() {
        guard let window, let colorScheme = lastColorScheme else { return }
        let color = colorScheme == .dark
            ? NSColor(srgbRed: 13/255, green: 17/255, blue: 23/255, alpha: 1)
            : .white
        window.titlebarAppearsTransparent = true
        window.backgroundColor = color
    }
}
