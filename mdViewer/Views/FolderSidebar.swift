import SwiftUI
import AppKit

private struct VisibleTreeRow: Identifiable {
    let node: FileTreeNode
    let depth: Int

    var id: URL { node.id }
}

private struct SearchGroup: Identifiable {
    let url: URL
    let hits: [FolderSearch.Hit]

    var id: URL { url }
}

struct FolderSidebar: View {
    @ObservedObject var store: DocumentStore
    var outline: [MarkdownHeading] = []
    var onSelectHeading: ((String) -> Void)?

    private enum SidebarTab: String, CaseIterable, Identifiable {
        case files = "Files"
        case outline = "Outline"
        var id: String { rawValue }
    }

    private enum PromptKind {
        case renameFile(URL)
        case renameFolder(URL)
        case newFolder(URL)
    }

    @State private var selectedTab: SidebarTab = .outline
    @State private var searchText = ""
    @State private var searchResults: [FolderSearch.Hit] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var prompt: PromptKind?
    @State private var promptText = ""

    @State private var pendingTrashURL: URL?
    @State private var pendingTrashIsDirectory = false
    @State private var showTrashConfirmation = false

    @FocusState private var searchFocused: Bool

    private var isFolderMode: Bool { store.folderURL != nil }
    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFiltering: Bool { !query.isEmpty }

    private var visibleRows: [VisibleTreeRow] {
        var rows: [VisibleTreeRow] = []

        func append(_ nodes: [FileTreeNode], depth: Int) {
            for node in nodes {
                rows.append(VisibleTreeRow(node: node, depth: depth))
                guard node.isFolder, store.expandedFolders.contains(node.url) else { continue }
                append(node.children, depth: depth + 1)
            }
        }

        append(store.folderTree, depth: 0)
        return rows
    }

