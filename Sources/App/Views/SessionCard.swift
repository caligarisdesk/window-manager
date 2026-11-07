import SwiftUI

struct SessionCard: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: Theme { Theme(scheme) }
    let session: TerminalSession
    var onExpand: () -> Void
    var onFocus: () -> Void
    var onResummarize: () -> Void
    var onAddNote: (String) -> Void
    var onDeleteNote: (UUID) -> Void

    @State private var hover = false
    @State private var angle: Double = 0          // 0 = front, 180 = back
    @State private var flipTask: DispatchWorkItem?
    @State private var showNotes = false

    private let radius: CGFloat = 14

    var body: some View {
        ZStack {
            face(frontContent)
                .modifier(FlipEffect(angle: angle, isBack: false))
            // The back is laid out on top of an invisible copy of the front so both faces are the same size.
            face(frontContent.hidden().overlay(alignment: .topLeading) { backContent })
                .modifier(FlipEffect(angle: angle, isBack: true))
        }
        .overlay(alignment: .topTrailing) { noteButton }
        .scaleEffect(hover ? 1.012 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hover)
        .contentShape(RoundedRectangle(cornerRadius: radius))
        .onHover(perform: hoverChanged)
        .onTapGesture(perform: onExpand)
        .contextMenu {
            Button("Expand") { onExpand() }
            Button("Bring to front (keep size)") { onFocus() }
            Button("Add note…") { showNotes = true }
            if session.isClaude { Button("Re-summarize with AI") { onResummarize() } }
            Divider()
            if let cwd = session.cwd {
                Button("Copy path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cwd, forType: .string)
                }
                Button("Reveal in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd) }
            }
        }
    }

    // MARK: - Hover / flip

    private func hoverChanged(_ inside: Bool) {
        hover = inside
        flipTask?.cancel()
        if inside {
            // Short delay so sweeping the mouse across the grid doesn't flip every card.
            let task = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.45)) { angle = 180 }
            }
            flipTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
        } else if !showNotes {
            withAnimation(.easeInOut(duration: 0.4)) { angle = 0 }
        }
    }

    private var noteButton: some View {
        Button { showNotes = true } label: {
            ZStack {
                Circle().fill(Color.accentColor)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Add a note to this session")
        .offset(x: 8, y: -8)
        .opacity(hover || showNotes ? 1 : 0)
        .scaleEffect(hover || showNotes ? 1 : 0.6)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
        .popover(isPresented: $showNotes, arrowEdge: .trailing) {
            NotesPopover(title: session.title, notes: session.notes, onAdd: onAddNote, onDelete: onDeleteNote)
        }
        .onChange(of: showNotes) { open in
            if !open && !hover { withAnimation(.easeInOut(duration: 0.4)) { angle = 0 } }
        }
    }

    // MARK: - Card chrome

    private func face<V: View>(_ content: V) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(hover ? theme.cardHover : theme.card)
                    LinearGradient(colors: [session.accent.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(session.status.color).frame(width: 3).padding(.vertical, 16)
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(hover ? session.accent.opacity(0.55) : theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(hover ? theme.shadow * 2 : theme.shadow), radius: hover ? 14 : 6, y: hover ? 8 : 3)
    }

    // MARK: - Front

    private var frontContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            bodyContent
            if let note = session.notes.last { noteStrip(note) }
            Spacer(minLength: 0)
            footer
            if let c = session.claude { metrics(c) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(status: session.status).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(theme.text)
                HStack(spacing: 6) {
                    Text(session.status.label.uppercased())
                        .font(.system(size: 9, weight: .bold)).tracking(0.6)
                        .foregroundColor(session.status.color)
                    if session.isClaude {
                        Text("CLAUDE").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundColor(theme.secondary)
                    }
                    if session.miniaturized {
                        Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 9)).foregroundColor(theme.secondary)
                    }
                }
            }
            Spacer()
            Text(Fmt.ago(session.lastActivity))
                .font(.system(size: 10, weight: .medium)).foregroundColor(theme.secondary)
                .padding(.trailing, 14) // room for the hover "+" button
        }
    }

    @ViewBuilder private var bodyContent: some View {
        if let c = session.claude {
            if let s = session.summary, s.hasDoneOrNext {
                VStack(alignment: .leading, spacing: 5) {
                    summaryRow(icon: "checkmark.circle.fill", color: .green, text: s.done)
                    summaryRow(icon: "arrow.right.circle.fill", color: session.status == .needsYou ? .orange : .blue, text: s.next)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.inset, in: RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .topTrailing) {
                    Text("AI").font(.system(size: 8, weight: .heavy)).foregroundColor(theme.secondary).padding(5)
                }
            } else if let a = c.lastAssistantText {
                Text(a).font(.system(size: 11.5)).foregroundColor(theme.text.opacity(0.8)).lineLimit(3)
            }
            if let p = c.lastPrompt {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "person.fill").font(.system(size: 9)).foregroundColor(theme.secondary).padding(.top, 2)
                    Text(p).font(.system(size: 11)).foregroundColor(theme.secondary).lineLimit(2)
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: session.foreground == nil ? "terminal" : "play.fill")
                    .font(.system(size: 11)).foregroundColor(session.status.color)
                Text(session.foreground ?? "idle shell")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(session.foreground == nil ? theme.secondary : theme.text)
                    .lineLimit(2)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.inset, in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private func noteStrip(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "note.text").font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(red: 0.62, green: 0.45, blue: 0.0)).padding(.top, 1)
            Text(note.text).font(.system(size: 11.5)).foregroundColor(Color(red: 0.25, green: 0.2, blue: 0.05)).lineLimit(2)
            Spacer(minLength: 0)
            if session.notes.count > 1 {
                Text("+\(session.notes.count - 1)").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 0.55, green: 0.42, blue: 0.05))
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color(red: 1.0, green: 0.93, blue: 0.62), in: RoundedRectangle(cornerRadius: 7))
    }

    private func summaryRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color).padding(.top, 1)
            Text(text).font(.system(size: 12)).foregroundColor(theme.text.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 10)).foregroundColor(session.accent)
            Text(session.shortPath()).font(.system(size: 11, design: .monospaced)).foregroundColor(theme.secondary)
                .lineLimit(1).truncationMode(.head)
            Spacer(minLength: 4)
            if let g = session.git {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(g.branch).lineLimit(1)
                    if g.dirty > 0 { Text("±\(g.dirty)").foregroundColor(.orange) }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(theme.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(theme.chip, in: Capsule())
            }
        }
    }

    private func metrics(_ c: ClaudeStats) -> some View {
        HStack(spacing: 6) {
            MetricPill(icon: "circle.hexagongrid.fill", value: Fmt.tokens(c.totalTokens),
                       help: "Tokens — in \(Fmt.tokens(c.inputTokens)), out \(Fmt.tokens(c.outputTokens)), cache read \(Fmt.tokens(c.cacheReadTokens)), cache write \(Fmt.tokens(c.cacheWriteTokens))",
                       tint: .purple)
            MetricPill(icon: "dollarsign.circle.fill", value: Fmt.cost(c.costUSD),
                       help: "Estimated API-equivalent cost (\(c.model ?? "unknown model"))", tint: .green)
            MetricPill(icon: "bubble.left.and.bubble.right.fill", value: "\(c.userTurns)",
                       help: "\(c.userTurns) prompts · \(c.assistantTurns) model calls", tint: .blue)
            MetricPill(icon: "clock.fill", value: Fmt.duration(from: c.firstActivity, to: c.lastActivity),
                       help: "Session span", tint: .gray)
            Spacer(minLength: 0)
            ContextGauge(fill: c.contextFill, tokens: c.contextTokens, window: c.contextWindow)
        }
    }

    // MARK: - Back

    private var backContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: session.isClaude ? "text.bubble.fill" : "terminal.fill")
                    .font(.system(size: 12)).foregroundColor(session.accent)
                Text(session.isClaude ? "Claude's last response" : "Shell")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(theme.text)
                Spacer()
                Text(Fmt.ago(session.lastActivity)).font(.system(size: 10, weight: .medium)).foregroundColor(theme.secondary)
                    .padding(.trailing, 14)
            }
            if let c = session.claude {
                if let last = session.summary?.last, !last.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 10)).foregroundColor(.purple).padding(.top, 2)
                        Text(last).font(.system(size: 12.5)).foregroundColor(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.inset, in: RoundedRectangle(cornerRadius: 9))
                }
                if let raw = c.lastAssistantText {
                    Text(raw)
                        .font(.system(size: 11.5)).foregroundColor(theme.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                } else {
                    Text("No response yet.").font(.system(size: 12)).foregroundColor(theme.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.foreground ?? "idle shell").font(.system(size: 12, design: .monospaced)).foregroundColor(theme.text)
                    Text(session.shortPath()).font(.system(size: 11, design: .monospaced)).foregroundColor(theme.secondary)
                    Text(session.tty).font(.system(size: 11, design: .monospaced)).foregroundColor(theme.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .clipped()
    }
}
