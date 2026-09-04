import SwiftUI

struct FolderSidebar: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            fileList
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(store.folderURL?.lastPathComponent ?? "Folder")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: { store.rescanFolder() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rescan folder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var fileList: some View {
        List(store.folderFiles) { entry in
            row(for: entry)
        }
        .listStyle(.sidebar)
        .overlay {
            if store.folderFiles.isEmpty {
                Text(store.isScanningFolder ? "Scanning…" : "No markdown files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func row(for entry: FolderScanner.Entry) -> some View {
        let isActive = store.fileURL?.standardizedFileURL == entry.url.standardizedFileURL
        let fileName = entry.url.lastPathComponent

        Button(action: { store.openFile(at: entry.url) }) {
            VStack(alignment: .leading, spacing: 2) {
                Text((fileName as NSString).deletingPathExtension)
                    .lineLimit(1)
                    .fontWeight(isActive ? .semibold : .regular)
                if entry.relativePath != fileName {
                    Text(entry.relativePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        )
    }
}
