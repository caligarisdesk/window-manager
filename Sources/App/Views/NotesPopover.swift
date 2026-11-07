import SwiftUI

/// Lists a session's notes and adds new ones.
struct NotesPopover: View {
    let title: String
    let notes: [Note]
    var onAdd: (String) -> Void
    var onDelete: (UUID) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes").font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)

            if !notes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notes.reversed()) { n in
                            HStack(alignment: .top, spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                                    Text(n.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button { onDelete(n.id) } label: {
                                    Image(systemName: "trash").font(.system(size: 10))
                                }
                                .buttonStyle(.borderless).help("Delete note")
                            }
                            .padding(8)
                            .background(Color(red: 1.0, green: 0.95, blue: 0.72).opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundColor(Color(red: 0.2, green: 0.17, blue: 0.05))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            TextEditor(text: $draft)
                .font(.system(size: 12))
                .focused($focused)
                .frame(height: 70)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            HStack {
                Text("⌘↩ to save").font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button("Add note") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { focused = true }
    }

    private func save() {
        onAdd(draft)
        draft = ""
    }
}
