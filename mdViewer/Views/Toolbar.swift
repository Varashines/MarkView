import SwiftUI

struct Toolbar: View {
    @Binding var mode: ViewMode
    @ObservedObject var store: DocumentStore
    var onExportPDF: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { mode = mode == .preview ? .edit : .preview } }) {
                Label(mode == .preview ? "Edit" : "Preview", systemImage: mode == .preview ? "pencil" : "eye")
            }
            .keyboardShortcut("e", modifiers: .command)
            
            Spacer()
            
            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            Button("Open", action: { store.openFile() })
                .keyboardShortcut("o", modifiers: .command)
            
            Button("Save", action: { store.save() })
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.fileURL == nil && store.text.isEmpty)
            
            Button("Export PDF", action: onExportPDF)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(store.text.isEmpty)
        }
    }
}
