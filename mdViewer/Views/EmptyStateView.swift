import SwiftUI

struct EmptyStateView: View {
    var onOpenFile: () -> Void
    var onOpenFolder: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("No document open")
                    .font(.title3.weight(.medium))
                Text("Drag a Markdown file here, or use the buttons below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Open File…", action: onOpenFile)
                Button("Open Folder…", action: onOpenFolder)
            }
            .buttonStyle(.bordered)

            VStack(spacing: 4) {
                hint("⌘O", "Open file")
                hint("⇧⌘O", "Open folder")
                hint("⌘E", "Toggle edit/preview")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(_ shortcut: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(shortcut)
                .font(.caption.monospaced())
            Text(label)
        }
    }
}
