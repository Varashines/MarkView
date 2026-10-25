import Foundation
import AppKit
import CoreServices
import Darwin
import UniformTypeIdentifiers

enum WorkspaceMode: String {
    case file
    case folder
}

struct FileTreeNode: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder
        case file
    }

    let url: URL
    let name: String
    let kind: Kind
    var children: [FileTreeNode]
    var fileCount: Int

    var id: URL { url }
    var isFolder: Bool { kind == .folder }

    static func build(entries: [FolderScanner.Entry], root: URL) -> [FileTreeNode] {
        final class BuilderNode {
            let url: URL
            let name: String
            let isFolder: Bool
            var children: [String: BuilderNode] = [:]

            init(url: URL, name: String, isFolder: Bool) {
                self.url = url
                self.name = name
                self.isFolder = isFolder
            }
        }

        let rootNode = BuilderNode(url: root, name: root.lastPathComponent, isFolder: true)

        for entry in entries {
            let components = entry.relativePath
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty else { continue }

            var current = rootNode
            var directory = root
            for (index, component) in components.enumerated() {
                let isFile = index == components.count - 1
                if !isFile {
                    directory.appendPathComponent(component)
                }

                if let existing = current.children[component] {
                    current = existing
                    continue
                }

                let node = BuilderNode(
                    url: isFile ? entry.url : directory,
                    name: component,
                    isFolder: !isFile
                )
                current.children[component] = node
                current = node
            }
        }

        func convert(_ node: BuilderNode) -> FileTreeNode? {
            if !node.isFolder {
                return FileTreeNode(
                    url: node.url,
                    name: node.name,
                    kind: .file,
                    children: [],
                    fileCount: 1
                )
            }

            let children = node.children.values.compactMap(convert)
            guard !children.isEmpty else { return nil }

            let sorted = children.sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder {
                    return lhs.isFolder
                }
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison == .orderedSame {
                    return lhs.url.path < rhs.url.path
                }
                return comparison == .orderedAscending
            }

            return FileTreeNode(
                url: node.url,
                name: node.name,
                kind: .folder,
                children: sorted,
                fileCount: sorted.reduce(0) { $0 + $1.fileCount }
            )
        }

        return rootNode.children.values.compactMap(convert).sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder {
                return lhs.isFolder
            }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.url.path < rhs.url.path
            }
            return comparison == .orderedAscending
        }
    }
}

enum DocumentStats {
    static func summary(for text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let minutes = Double(words) / 200.0
        let reading: String
        if words == 0 {
            reading = "0 min"
        } else if minutes < 1 {
            reading = "<1 min"
        } else {
            reading = "\(Int(minutes.rounded())) min"
        }
        return "\(grouped(words)) words · \(reading) read"
    }

    static func grouped(_ number: Int) -> String {
        let digits = String(number)
        guard digits.count > 3 else { return digits }
        var grouped = ""
        for (index, digit) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 {
                grouped.insert(",", at: grouped.startIndex)
            }
            grouped.insert(digit, at: grouped.startIndex)
        }
        return grouped
    }
}

enum FolderSearch {
    struct Hit: Identifiable, Equatable {
        let url: URL
        let line: Int
        let snippet: String

        var id: String { url.absoluteString + "#\(line)" }
    }

    static func search(
        entries: [FolderScanner.Entry],
        query: String,
        maxHitsPerFile: Int = 3,
        maxTotal: Int = 200
    ) -> [Hit] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }

        var hits: [Hit] = []
        for entry in entries {
            guard hits.count < maxTotal else { break }
            guard let data = try? Data(contentsOf: entry.url),
                  data.count < 1_000_000,
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }
            guard content.lowercased().contains(needle) else { continue }

            let lines = content.components(separatedBy: .newlines)
            var fileHits = 0
            for (index, line) in lines.enumerated() where fileHits < maxHitsPerFile {
                if line.lowercased().contains(needle) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let snippet = trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
                    hits.append(Hit(url: entry.url, line: index + 1, snippet: snippet))
                    fileHits += 1
                }
            }
        }
        return hits
    }
}

enum RecentItems {
    static let maxItems = 10
    static let filesKey = "recentFiles"
    static let foldersKey = "recentFolders"
    static let lastFileKey = "lastOpenedFile"
    static let lastFolderKey = "lastOpenedFolder"
    static let lastModeKey = "lastWorkspaceMode"

    static func addFile(_ url: URL, defaults: UserDefaults = .standard) {
        add(url, key: filesKey, defaults: defaults)
        defaults.set(url.standardizedFileURL.path, forKey: lastFileKey)
    }

