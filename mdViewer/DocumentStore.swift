import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var isDirty: Bool = false
    @Published var status: String = "No file open"
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
