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
    @State private var crossfade: Double = 0

    var body: some View {
        mainLayout
            .frame(minWidth: 600, minHeight: 400)
            .overlay(alignment: .bottomTrailing) {
                StatusBar(store: store)
                    .padding(.bottom, 12)
                    .padding(.trailing, 14)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if store.folderURL != nil {
                        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isSidebarVisible.toggle() } }) {
                            Image(systemName: "sidebar.left")
                        }
                        .help("Toggle Sidebar (⌘\\)")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { toggleMode() }) {
                        modeToggleLabel
                    }
                    .help("Toggle Edit/Preview (⌘E)")
                }
            }
            .navigationTitle(store.fileURL?.lastPathComponent ?? "Untitled")
            .navigationSubtitle(store.folderURL?.lastPathComponent ?? "")
            .onChange(of: store.isDirty) { _, dirty in
                NSApp.keyWindow?.isDocumentEdited = dirty
            }
            .dropDestination(for: URL.self) { urls, _ in
                handleDrop(urls)
            }
            .onAppear {
                handleLaunch()
            }
            .onChange(of: store.folderURL) { _, newValue in
                if newValue != nil {
                    isSidebarVisible = true
                }
            }
            .modifier(AppCommandHandlers(
                store: store,
                mode: $mode,
                toggleMode: toggleMode,
                isSidebarVisible: $isSidebarVisible,
                exportPDF: exportPDF
            ))
    }

    private var mainLayout: some View {
        HStack(spacing: 0) {
            if store.folderURL != nil && isSidebarVisible {
                FolderSidebar(store: store)
                    .frame(width: 230)
                Divider()
            }
            modeContent
        }
    }

    private var modeToggleLabel: some View {
        Label(mode == .preview ? "Edit" : "Preview", systemImage: mode == .preview ? "pencil" : "eye")
            .font(.system(size: 13))
            .frame(width: 68)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var modeContent: some View {
        Group {
            if mode == .edit {
                editorArea
            } else if store.text.isEmpty {
                EmptyStateView(
                    onOpenFile: { store.openFile() },
                    onOpenFolder: { store.openFolder() }
                )
            } else {
                previewArea
            }
        }
        .overlay {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .opacity(crossfade)
                .allowsHitTesting(false)
        }
    }

    private var editorArea: some View {
        HStack(spacing: 0) {
            Spacer()
            MarkdownEditor(text: textBinding)
                .frame(maxWidth: 800, maxHeight: .infinity)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private var previewArea: some View {
        MarkdownPreview(
            text: store.text,
            documentURL: store.fileURL,
            onToggleTask: { line, checked in
                var lines = store.text.components(separatedBy: .newlines)
                guard line >= 0, line < lines.count else { return }
                let current = lines[line]
                if checked {
                    lines[line] = current.replacingOccurrences(of: "- [ ]", with: "- [x]")
                } else {
                    lines[line] = current.replacingOccurrences(of: "- [x]", with: "- [ ]")
                }
                store.textChanged(lines.joined(separator: "\n"))
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        if url.hasDirectoryPath {
            isSidebarVisible = true
            store.openFolder(at: url)
        } else {
            store.openFile(at: url)
        }
        return true
    }

    private func handleLaunch() {
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
        } else {
            restoreLastSession()
        }
    }

    private func toggleMode() {
        guard crossfade == 0 else { return }
        withAnimation(.easeIn(duration: 0.08)) { crossfade = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            mode = mode == .preview ? .edit : .preview
            withAnimation(.easeOut(duration: 0.16)) { crossfade = 0 }
        }
    }

    private func restoreLastSession() {
        if let folder = RecentItems.lastFolder(),
           FileManager.default.fileExists(atPath: folder.path) {
            store.openFolder(at: folder)
        }
        if let file = RecentItems.lastFile(),
           FileManager.default.fileExists(atPath: file.path) {
            store.openFile(at: file)
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

private struct AppCommandHandlers: ViewModifier {
    let store: DocumentStore
    @Binding var mode: ViewMode
    let toggleMode: () -> Void
    @Binding var isSidebarVisible: Bool
    let exportPDF: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openFileURL)) { notification in
                if let url = notification.object as? URL {
                    store.openFile(at: url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFolderURL)) { notification in
                if let url = notification.object as? URL {
                    store.openFolder(at: url)
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
                toggleMode()
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