    private var fileMatches: [FolderScanner.Entry] {
        guard isFiltering else { return [] }
        return store.folderFiles.filter {
            $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedResults: [SearchGroup] {
        Dictionary(grouping: searchResults, by: { $0.url })
            .map { SearchGroup(url: $0.key, hits: $0.value.sorted { $0.line < $1.line }) }
            .sorted { relativePath(for: $0.url) < relativePath(for: $1.url) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isFolderMode {
                if selectedTab == .files {
                    searchField
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }

                Picker("Sidebar", selection: $selectedTab) {
                    ForEach(SidebarTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            content
        }
        .onChange(of: store.folderURL) { _, folder in
            selectedTab = folder == nil ? .outline : .files
            if folder == nil {
                searchText = ""
                searchResults = []
                isSearching = false
                searchTask?.cancel()
            }
        }
        .onChange(of: searchText) { _, _ in
            scheduleSearch()
        }
        .onChange(of: store.folderFiles) { _, _ in
            if isFiltering {
                scheduleSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebarSearchRequested)) { _ in
            guard isFolderMode else { return }
            selectedTab = .files
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                searchFocused = true
            }
        }
        .alert(promptTitle, isPresented: promptPresented) {
            TextField("Name", text: $promptText)
            Button("Cancel", role: .cancel) { prompt = nil }
            Button("Save") { performPrompt() }
        } message: {
            Text(promptMessage)
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: $showTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let url = pendingTrashURL {
                    store.trashItem(at: url)
                }
                pendingTrashURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingTrashURL = nil
            }
        } message: {
            if let url = pendingTrashURL {
                Text(
                    pendingTrashIsDirectory
                        ? "“\(url.lastPathComponent)” and everything inside it will be moved to the Trash."
                        : "“\(url.lastPathComponent)” will be moved to the Trash."
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: isFolderMode ? "folder.fill" : "doc.text.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if isFolderMode {
                    Text(folderSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let url = store.fileURL {
                    Text(url.deletingLastPathComponent().lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if isFolderMode {
                folderMenu
            } else if let url = store.fileURL {
                Button {
                    store.revealInFinder(url)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var headerTitle: String {
        if let folder = store.folderURL {
            return folder.lastPathComponent
        }
        return store.fileURL?.lastPathComponent ?? "MarkView"
    }

    private var folderSubtitle: String {
        if store.isScanningFolder {
            return "Scanning…"
        }
        let count = store.folderFiles.count
        return count == 1 ? "1 file" : "\(count) files"
    }

    private var folderMenu: some View {
        Menu {
            Button("New File") {
                store.createFile(in: store.sidebarTargetFolder ?? store.folderURL)
            }
            Button("New Folder…") {
                beginNewFolder(in: store.sidebarTargetFolder ?? store.folderURL)
            }
            Divider()
            Button("Reveal in Finder") {
                store.revealFolder()
            }
            Button("Rescan Folder") {
                store.rescanFolder()
            }
            Button("Collapse All") {
                store.collapseAllFolders()
            }
            Divider()
            Button("Close Folder") {
                store.closeFolder()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Folder actions")
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search files and content", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($searchFocused)
            if isFiltering {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard isFiltering else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        let entries = store.folderFiles
        let currentQuery = query

        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            let hits = await Task.detached(priority: .userInitiated) {
                FolderSearch.search(entries: entries, query: currentQuery)
            }.value

            guard !Task.isCancelled else { return }
            searchResults = hits
            isSearching = false
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !isFolderMode {
            fileModeContent
        } else if selectedTab == .outline {
            outlineList
        } else if isFiltering {
            searchResultsList
        } else {
            fileTree
        }
    }

    @ViewBuilder
    private var fileModeContent: some View {
        if store.fileURL == nil {
            noFileState
        } else {
            outlineList
        }
    }

    private var noFileState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("No file open")
                .font(.callout.weight(.medium))
            Text("Open a file, or open a folder to browse it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open File…") {
                store.openFile()
            }
            Button("Open Folder…") {
                store.openFolder()
            }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var outlineList: some View {
        List {
            ForEach(outline) { heading in
                Button {
                    onSelectHeading?(heading.id)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(heading.level == 1 ? 0.45 : 0.18))
                            .frame(width: 2, height: 14)

                        Text(heading.title)
                            .font(heading.level == 1 ? .callout.weight(.semibold) : .callout)
                            .lineLimit(2)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("H\(heading.level)")
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if outline.isEmpty {
                Text("No headings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fileTree: some View {
        ScrollViewReader { proxy in
            List(selection: fileSelection) {
                if let current = store.fileURL, !isInsideOpenFolder(current) {
                    Section("Current File") {
                        currentFileRow(current)
                    }
                }

                Section {
                    ForEach(visibleRows) { row in
                        treeRow(row)
                            .id(row.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if store.folderFiles.isEmpty {
                    emptyFolderState
                }
            }
            .onChange(of: store.fileURL) { _, url in
                scroll(proxy, to: url)
            }
            .onAppear {
                scroll(proxy, to: store.fileURL, animated: false)
            }
        }
    }

    private var fileSelection: Binding<URL?> {
        Binding(
            get: { store.fileURL },
            set: { url in
                guard let url,
                      store.folderFiles.contains(where: {
                          $0.url.standardizedFileURL == url.standardizedFileURL
                      }) else {
                    return
                }
                store.openFile(at: url)
            }
        )
    }

    private func isInsideOpenFolder(_ url: URL) -> Bool {
        guard let folder = store.folderURL else { return false }
        return url.isDescendant(of: folder)
    }

    private func scroll(_ proxy: ScrollViewProxy, to url: URL?, animated: Bool = true) {
        guard let url else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(url, anchor: .center)
                }
            } else {
                proxy.scrollTo(url, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func treeRow(_ row: VisibleTreeRow) -> some View {
        if row.node.isFolder {
            Button {
                store.sidebarTargetFolder = row.node.url
                store.toggleFolder(row.node.url)
            } label: {
                treeRowContent(row)
            }
            .buttonStyle(.plain)
            .contextMenu {
                folderContextMenu(for: row.node.url)
            }
        } else {
            treeRowContent(row)
                .tag(row.node.url)
                .contextMenu {
                    fileContextMenu(for: row.node.url)
                }
        }
    }

    private func treeRowContent(_ row: VisibleTreeRow) -> some View {
        let expanded = store.expandedFolders.contains(row.node.url)
        let isCurrent = store.fileURL?.standardizedFileURL == row.node.url.standardizedFileURL

        return HStack(spacing: 6) {
            if row.node.isFolder {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10)
                Image(systemName: expanded ? "folder.fill" : "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
                    .frame(width: 10)
                Image(systemName: fileIcon(for: row.node.url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(row.node.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            if !row.node.isFolder, isCurrent, store.isDirty {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
            }

            Spacer(minLength: 0)

            if row.node.isFolder {
                Text("\(row.node.fileCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, CGFloat(row.depth) * 12)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func currentFileRow(_ url: URL) -> some View {
        Button {
            store.openFile(at: url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyFolderState: some View {
        VStack(spacing: 10) {
            if store.isScanningFolder {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No Markdown files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("New File") {
                    store.createFile(in: store.folderURL)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var searchResultsList: some View {
        List {
            if !fileMatches.isEmpty {
                Section("Files") {
                    ForEach(fileMatches) { entry in
                        Button {
                            store.openFile(at: entry.url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: fileIcon(for: entry.url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text((entry.url.lastPathComponent as NSString).deletingPathExtension)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Text(relativePath(for: entry.url))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ForEach(groupedResults) { group in
                Section {
                    ForEach(group.hits) { hit in
                        Button {
                            store.openFile(at: hit.url)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("L\(hit.line)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 30, alignment: .trailing)
                                Text(hit.snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.url.lastPathComponent)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(relativePath(for: group.url))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }

            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if !isSearching && fileMatches.isEmpty && searchResults.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Menus

    @ViewBuilder
    private func fileContextMenu(for url: URL) -> some View {
        Button("Open") {
            store.openFile(at: url)
        }
        Divider()
        Button("Rename…") {
            beginRename(url, isDirectory: false)
        }
        Button("Duplicate") {
            store.duplicateFile(at: url)
        }
        Button("Reveal in Finder") {
            store.revealInFinder(url)
        }
        Button("Copy Path") {
            store.copyPath(url)
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            confirmTrash(url, isDirectory: false)
        }
    }

    @ViewBuilder
    private func folderContextMenu(for url: URL) -> some View {
        Button("New File Here") {
            store.createFile(in: url)
        }
        Button("New Folder…") {
            beginNewFolder(in: url)
        }
        Divider()
        Button("Rename…") {
            beginRename(url, isDirectory: true)
        }
        Button("Reveal in Finder") {
            store.revealInFinder(url)
        }
        Button("Copy Path") {
            store.copyPath(url)
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            confirmTrash(url, isDirectory: true)
        }
    }

    // MARK: - Rename / new folder / trash

    private var promptPresented: Binding<Bool> {
        Binding(
            get: { prompt != nil },
            set: { presented in
                if !presented { prompt = nil }
            }
        )
    }

    private var promptTitle: String {
        switch prompt {
        case .renameFile: return "Rename File"
        case .renameFolder: return "Rename Folder"
        case .newFolder: return "New Folder"
        case nil: return ""
        }
    }

    private var promptMessage: String {
        switch prompt {
        case .renameFile: return "Enter a new name for the file."
        case .renameFolder: return "Enter a new name for the folder."
        case .newFolder: return "Enter a name for the new folder."
        case nil: return ""
        }
    }

    private func beginRename(_ url: URL, isDirectory: Bool) {
        promptText = url.lastPathComponent
        prompt = isDirectory ? .renameFolder(url) : .renameFile(url)
    }

    private func beginNewFolder(in directory: URL?) {
        guard let directory else { return }
        promptText = "New Folder"
        prompt = .newFolder(directory)
    }

    private func performPrompt() {
        guard let prompt else { return }
        switch prompt {
        case .renameFile(let url), .renameFolder(let url):
            store.renameItem(at: url, to: promptText)
        case .newFolder(let directory):
            store.createFolder(named: promptText, in: directory)
        }
        self.prompt = nil
    }

    private func confirmTrash(_ url: URL, isDirectory: Bool) {
        pendingTrashURL = url
        pendingTrashIsDirectory = isDirectory
        showTrashConfirmation = true
    }

    // MARK: - Helpers

    private func fileIcon(for url: URL) -> String {
        url.pathExtension.lowercased() == "txt" ? "doc.text" : "doc.richtext"
    }

    private func relativePath(for url: URL) -> String {
        guard let folder = store.folderURL else { return url.lastPathComponent }
        let base = folder.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return path }
        let relative = String(path.dropFirst(base.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? url.lastPathComponent : relative
    }
}
