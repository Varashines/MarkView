import SwiftUI

@main
struct mdViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage(RecentItems.filesKey) private var recentFilesData: Data = Data()
    @AppStorage(RecentItems.foldersKey) private var recentFoldersData: Data = Data()

    private var colorSchemeOverride: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
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
                .preferredColorScheme(colorSchemeOverride)
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

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("editorFontSize") private var editorFontSize = 13.0

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceMode) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.radioGroup)

            HStack {
                Text("Editor font size")
                Slider(value: $editorFontSize, in: 10...22, step: 1)
                    .labelsHidden()
                Text("\(Int(editorFontSize)) pt")
                    .monospacedDigit()
                    .frame(width: 44)
            }
        }
        .padding(20)
        .frame(width: 340)
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
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
    static let toggleModeRequested = Notification.Name("toggleModeRequested")
    static let findRequested = Notification.Name("findRequested")
    static let zoomInRequested = Notification.Name("zoomInRequested")
    static let zoomOutRequested = Notification.Name("zoomOutRequested")
    static let zoomResetRequested = Notification.Name("zoomResetRequested")
    static let performEditorFind = Notification.Name("performEditorFind")
}
