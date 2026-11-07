import Foundation

/// `Shelf --dump`: prints what the dashboard would show, for debugging without the UI.
enum Dump {
    static func run() {
        let tabs = TerminalClient().snapshot()
        let store = ClaudeSessionStore()
        let sessions = SessionAssembler(claudeStats: store.stats(for:), gitStatus: { _ in nil }, summary: { _ in nil })
            .assemble(tabs: tabs, processes: ProcessScanner().scan(ttys: tabs.map(\.tty)), sessionFiles: store.sessionFiles())
        print("terminals: \(sessions.count)")
        for s in sessions {
            print("— [\(s.status.label)] \(s.title)  window \(s.windowId) tab \(s.tabIndex) \(s.tty)")
            print("  cwd: \(s.cwd ?? "?")  foreground: \(s.foreground ?? "-")")
            guard let c = s.claude else { continue }
            print("  model: \(c.model ?? "-")  tokens: \(Fmt.tokens(c.totalTokens))  cost: \(Fmt.cost(c.costUSD))  context: \(Int(c.contextFill * 100))%")
            print("  last prompt: \(c.lastPrompt?.prefix(80) ?? "-")")
        }
    }
}
