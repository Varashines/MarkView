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

            if store.folderURL != nil {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isSidebarVisible.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }

            Spacer()

            if !store.text.isEmpty {
                Text(DocumentStats.summary(for: store.text))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Word count and estimated reading time")
            }

            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("Open", action: { store.openFile() })

            Button("Open Folder", action: { store.openFolder() })

            Button("Save", action: { store.save() })
                .disabled(store.fileURL == nil && store.text.isEmpty)

            Button("Export PDF", action: onExportPDF)
                .disabled(store.text.isEmpty)
        }
    }
}