    static func addFolder(_ url: URL, defaults: UserDefaults = .standard) {
        add(url, key: foldersKey, defaults: defaults)
        defaults.set(url.standardizedFileURL.path, forKey: lastFolderKey)
    }

    static func files(defaults: UserDefaults = .standard) -> [URL] {
        read(filesKey, defaults)
    }

    static func folders(defaults: UserDefaults = .standard) -> [URL] {
        read(foldersKey, defaults)
    }

    static func lastFile(defaults: UserDefaults = .standard) -> URL? {
        defaults.string(forKey: lastFileKey).map { URL(fileURLWithPath: $0) }
    }

    static func lastFolder(defaults: UserDefaults = .standard) -> URL? {
        defaults.string(forKey: lastFolderKey).map { URL(fileURLWithPath: $0) }
    }

    static func setLastWorkspaceMode(_ mode: WorkspaceMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: lastModeKey)
    }

    static func lastWorkspaceMode(defaults: UserDefaults = .standard) -> WorkspaceMode? {
        defaults.string(forKey: lastModeKey).flatMap(WorkspaceMode.init(rawValue:))
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: filesKey)
        defaults.removeObject(forKey: foldersKey)
        defaults.removeObject(forKey: lastFileKey)
        defaults.removeObject(forKey: lastFolderKey)
        defaults.removeObject(forKey: lastModeKey)
    }

    private static func add(_ url: URL, key: String, defaults: UserDefaults) {
        var urls = read(key, defaults)
        let standard = url.standardizedFileURL
        urls.removeAll { $0.standardizedFileURL == standard }
        urls.insert(standard, at: 0)
        if urls.count > maxItems {
            urls.removeLast(urls.count - maxItems)
        }
        if let data = try? JSONEncoder().encode(urls) {
            defaults.set(data, forKey: key)
        }
    }

    private static func read(_ key: String, _ defaults: UserDefaults) -> [URL] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([URL].self, from: data)) ?? []
    }
}

enum FolderScanner {
    struct Entry: Identifiable, Equatable {
        let url: URL
        let relativePath: String
        let modified: Date?

        var id: URL { url }
    }

    static let markdownExtensions: Set<String> = ["md", "markdown", "txt"]
    private static let maxEntries = 5000
    private static let skippedDirectories: Set<String> = ["node_modules"]

    static func scan(folder: URL) -> [Entry] {
        let basePath = folder.standardizedFileURL.path
        var entries: [Entry] = []

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return entries
        }

        for case let url as URL in enumerator {
            if entries.count >= maxEntries { break }

            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if skippedDirectories.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard markdownExtensions.contains(url.pathExtension.lowercased()) else { continue }

            var relativePath = url.standardizedFileURL.path
            if relativePath.hasPrefix(basePath) {
                relativePath.removeFirst(basePath.count)
            }
            if relativePath.hasPrefix("/") {
                relativePath.removeFirst()
            }
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            entries.append(Entry(url: url, relativePath: relativePath, modified: modified))
        }

        return entries.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }
}

extension URL {
    func isDescendant(of folder: URL) -> Bool {
        let candidate = standardizedFileURL.path
        let base = folder.standardizedFileURL.path
        return candidate == base || candidate.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}

private final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "com.markview.folder-watcher")

    func start(url: URL, onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagIgnoreSelf
        )

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, _, eventFlags, _ in
                guard let info else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handle(count: count, flags: eventFlags)
            },
            &context,
            [url.standardizedFileURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        )

        guard let stream else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)

        if !FSEventStreamStart(stream) {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func handle(count: Int, flags: UnsafePointer<FSEventStreamEventFlags>) {
        let mask = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed
        )

        var relevant = false
        for index in 0..<count where flags[index] & mask != 0 {
            relevant = true
            break
        }
        guard relevant else { return }

        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.onChange?()
            }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    func stop() {
        pending?.cancel()
        pending = nil
        onChange = nil

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    deinit {
        stop()
    }
}

