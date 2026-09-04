import SwiftUI

struct Toolbar: View {
    @Binding var mode: ViewMode
    @Binding var isSidebarVisible: Bool
    @ObservedObject var store: DocumentStore

    var body: some View {
        HStack(spacing: 10) {
            if store.folderURL != nil {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isSidebarVisible.toggle() } }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Toggle Sidebar (⌘\\)")
            }

            Divider()
                .frame(height: 16)

            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { mode = mode == .preview ? .edit : .preview } }) {
                Label(mode == .preview ? "Edit" : "Preview", systemImage: mode == .preview ? "pencil" : "eye")
                    .font(.callout)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .help("Toggle Edit/Preview (⌘E)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
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

            if !store.text.isEmpty {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(DocumentStats.summary(for: store.text))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("·")
                .foregroundStyle(.tertiary)

            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .frame(maxWidth: 460)
    }
}
