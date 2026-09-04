import SwiftUI
import WebKit

enum ViewMode {
    case edit
    case preview
}

struct ContentView: View {
    @StateObject private var store = DocumentStore()
    @State private var mode: ViewMode = .preview
    
    var body: some View {
        VStack(spacing: 0) {
            Toolbar(
                mode: $mode,
                store: store,
                onExportPDF: exportPDF
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            Group {
                if mode == .edit {
                    HStack(spacing: 0) {
                        Spacer()
                        MarkdownEditor(text: textBinding)
                            .frame(maxWidth: 800, maxHeight: .infinity)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                } else {
                    MarkdownPreview(text: store.text, documentURL: store.fileURL, onToggleTask: { line, checked in
                        var lines = store.text.components(separatedBy: .newlines)
                        guard line >= 0, line < lines.count else { return }
                        let current = lines[line]
                        if checked {
                            lines[line] = current.replacingOccurrences(of: "- [ ]", with: "- [x]")
                        } else {
                            lines[line] = current.replacingOccurrences(of: "- [x]", with: "- [ ]")
                        }
                        store.textChanged(lines.joined(separator: "\n"))
                    })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            store.onFileOpened = {}
            if let path = CommandLine.arguments.dropFirst().first {
                store.openFile(at: URL(fileURLWithPath: path))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { notification in
            if let url = notification.object as? URL {
                store.openFile(at: url)
            }
        }
    }
    
    private var textBinding: Binding<String> {
        Binding(
            get: { store.text },
            set: { store.textChanged($0) }
        )
    }
    
    private func exportPDF() {
        guard !store.text.isEmpty else {
            store.status = "No content to export"
            return
        }
        let html = MarkdownConverter.html(from: store.text)
        let window = NSApp.keyWindow
        PDFExporter.export(from: html, window: window, resourceBase: store.fileURL?.deletingLastPathComponent())
    }
}