@MainActor
final class DocumentStore: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var isDirty: Bool = false
    @Published var status: String = "No file open"
    @Published var folderURL: URL?
    @Published var folderFiles: [FolderScanner.Entry] = []
    @Published var folderTree: [FileTreeNode] = []
    @Published var expandedFolders: Set<URL> = []
    @Published var isScanningFolder: Bool = false
    @Published var sidebarTargetFolder: URL?
    @Published private(set) var workspaceMode: WorkspaceMode = .file
    var onFileOpened: (() -> Void)?

    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelay: Duration = .seconds(1)
    private var externalChangeTask: Task<Void, Never>?
    private var directoryWatchSource: DispatchSourceFileSystemObject?
    private var hasExternalConflict = false
    private let folderWatcher = FolderWatcher()
    private let defaults = UserDefaults.standard

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedOpenTypes
        panel.allowsOtherFileTypes = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFile(at: url)
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing markdown files"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(at: url)
    }

    func openFolder(at url: URL) {
        let standardized = url.standardizedFileURL
        let isNewFolder = folderURL?.standardizedFileURL != standardized

        folderURL = standardized
        workspaceMode = .folder
        RecentItems.addFolder(standardized)
        RecentItems.setLastWorkspaceMode(.folder)
        status = "Folder open"

        if isNewFolder {
            sidebarTargetFolder = standardized
            loadExpansionState(for: standardized)
        }

        rescanFolder(autoOpen: true)
        startWatchingFolder(at: standardized)
    }

    func closeFolder() {
        guard folderURL != nil else { return }
        folderURL = nil
        folderTree = []
        folderFiles = []
        expandedFolders = []
        sidebarTargetFolder = nil
        isScanningFolder = false
        workspaceMode = .file
        RecentItems.setLastWorkspaceMode(.file)
        stopWatchingFolder()
        status = fileURL == nil ? "No file open" : "Folder closed"
    }

    func rescanFolder(autoOpen: Bool = false) {
        guard let folder = folderURL else { return }
        isScanningFolder = true
        Task { [weak self] in
            let entries = await Task.detached(priority: .userInitiated) {
                FolderScanner.scan(folder: folder)
            }.value
            guard let self,
                  self.folderURL?.standardizedFileURL == folder.standardizedFileURL else {
                return
            }
            self.folderFiles = entries
            self.folderTree = FileTreeNode.build(entries: entries, root: folder)
            self.isScanningFolder = false
            if autoOpen {
                self.openInitialFileIfNeeded(in: folder, entries: entries)
            }
            self.expandAncestors(of: self.fileURL)
        }
    }

    private func openInitialFileIfNeeded(in folder: URL, entries: [FolderScanner.Entry]) {
        if let current = fileURL,
           current.isDescendant(of: folder),
           entries.contains(where: {
               $0.url.standardizedFileURL == current.standardizedFileURL
           }) {
            return
        }

        if let stored = defaults.string(forKey: lastFileKey(for: folder)) {
            let storedURL = URL(fileURLWithPath: stored)
            if entries.contains(where: {
                $0.url.standardizedFileURL == storedURL.standardizedFileURL
            }) {
                openFile(at: storedURL)
                return
            }
        }

        for name in ["readme.md", "index.md"] {
            if let entry = entries.first(where: {
                $0.url.lastPathComponent.lowercased() == name
            }) {
                openFile(at: entry.url)
                return
            }
        }

        if let newest = entries.max(by: {
            ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast)
        }) {
            openFile(at: newest.url)
        }
    }

    func openFile(at url: URL) {
        let standardized = url.standardizedFileURL
        do {
            let contents = try String(contentsOf: standardized, encoding: .utf8)

            if let folder = folderURL, !standardized.isDescendant(of: folder) {
                closeFolder()
            }

            text = contents
            fileURL = standardized
            isDirty = false
            hasExternalConflict = false
            status = "Opened"
            RecentItems.addFile(standardized)

            if folderURL == nil {
                workspaceMode = .file
                RecentItems.setLastWorkspaceMode(.file)
            } else if let folder = folderURL, standardized.isDescendant(of: folder) {
                setLastFile(standardized)
                sidebarTargetFolder = standardized.deletingLastPathComponent()
                expandAncestors(of: standardized)
            }

            startWatchingFile(at: standardized)
            onFileOpened?()
        } catch {
            status = "Failed to open: \(error.localizedDescription)"
        }
    }

    func toggleFolder(_ url: URL) {
        if expandedFolders.contains(url) {
            expandedFolders.remove(url)
        } else {
            expandedFolders.insert(url)
        }
        saveExpansionState()
    }

    func collapseAllFolders() {
        expandedFolders.removeAll()
        saveExpansionState()
    }

    func expandAncestors(of fileURL: URL?) {
        guard let fileURL, let folder = folderURL, fileURL.isDescendant(of: folder) else {
            return
        }
        var current = folder
        let directory = fileURL.deletingLastPathComponent()
        let components = directory.pathComponents.dropFirst(folder.pathComponents.count)
        for component in components {
            current.appendPathComponent(component)
            expandedFolders.insert(current)
        }
        saveExpansionState()
    }

    func createFile(in directory: URL? = nil) {
        guard let target = directory ?? sidebarTargetFolder ?? folderURL else {
            status = "Open a folder to create a file"
            return
        }
        let url = uniqueFileURL(in: target, baseName: "Untitled", fileExtension: "md")
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            expandedFolders.insert(target)
            saveExpansionState()
            openFile(at: url)
            rescanFolder()
            status = "Created \(url.lastPathComponent)"
        } catch {
            status = "Create failed: \(error.localizedDescription)"
        }
    }

    func createFolder(named name: String, in directory: URL? = nil) {
        guard let folder = directory ?? sidebarTargetFolder ?? folderURL else {
            status = "Open a folder to create a folder"
            return
        }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !cleaned.isEmpty else { return }
        let target = uniqueDirectoryURL(in: folder, baseName: cleaned)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            expandedFolders.insert(folder)
            expandedFolders.insert(target)
            sidebarTargetFolder = target
            saveExpansionState()
            rescanFolder()
            status = "Created \(target.lastPathComponent)"
        } catch {
            status = "Create failed: \(error.localizedDescription)"
        }
    }

    func renameItem(at url: URL, to name: String) {
        let original = url.standardizedFileURL
        let isDirectory = (try? original.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        var newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !newName.isEmpty else { return }

        if !isDirectory,
           !FolderScanner.markdownExtensions.contains(
               URL(fileURLWithPath: newName).pathExtension.lowercased()
           ) {
            newName += "." + original.pathExtension
        }

        let destination = original.deletingLastPathComponent().appendingPathComponent(newName)
        guard destination.standardizedFileURL != original else { return }

        do {
            try FileManager.default.moveItem(at: original, to: destination)
            remapURLs(from: original, to: destination)
            rescanFolder()
            status = "Renamed"
        } catch {
            status = "Rename failed: \(error.localizedDescription)"
        }
    }

    func duplicateFile(at url: URL) {
        let original = url.standardizedFileURL
        let directory = original.deletingLastPathComponent()
        let base = original.deletingPathExtension().lastPathComponent
        let destination = uniqueFileURL(
            in: directory,
            baseName: "\(base) copy",
            fileExtension: original.pathExtension
        )
        do {
            try FileManager.default.copyItem(at: original, to: destination)
            rescanFolder()
            openFile(at: destination)
            status = "Duplicated \(original.lastPathComponent)"
        } catch {
            status = "Duplicate failed: \(error.localizedDescription)"
        }
    }

    func trashItem(at url: URL) {
        let standardized = url.standardizedFileURL
        if let fileURL, fileURL.isDescendant(of: standardized) {
            stopWatchingFile()
            self.fileURL = nil
            text = ""
            isDirty = false
            hasExternalConflict = false
        }

        if let target = sidebarTargetFolder, target.isDescendant(of: standardized) {
            sidebarTargetFolder = folderURL
        }

        do {
            try FileManager.default.trashItem(at: standardized, resultingItemURL: nil)
            rescanFolder()
            status = "Moved to Trash"
        } catch {
            status = "Move to Trash failed: \(error.localizedDescription)"
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealFolder() {
        guard let folderURL else { return }
        revealInFinder(folderURL)
    }

    func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        status = "Copied path"
    }

    private func uniqueFileURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(fileExtension)")
            counter += 1
        }
        return candidate
    }

    private func uniqueDirectoryURL(in directory: URL, baseName: String) -> URL {
        var candidate = directory.appendingPathComponent(baseName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter)")
            counter += 1
        }
        return candidate
    }

    private func remapURLs(from old: URL, to new: URL) {
        let oldPath = old.standardizedFileURL.path
        let newURL = new.standardizedFileURL

        func remap(_ url: URL) -> URL? {
            let candidate = url.standardizedFileURL
            if candidate.path == oldPath {
                return newURL
            }
            let prefix = oldPath + "/"
            guard candidate.path.hasPrefix(prefix) else { return nil }
            let suffix = String(candidate.path.dropFirst(prefix.count))
            return newURL.appendingPathComponent(suffix)
        }

        if let fileURL, let updated = remap(fileURL) {
            self.fileURL = updated
            startWatchingFile(at: updated)
            RecentItems.addFile(updated)
            setLastFile(updated)
        }

        expandedFolders = Set(expandedFolders.map { remap($0) ?? $0 })

        if let sidebarTargetFolder, let updated = remap(sidebarTargetFolder) {
            self.sidebarTargetFolder = updated
        }

        if let folderURL, let updated = remap(folderURL) {
            self.folderURL = updated
            startWatchingFolder(at: updated)
        }

        saveExpansionState()
    }

    private func lastFileKey(for folder: URL) -> String {
        "lastFileInFolder.\(folder.standardizedFileURL.path)"
    }

    private func expansionKey(for folder: URL) -> String {
        "expandedFolders.\(folder.standardizedFileURL.path)"
    }

    private func setLastFile(_ url: URL) {
        guard let folder = folderURL, url.isDescendant(of: folder) else { return }
        defaults.set(url.standardizedFileURL.path, forKey: lastFileKey(for: folder))
    }

    private func loadExpansionState(for folder: URL) {
        let paths = defaults.stringArray(forKey: expansionKey(for: folder)) ?? []
        expandedFolders = Set(paths.map { URL(fileURLWithPath: $0) })
    }

    private func saveExpansionState() {
        guard let folder = folderURL else { return }
        defaults.set(
            expandedFolders.map { $0.standardizedFileURL.path }.sorted(),
            forKey: expansionKey(for: folder)
        )
    }

    private func startWatchingFolder(at url: URL) {
        stopWatchingFolder()
        folderWatcher.start(url: url) { [weak self] in
            Task { @MainActor [weak self] in
                self?.rescanFolder()
            }
        }
    }

    private func stopWatchingFolder() {
        folderWatcher.stop()
    }
    
    func save() {
        if fileURL == nil && text.isEmpty {
            status = "Nothing to save"
            return
        }
        guard let url = fileURL else {
            saveAs()
            return
        }
        write(to: url)
    }
    
    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedSaveTypes
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
        fileURL = url
        hasExternalConflict = false
        RecentItems.addFile(url)
        if folderURL == nil {
            workspaceMode = .file
            RecentItems.setLastWorkspaceMode(.file)
        } else if let folder = folderURL, url.isDescendant(of: folder) {
            setLastFile(url)
            sidebarTargetFolder = url.deletingLastPathComponent()
            expandAncestors(of: url)
        }
        startWatchingFile(at: url)
    }
    
    private func write(to url: URL) {
        let hadConflict = hasExternalConflict
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            hasExternalConflict = false
            status = hadConflict ? "Saved, overwriting external changes" : "Saved"
        } catch {
            status = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    func textChanged(_ newText: String) {
        text = newText
        isDirty = true
        status = hasExternalConflict ? "Unsaved changes (external change detected)" : "Unsaved changes"
        
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self.autosave()
        }
    }
    
    private func autosave() {
        guard let url = fileURL else { return }
        guard !hasExternalConflict else {
            status = "Autosave paused: external change detected"
            return
        }
        write(to: url)
        status = "Autosaved"
    }

    func reloadFromDisk() {
        guard let url = fileURL else { return }
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            isDirty = false
            hasExternalConflict = false
            status = "Reloaded from disk"
        } catch {
            status = "Failed to reload: \(error.localizedDescription)"
        }
    }

    private func startWatchingFile(at url: URL) {
        stopWatchingFile()
        let directory = url.deletingLastPathComponent()
        let fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleExternalChangeCheck()
            }
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        directoryWatchSource = source
        source.resume()
    }

    private func stopWatchingFile() {
        externalChangeTask?.cancel()
        externalChangeTask = nil
        directoryWatchSource?.cancel()
        directoryWatchSource = nil
    }

    private func scheduleExternalChangeCheck() {
        externalChangeTask?.cancel()
        externalChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.checkForExternalChange()
        }
    }

    private func checkForExternalChange() {
        guard let url = fileURL else { return }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            status = "File removed or unreadable"
            return
        }
        guard contents != text else {
            if hasExternalConflict {
                hasExternalConflict = false
                status = "External changes match local content"
            }
            return
        }
        if isDirty || hasExternalConflict {
            hasExternalConflict = true
            status = "External change detected"
        } else {
            text = contents
            status = "Reloaded external changes"
        }
    }

    deinit {
        directoryWatchSource?.cancel()
        folderWatcher.stop()
    }
    
    private var allowedOpenTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let mdType = UTType(filenameExtension: "md") {
            types.append(mdType)
        }
        return types
    }
    
    private var allowedSaveTypes: [UTType] {
        if let mdType = UTType(filenameExtension: "md") {
            return [mdType]
        }
        return [.plainText]
    }
}
