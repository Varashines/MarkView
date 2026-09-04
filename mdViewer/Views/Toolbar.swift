import SwiftUI

struct StatusBar: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        HStack(spacing: 6) {
            if let folderName = store.folderURL?.lastPathComponent {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(folderName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                    .foregroundStyle(.tertiary)
            }

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
