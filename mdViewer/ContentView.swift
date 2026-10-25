import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

enum ViewMode {
    case edit
    case preview
    case split
}

@MainActor
final class SplitScrollSync: ObservableObject {
    enum Source {
        case editor
        case preview
    }

    @Published private(set) var editorTarget: CGFloat?
    @Published private(set) var editorGeneration = 0
    @Published private(set) var previewTarget: CGFloat?
    @Published private(set) var previewGeneration = 0

    private var activeSource: Source?
    private var lastEventTime: TimeInterval = 0

    func editorDidScroll(_ fraction: CGFloat) {
        guard shouldAccept(.editor) else { return }
        previewTarget = fraction
        previewGeneration += 1
    }

    func previewDidScroll(_ fraction: CGFloat) {
        guard shouldAccept(.preview) else { return }
        editorTarget = fraction
        editorGeneration += 1
    }

    private func shouldAccept(_ source: Source) -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        if let activeSource, activeSource != source, now - lastEventTime < 0.15 {
            return false
        }
        activeSource = source
        lastEventTime = now
        return true
    }
}

struct ContentView: View {
    @StateObject private var store = DocumentStore()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("previewZoom") private var previewZoom = 1.0
    @State private var mode: ViewMode = .preview
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var crossfade: Double = 0
    @State private var findVisible = false
    @State private var findQuery = ""
    @State private var findGeneration = 0
    @State private var findForward = true
    @State private var findMatchFound: Bool?
    @State private var outline: [MarkdownHeading] = []
    @State private var scrollHeadingID: String?
    @State private var scrollHeadingGeneration = 0
    @State private var previewText = ""
    @State private var previewUpdateTask: Task<Void, Never>?
    @StateObject private var scrollSync = SplitScrollSync()
    @FocusState private var findFieldFocused: Bool

