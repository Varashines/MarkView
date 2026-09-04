import SwiftUI
import WebKit
import AppKit

enum ViewMode {
    case edit
    case preview
}

struct ContentView: View {
    @StateObject private var store = DocumentStore()
    @State private var mode: ViewMode = .preview
    @State private var isSidebarVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(
                mode: $mode,
                isSidebarVisible: $isSidebarVisible,
                store: store,
                onExportPDF: exportPDF
            )
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            HStack(spacing: 0) {
                if store.folderURL != nil && isSidebarVisible {
                    FolderSidebar(store: store)
                        .frame(width: 230)
                    Divider()
                }

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
                    } else if store.text.isEmpty {
                        EmptyStateView(
                            onOpenFile: { store.openFile() },
                            onOpenFolder: { store.openFolder() }
                        )
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
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle(store.fileURL?.lastPathComponent ?? "Untitled")
        .navigationSubtitle(store.folderURL?.lastPathComponent ?? "")
        .onChange(of: store.isDirty) { _, dirty in
            NSApp.keyWindow?.isDocumentEdited = dirty
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            if url.hasDirectoryPath {
                isSidebarVisible = true
                store.openFolder(at: url)
            } else {
                store.openFile(at: url)
            }
            return true
        }
        .onAppear {
            store.onFileOpened = {}
            if let path = CommandLine.arguments.dropFirst().first {
                let url = URL(fileURLWithPath: path)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    isSidebarVisible = true
                    store.openFolder(at: url)
                } else {
                    store.openFile(at: url)
                }
            }
        }
        .onChange(of: store.folderURL) { _, newValue in
            if newValue != nil {
                isSidebarVisible = true
            }
        }
        .modifier(AppCommandHandlers(
            store: store,
            mode: $mode,
            isSidebarVisible: $isSidebarVisible,
            exportPDF: exportPDF
        ))
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

private struct AppCommandHandlers: ViewModifier {
    let store: DocumentStore
    @Binding var mode: ViewMode
    @Binding var isSidebarVisible: Bool
    let exportPDF: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { notification in
                if let url = notification.object as? URL {
                    store.openFile(at: url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFileRequested)) { _ in
                store.openFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFolderRequested)) { _ in
                store.openFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveRequested)) { _ in
                store.save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportPDFRequested)) { _ in
                exportPDF()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarRequested)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) { isSidebarVisible.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleModeRequested)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) { mode = mode == .preview ? .edit : .preview }
            }
            .onReceive(NotificationCenter.default.publisher(for: .findRequested)) { _ in
                if mode == .preview {
                    withAnimation(.easeInOut(duration: 0.15)) { mode = .edit }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .performEditorFind, object: nil)
                }
            }
    }
}
