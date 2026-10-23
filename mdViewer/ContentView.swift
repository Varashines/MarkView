import SwiftUI
import WebKit
import AppKit

enum ViewMode {
    case edit
    case preview
}

struct ContentView: View {
    @StateObject private var store = DocumentStore()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("previewZoom") private var previewZoom = 1.0
    @State private var mode: ViewMode = .preview
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var crossfade: Double = 0

    private var contentBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 13/255, green: 17/255, blue: 23/255)
            : .white
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FolderSidebar(store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 400)
        } detail: {
            modeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 6) {
                            Text(store.fileURL?.lastPathComponent ?? "Untitled")
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let folderName = store.folderURL?.lastPathComponent {
                                Text(folderName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.08))
                        )
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: { toggleMode() }) {
                            Label("Preview", systemImage: "eye")
                                .font(.system(size: 12))
                                .frame(width: 58)
                                .contentShape(Rectangle())
                                .foregroundStyle(mode == .preview ? Color.accentColor : Color.primary)
                        }
                        .help("Toggle Edit/Preview (⌘E)")
                    }
                }
                .navigationTitle(store.fileURL?.lastPathComponent ?? "Untitled")
                .navigationSubtitle(store.folderURL?.lastPathComponent ?? "")
        }
        .background(WindowChrome(colorScheme: colorScheme))
        .frame(minWidth: 600, minHeight: 400)
        .overlay(alignment: .bottomTrailing) {
            StatusBar(store: store)
                .padding(.bottom, 12)
                .padding(.trailing, 14)
        }
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
            withAnimation(.easeInOut(duration: 0.15)) {
                columnVisibility = (newValue != nil) ? .all : .detailOnly
            }
        }
        .modifier(AppCommandHandlers(
            store: store,
            mode: $mode,
            toggleMode: toggleMode,
            columnVisibility: $columnVisibility,
            previewZoom: $previewZoom,
            exportPDF: { exportPDF(singlePage: $0) }
        ))
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
                .fill(contentBackgroundColor)
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
        .background(contentBackgroundColor)
    }

    private var previewArea: some View {
        MarkdownPreview(
            text: store.text,
            documentURL: store.fileURL,
            zoom: previewZoom,
            onToggleTask: { line, checked in
                var lines = store.text.components(separatedBy: .newlines)
                guard line >= 0, line < lines.count else { return }
                guard let updated = toggledTaskLine(lines[line], checked: checked) else { return }
                lines[line] = updated
                store.textChanged(lines.joined(separator: "\n"))
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        if url.hasDirectoryPath {
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
        withAnimation(.easeInOut(duration: 0.1)) { crossfade = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            mode = mode == .preview ? .edit : .preview
            withAnimation(.easeInOut(duration: 0.18)) { crossfade = 0 }
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

    private func toggledTaskLine(_ line: String, checked: Bool) -> String? {
        let pattern = "^(\\s*(?:[-*+]|\\d{1,9}[.)])\\s+\\[)( |x|X)(\\])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        return ns.replacingCharacters(in: match.range(at: 2), with: checked ? "x" : " ")
    }

    private func exportPDF(singlePage: Bool = false) {
        guard !store.text.isEmpty else {
            store.status = "No content to export"
            return
        }
        let html = MarkdownConverter.html(from: store.text)
        let window = NSApp.keyWindow
        PDFExporter.export(
            from: html,
            window: window,
            resourceBase: store.fileURL?.deletingLastPathComponent(),
            mode: singlePage ? .continuous : .paginated
        )
    }
}

private struct AppCommandHandlers: ViewModifier {
    let store: DocumentStore
    @Binding var mode: ViewMode
    let toggleMode: () -> Void
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var previewZoom: Double
    let exportPDF: (_ singlePage: Bool) -> Void

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
            exportPDF(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSinglePagePDFRequested)) { _ in
            exportPDF(true)
        }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarRequested)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                }
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
            .onReceive(NotificationCenter.default.publisher(for: .zoomInRequested)) { _ in
                previewZoom = min(3.0, (previewZoom * 1.25 * 100).rounded() / 100)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOutRequested)) { _ in
                previewZoom = max(0.5, (previewZoom / 1.25 * 100).rounded() / 100)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomResetRequested)) { _ in
                previewZoom = 1.0
            }
    }
}
