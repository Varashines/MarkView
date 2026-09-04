import SwiftUI

@main
struct mdViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
        .windowToolbarStyle(.unified(showsTitle: true))
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
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Markdown Sidebar") { post(.toggleSidebarRequested) }
                    .keyboardShortcut("\\", modifiers: .command)
                Button("Toggle Edit/Preview") { post(.toggleModeRequested) }
                    .keyboardShortcut("e")
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
    static let openFileRequested = Notification.Name("openFileRequested")
    static let openFolderRequested = Notification.Name("openFolderRequested")
    static let saveRequested = Notification.Name("saveRequested")
    static let exportPDFRequested = Notification.Name("exportPDFRequested")
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
    static let toggleModeRequested = Notification.Name("toggleModeRequested")
    static let findRequested = Notification.Name("findRequested")
    static let performEditorFind = Notification.Name("performEditorFind")
}
