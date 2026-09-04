import SwiftUI

struct Toolbar: View {
    @Binding var mode: ViewMode
    @Binding var isSidebarVisible: Bool
    @ObservedObject var store: DocumentStore
    var onExportPDF: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { mode = mode == .preview ? .edit : .preview } }) {
                Label(mode == .preview ? "Edit" : "Preview", systemImage: mode == .preview ? "pencil" : "eye")
            }
            .keyboardShortcut("e", modifiers: .command)

            if store.folderURL != nil {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isSidebarVisible.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .keyboardShortcut("\\", modifiers: .command)
            }

            Spacer()
            
            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            Button("Open", action: { store.openFile() })
                .keyboardShortcut("o", modifiers: .command)

            Button("Open Folder", action: { store.openFolder() })
                .keyboardShortcut("o", modifiers: [.command, .shift])
            
            Button("Save", action: { store.save() })
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.fileURL == nil && store.text.isEmpty)
            
            Button("Export PDF", action: onExportPDF)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(store.text.isEmpty)
        }
    }
}
