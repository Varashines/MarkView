import SwiftUI
import Darwin

@main
struct mdViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(RecentItems.filesKey) private var recentFilesData: Data = Data()
    @AppStorage(RecentItems.foldersKey) private var recentFoldersData: Data = Data()

    init() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--export-html"),
              flag + 2 < arguments.count else {
            return
        }
        let inputURL = URL(fileURLWithPath: arguments[flag + 1])
        let outputURL = URL(fileURLWithPath: arguments[flag + 2])
        guard let markdown = try? String(contentsOf: inputURL, encoding: .utf8) else {
            exit(1)
        }
        let html = MarkdownConverter.exportedHTML(
            from: markdown,
            baseURL: inputURL.deletingLastPathComponent()
        )
        do {
            try html.write(to: outputURL, atomically: true, encoding: .utf8)
            exit(0)
        } catch {
            exit(1)
        }
    }

    private var recentFiles: [URL] {
        (try? JSONDecoder().decode([URL].self, from: recentFilesData)) ?? []
    }

    private var recentFolders: [URL] {
        (try? JSONDecoder().decode([URL].self, from: recentFoldersData)) ?? []
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    postOpen(url)
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") { post(.newFileRequested) }
                    .keyboardShortcut("n")
            }

            CommandGroup(after: .newItem) {
                Button("Open…") { post(.openFileRequested) }
                    .keyboardShortcut("o")
                Button("Open Folder…") { post(.openFolderRequested) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Close Folder") { post(.closeFolderRequested) }
                Divider()
                Button("Save") { post(.saveRequested) }
                    .keyboardShortcut("s")
                Button("Reload from Disk") { post(.reloadFromDiskRequested) }
                    .keyboardShortcut("r")
                Button("Export as PDF…") { post(.exportPDFRequested) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Export as Single-Page PDF…") { post(.exportSinglePagePDFRequested) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export as HTML…") { post(.exportHTMLRequested) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Divider()
                Menu("Open Recent") {
                    if recentFiles.isEmpty && recentFolders.isEmpty {
                        Text("No Recent Items")
                    } else {
                        ForEach(recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                NotificationCenter.default.post(name: .openFileURL, object: url)
                            }
                            .help(url.deletingLastPathComponent().path)
                        }
                        if !recentFolders.isEmpty {
                            Divider()
                        }
                        ForEach(recentFolders, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                NotificationCenter.default.post(name: .openFolderURL, object: url)
                            }
                            .help(url.path)
                        }
                        Divider()
                        Button("Clear Menu") {
                            RecentItems.clear()
                        }
                    }
                }
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Markdown Sidebar") { post(.toggleSidebarRequested) }
                    .keyboardShortcut("\\", modifiers: .command)
                Button("Toggle Edit/Preview") { post(.toggleModeRequested) }
                    .keyboardShortcut("e")
                Button("Toggle Split View") { post(.toggleSplitRequested) }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Divider()
                Button("Zoom In") { post(.zoomInRequested) }
                    .keyboardShortcut("+")
                Button("Zoom Out") { post(.zoomOutRequested) }
                    .keyboardShortcut("-")
                Button("Actual Size") { post(.zoomResetRequested) }
                    .keyboardShortcut("0")
            }

            CommandGroup(after: .textEditing) {
                Button("Find…") { post(.findRequested) }
                    .keyboardShortcut("f")
                Button("Search Files…") { post(.focusSidebarSearchRequested) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}

private func post(_ name: Notification.Name) {
    NotificationCenter.default.post(name: name, object: nil)
}

private func postOpen(_ url: URL) {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
       isDirectory.boolValue {
        NotificationCenter.default.post(name: .openFolderURL, object: url)
    } else {
        NotificationCenter.default.post(name: .openFileURL, object: url)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var pendingOpenURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        AppDelegate.pendingOpenURLs.append(contentsOf: urls)
        for url in urls {
            postOpen(url)
        }
    }

    static func markHandled(_ url: URL) {
        pendingOpenURLs.removeAll {
            $0.standardizedFileURL == url.standardizedFileURL
        }
    }

    static func consumePendingOpenURLs() -> [URL] {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }
}

extension Notification.Name {
    static let openFileURL = Notification.Name("openFileURL")
    static let openFolderURL = Notification.Name("openFolderURL")
    static let openFileRequested = Notification.Name("openFileRequested")
    static let openFolderRequested = Notification.Name("openFolderRequested")
    static let newFileRequested = Notification.Name("newFileRequested")
    static let closeFolderRequested = Notification.Name("closeFolderRequested")
    static let focusSidebarSearchRequested = Notification.Name("focusSidebarSearchRequested")
    static let saveRequested = Notification.Name("saveRequested")
    static let reloadFromDiskRequested = Notification.Name("reloadFromDiskRequested")
    static let exportPDFRequested = Notification.Name("exportPDFRequested")
    static let exportSinglePagePDFRequested = Notification.Name("exportSinglePagePDFRequested")
    static let exportHTMLRequested = Notification.Name("exportHTMLRequested")
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
    static let toggleModeRequested = Notification.Name("toggleModeRequested")
    static let toggleSplitRequested = Notification.Name("toggleSplitRequested")
    static let findRequested = Notification.Name("findRequested")
    static let zoomInRequested = Notification.Name("zoomInRequested")
    static let zoomOutRequested = Notification.Name("zoomOutRequested")
    static let zoomResetRequested = Notification.Name("zoomResetRequested")
    static let performEditorFind = Notification.Name("performEditorFind")
}
