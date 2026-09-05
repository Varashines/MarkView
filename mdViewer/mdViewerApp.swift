import SwiftUI

@main
struct mdViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(RecentItems.filesKey) private var recentFilesData: Data = Data()
    @AppStorage(RecentItems.foldersKey) private var recentFoldersData: Data = Data()

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
                    NotificationCenter.default.post(
                        name: .openFileURL,
                        object: url
                    )
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .newItem) {
                Button("Open…") { post(.openFileRequested) }
                    .keyboardShortcut("o")
                Button("Open Folder…") { post(.openFolderRequested) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Save") { post(.saveRequested) }
                    .keyboardShortcut("s")
                Button("Export as PDF…") { post(.exportPDFRequested) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Export as Single-Page PDF…") { post(.exportSinglePagePDFRequested) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
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
            }
        }
    }
}

private func post(_ name: Notification.Name) {
    NotificationCenter.default.post(name: name, object: nil)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(
                name: .openFileURL,
                object: url
            )
        }
    }
}

extension Notification.Name {
    static let openFileURL = Notification.Name("openFileURL")
    static let openFolderURL = Notification.Name("openFolderURL")
    static let openFileRequested = Notification.Name("openFileRequested")
    static let openFolderRequested = Notification.Name("openFolderRequested")
    static let saveRequested = Notification.Name("saveRequested")
    static let exportPDFRequested = Notification.Name("exportPDFRequested")
    static let exportSinglePagePDFRequested = Notification.Name("exportSinglePagePDFRequested")
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
    static let toggleModeRequested = Notification.Name("toggleModeRequested")
    static let findRequested = Notification.Name("findRequested")
    static let zoomInRequested = Notification.Name("zoomInRequested")
    static let zoomOutRequested = Notification.Name("zoomOutRequested")
    static let zoomResetRequested = Notification.Name("zoomResetRequested")
    static let performEditorFind = Notification.Name("performEditorFind")
}
