import SwiftUI

struct DashboardView: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: Theme { Theme(scheme) }
    @EnvironmentObject var store: DeckStore

    private let columns = [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 14)]

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22).padding(.top, 34).padding(.bottom, 12)
                filterBar
                    .padding(.horizontal, 22).padding(.bottom, 12)
                Rectangle().fill(theme.border).frame(height: 1)
                content
            }
        }
        .foregroundColor(theme.text)
        .frame(minWidth: 520, minHeight: 400)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Shelf").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("\(store.sessions.count) terminals · \(store.count(.needsYou)) need you · \(store.count(.working)) working")
                    .font(.system(size: 12)).foregroundColor(theme.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                statBlock(Fmt.tokens(store.totalTokens), "tokens")
                statBlock(Fmt.cost(store.totalCost), "est. cost")
                Button { store.toggleTile() } label: {
                    Label(store.tiled ? "Restore windows" : "Tile windows",
                          systemImage: store.tiled ? "arrow.uturn.backward" : "square.grid.3x3.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(store.tiled ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.3),
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Arrange the Terminal windows of the cards shown below into a grid")
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                        .padding(7).background(theme.chip, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).help("Refresh now")
            }
        }
    }

    private func statBlock(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(theme.secondary).textCase(.uppercase)
        }
        .padding(.trailing, 6)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(DeckFilter.allCases) { f in
                let selected = store.filter == f
                Button { store.filter = f } label: {
                    HStack(spacing: 5) {
                        Text(f.rawValue)
                        Text("\(store.count(f))").foregroundColor(selected ? theme.text.opacity(0.8) : theme.secondary).monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(selected ? theme.chipSelected : theme.chip, in: Capsule())
                    .overlay(Capsule().strokeBorder(selected ? theme.borderStrong : .clear))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Toggle(isOn: $store.aiSummariesEnabled) {
                Label("AI summaries", systemImage: "sparkles").font(.system(size: 11))
            }
            .toggleStyle(.switch).controlSize(.mini)
            .help("Generate Done/Next lines with Claude Haiku when sessions go idle")
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundColor(theme.secondary).font(.system(size: 11))
                TextField("Search", text: $store.search).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .frame(width: 200)
            .background(theme.chip, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    @ViewBuilder private var content: some View {
        let items = store.visible
        if store.lastRefresh == nil {
            Spacer(); ProgressView().controlSize(.small); Spacer()
        } else if items.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "terminal").font(.system(size: 34)).foregroundColor(theme.secondary)
                Text(store.sessions.isEmpty ? "No Terminal windows found" : "Nothing matches this filter")
                    .foregroundColor(theme.secondary)
                if store.sessions.isEmpty {
                    Text("Open Terminal.app, and allow Shelf to control it under System Settings → Privacy & Security → Automation.")
                        .font(.system(size: 11)).foregroundColor(theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                }
            }
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(items) { s in
                        SessionCard(session: s,
                                    onExpand: { store.expand(s) },
                                    onFocus: { store.focus(s) },
                                    onResummarize: { store.resummarize(s) },
                                    onAddNote: { store.addNote($0, to: s.noteKey) },
                                    onDeleteNote: { store.deleteNote($0, from: s.noteKey) })
                    }
                }
                .padding(22)
                .animation(.easeInOut(duration: 0.25), value: items.map(\.id))
            }
        }
    }
}
