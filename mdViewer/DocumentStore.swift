import Foundation
import AppKit
import Darwin
import UniformTypeIdentifiers

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

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: filesKey)
        defaults.removeObject(forKey: foldersKey)
        defaults.removeObject(forKey: lastFileKey)
        defaults.removeObject(forKey: lastFolderKey)
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
            entries.append(Entry(url: url, relativePath: relativePath))
        }

        return entries.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
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
    @Published var isScanningFolder: Bool = false
    var onFileOpened: (() -> Void)?

    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelay: Duration = .seconds(1)
    private var externalChangeTask: Task<Void, Never>?
    private var directoryWatchSource: DispatchSourceFileSystemObject?
    private var hasExternalConflict = false

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
        folderURL = url
        status = "Folder open"
        RecentItems.addFolder(url)
        rescanFolder()
    }

    func rescanFolder() {
        guard let folder = folderURL else { return }
        isScanningFolder = true
        Task { [weak self] in
            let entries = await Task.detached(priority: .userInitiated) {
                FolderScanner.scan(folder: folder)
            }.value
            guard let self, self.folderURL == folder else { return }
            self.folderFiles = entries
            self.isScanningFolder = false
        }
    }
    
    func openFile(at url: URL) {
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            isDirty = false
            hasExternalConflict = false
            status = "Opened"
            RecentItems.addFile(url)
            startWatchingFile(at: url)
            onFileOpened?()
        } catch {
            status = "Failed to open: \(error.localizedDescription)"
        }
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
