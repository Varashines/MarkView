import SwiftUI

struct Toolbar: View {
    @Binding var mode: ViewMode
    @Binding var isSidebarVisible: Bool
    @ObservedObject var store: DocumentStore

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { mode = mode == .preview ? .edit : .preview } }) {
                Label(mode == .preview ? "Edit" : "Preview", systemImage: mode == .preview ? "pencil" : "eye")
            }

            if store.folderURL != nil {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isSidebarVisible.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                        .labelStyle(.iconOnly)
                }
                .help("Toggle Sidebar (⌘\\)")
            }

            Spacer()
        }
    }
}

struct StatusBar: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(store.fileURL?.lastPathComponent ?? "Untitled")
                .font(.caption)
                .lineLimit(1)

            if let folderName = store.folderURL?.lastPathComponent {
                Text("· \(folderName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if !store.text.isEmpty {
                Text(DocumentStats.summary(for: store.text))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
            }

            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
