import SwiftUI

struct FolderSidebar: View {
    @ObservedObject var store: DocumentStore
    @State private var searchText = ""
    @State private var searchResults: [FolderSearch.Hit] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var renamingEntry: FolderScanner.Entry?
    @State private var renameText = ""
    @State private var showRenameAlert = false

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)
            content
        }
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { performRename() }
        } message: {
            Text("Enter a new name for the file")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if isFiltering {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.06))
        )
    }

    @ViewBuilder
    private var content: some View {
        if isFiltering {
            searchResultsList
        } else {
            fileList
        }
    }

    private var fileList: some View {
        List(selection: Binding(
            get: { store.fileURL },
            set: { url in
                if let url {
                    store.openFile(at: url)
                }
            }
        )) {
            Section(header: sectionHeader) {
                ForEach(store.folderFiles) { entry in
                    row(for: entry)
                        .tag(entry.url)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.folderFiles.isEmpty {
                Text(store.isScanningFolder ? "Scanning…" : "No Markdown files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sectionHeader: some View {
        Text(store.folderURL?.lastPathComponent ?? "Folder")
            .contextMenu {
                Button("Rescan Folder") {
                    store.rescanFolder()
                }
            }
    }

    private var searchResultsList: some View {
        List {
            Section(header: Text("Results")) {
                ForEach(searchResults) { hit in
                    searchRow(for: hit)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if !isSearching && searchResults.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(for entry: FolderScanner.Entry) -> some View {
        let fileName = entry.url.lastPathComponent

        return HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text((fileName as NSString).deletingPathExtension)
                    .lineLimit(1)
                if entry.relativePath != fileName {
                    Text(entry.relativePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        .contextMenu {
            Button("Rename…") {
                renamingEntry = entry
                renameText = fileName
                showRenameAlert = true
            }
            Button("Move to Trash", role: .destructive) {
                moveToTrash(entry)
            }
        }
    }

    private func searchRow(for hit: FolderSearch.Hit) -> some View {
        Button(action: { store.openFile(at: hit.url) }) {
            HStack(spacing: 6) {
                Image(systemName: "text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text((hit.url.lastPathComponent as NSString).deletingPathExtension)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("L\(hit.line)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                        Text(hit.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func performRename() {
        guard let entry = renamingEntry else { return }
        var name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        name = name.replacingOccurrences(of: "/", with: "-")
        if !FolderScanner.markdownExtensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased()) {
            name += "." + entry.url.pathExtension
        }
        let newURL = entry.url.deletingLastPathComponent().appendingPathComponent(name)
        guard newURL != entry.url else { return }
        do {
            try FileManager.default.moveItem(at: entry.url, to: newURL)
            if store.fileURL == entry.url {
                store.fileURL = newURL
            }
            store.rescanFolder()
            store.status = "Renamed"
        } catch {
            store.status = "Rename failed: \(error.localizedDescription)"
        }
    }

    private func moveToTrash(_ entry: FolderScanner.Entry) {
        do {
            try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
            if store.fileURL == entry.url {
                store.fileURL = nil
                store.text = ""
                store.status = "Moved to Trash"
            }
            store.rescanFolder()
        } catch {
            store.status = "Move to Trash failed: \(error.localizedDescription)"
        }
    }
}