    private var contentBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 13/255, green: 17/255, blue: 23/255)
            : .white
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FolderSidebar(
                store: store,
                outline: outline,
                onSelectHeading: { id in
                    scrollToHeading(id)
                }
            )
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
                        Button(action: { toggleSplit() }) {
                            Label("Split", systemImage: "rectangle.split.2x1")
                                .font(.system(size: 12))
                                .frame(width: 52)
                                .contentShape(Rectangle())
                                .foregroundStyle(mode == .split ? Color.accentColor : Color.primary)
                        }
                        .help("Toggle Split View (⌘⌥E)")
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
            previewText = store.text
            handleLaunch()
        }
        .onChange(of: store.text) { _, newText in
            schedulePreviewUpdate(newText)
        }
        .task(id: store.text) {
            let text = store.text
            guard !text.isEmpty else {
                outline = []
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let headings = await Task.detached(priority: .userInitiated) {
                MarkdownConverter.outline(from: text)
            }.value
            guard !Task.isCancelled else { return }
            outline = headings
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
            exportPDF: { exportPDF(singlePage: $0) },
            exportHTML: exportHTML,
            beginPreviewFind: beginFind,
            toggleSplit: toggleSplit
        ))
        .onChange(of: mode) { _, newMode in
            previewUpdateTask?.cancel()
            previewText = store.text
            if newMode == .edit {
                closeFind()
            }
        }
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
            } else if mode == .split {
                splitArea
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
            MarkdownEditor(
                text: textBinding,
                scrollToFraction: scrollSync.editorTarget,
                scrollToGeneration: scrollSync.editorGeneration,
                onScrollFraction: { fraction in
                    if mode == .split {
                        scrollSync.editorDidScroll(fraction)
                    }
                }
            )
            .frame(maxWidth: 800, maxHeight: .infinity)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(contentBackgroundColor)
    }

    private var splitArea: some View {
        HStack(spacing: 0) {
            editorArea
            Divider()
            previewArea
        }
        .background(contentBackgroundColor)
    }

    private var previewArea: some View {
        MarkdownPreview(
            text: previewText,
            documentURL: store.fileURL,
            zoom: previewZoom,
            findQuery: findQuery,
            findGeneration: findGeneration,
            findForward: findForward,
            scrollToHeadingID: scrollHeadingID,
            scrollToHeadingGeneration: scrollHeadingGeneration,
            scrollFraction: scrollSync.previewTarget,
            scrollFractionGeneration: scrollSync.previewGeneration,
            onToggleTask: { line, checked in
                var lines = store.text.components(separatedBy: .newlines)
                guard line >= 0, line < lines.count else { return }
                guard let updated = toggledTaskLine(lines[line], checked: checked) else { return }
                lines[line] = updated
                store.textChanged(lines.joined(separator: "\n"))
            },
            onFindResult: { found in
                findMatchFound = found
            },
            onPreviewScroll: { fraction in
                if mode == .split {
                    scrollSync.previewDidScroll(fraction)
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if findVisible {
                previewFindBar
                    .padding(.top, 10)
                    .padding(.trailing, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var previewFindBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Find in preview", text: $findQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(width: 180)
                .focused($findFieldFocused)
                .onSubmit {
                    findNext(forward: !NSEvent.modifierFlags.contains(.shift))
                }
                .onChange(of: findQuery) { _, newValue in
                    findMatchFound = nil
                    if !newValue.isEmpty {
                        findForward = true
                        findGeneration += 1
                    }
                }
            Text(findStatusText)
                .font(.caption2)
                .foregroundStyle(findMatchFound == false ? Color.red : Color.secondary)
                .frame(minWidth: 58, alignment: .leading)
            Button {
                findNext(forward: false)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Previous match")
            Button {
                findNext(forward: true)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Next match")
            Button {
                closeFind()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close find bar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .onExitCommand {
            closeFind()
        }
    }

    private var findStatusText: String {
        guard !findQuery.isEmpty else { return "" }
        if findMatchFound == false { return "No matches" }
        if findMatchFound == true { return "Match" }
        return ""
    }

    private func beginFind() {
        findVisible = true
        findGeneration += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            findFieldFocused = true
        }
    }

    private func findNext(forward: Bool) {
        guard !findQuery.isEmpty else { return }
        findForward = forward
        findGeneration += 1
    }

    private func closeFind() {
        guard findVisible || !findQuery.isEmpty else { return }
        findVisible = false
        findQuery = ""
        findMatchFound = nil
        findGeneration += 1
    }

    private func scrollToHeading(_ id: String) {
        if mode != .preview {
            mode = .preview
            crossfade = 0
        }
        scrollHeadingID = id
        scrollHeadingGeneration += 1
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

    private func toggleSplit() {
        mode = mode == .split ? .preview : .split
    }

    private func schedulePreviewUpdate(_ text: String) {
        previewUpdateTask?.cancel()
        guard mode == .split else {
            previewText = text
            return
        }
        previewUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            previewText = text
        }
    }

    private func restoreLastSession() {
        let mode = RecentItems.lastWorkspaceMode()

        if mode == .folder,
           let folder = RecentItems.lastFolder(),
           FileManager.default.fileExists(atPath: folder.path) {
            store.openFolder(at: folder)
            return
        }

        if let file = RecentItems.lastFile(),
           FileManager.default.fileExists(atPath: file.path) {
            store.openFile(at: file)
            return
        }

        if let folder = RecentItems.lastFolder(),
           FileManager.default.fileExists(atPath: folder.path) {
            store.openFolder(at: folder)
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

    private func exportHTML() {
        guard !store.text.isEmpty else {
            store.status = "No content to export"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        let baseName = store.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = baseName + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let html = MarkdownConverter.exportedHTML(
            from: store.text,
            baseURL: store.fileURL?.deletingLastPathComponent()
        )
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            store.status = "Exported HTML"
        } catch {
            store.status = "Failed to export HTML: \(error.localizedDescription)"
        }
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
    let exportHTML: () -> Void
    let beginPreviewFind: () -> Void
    let toggleSplit: () -> Void

    func body(content: Content) -> some View {
        viewHandlers(exportHandlers(fileHandlers(content)))
    }

    private func fileHandlers<V: View>(_ content: V) -> some View {
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
            .onReceive(NotificationCenter.default.publisher(for: .newFileRequested)) { _ in
                store.createFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeFolderRequested)) { _ in
                store.closeFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSidebarSearchRequested)) { _ in
                guard store.folderURL != nil else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    columnVisibility = .all
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadFromDiskRequested)) { _ in
                store.reloadFromDisk()
            }
    }

    private func exportHandlers<V: View>(_ content: V) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportPDFRequested)) { _ in
                exportPDF(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportSinglePagePDFRequested)) { _ in
                exportPDF(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportHTMLRequested)) { _ in
                exportHTML()
            }
    }

    private func viewHandlers<V: View>(_ content: V) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarRequested)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleModeRequested)) { _ in
                toggleMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSplitRequested)) { _ in
                toggleSplit()
            }
            .onReceive(NotificationCenter.default.publisher(for: .findRequested)) { _ in
                if mode == .preview {
                    beginPreviewFind()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .performEditorFind, object: nil)
                    }
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
