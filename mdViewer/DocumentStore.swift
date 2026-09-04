import Foundation
import AppKit
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
        return "\(words) words · \(reading) read"
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
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
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
        status = "Folder: \(url.lastPathComponent)"
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
            status = "Opened \(url.lastPathComponent)"
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
    }
    
    private func write(to url: URL) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            status = "Saved \(url.lastPathComponent)"
        } catch {
            status = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    func textChanged(_ newText: String) {
        text = newText
        isDirty = true
        status = "Unsaved changes"
        
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
        write(to: url)
        status = "Autosaved \(url.lastPathComponent)"
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
