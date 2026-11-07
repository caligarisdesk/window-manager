import Foundation

/// Rules for classifying, combining, sorting and filtering sessions.
enum Triage {
    /// Claude sessions idle longer than this count as "Idle" rather than "Needs you".
    static let defaultStaleAfter: TimeInterval = 3 * 3600

    static func status(of claude: ClaudeStats?, now: Date, staleAfter: TimeInterval = defaultStaleAfter) -> SessionStatus {
        guard let claude else { return .shell }
        if claude.isBusy { return .working }
        let last = claude.lastActivity ?? claude.statusUpdatedAt ?? .distantPast
        return now.timeIntervalSince(last) > staleAfter ? .idle : .needsYou
    }

    /// Needs-you first, then working, idle, shells; most recently active first within each group.
    static func sorted(_ sessions: [TerminalSession]) -> [TerminalSession] {
        sessions.sorted {
            if $0.status != $1.status { return $0.status < $1.status }
            return ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
        }
    }

    /// Case-insensitive match against everything a card shows.
    static func matches(_ s: TerminalSession, search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        var haystack = [s.title, s.cwd ?? "", s.claude?.lastPrompt ?? "", s.foreground ?? "", s.summary?.next ?? ""]
        haystack += s.notes.map(\.text)
        return haystack.joined(separator: " ").lowercased().contains(query)
    }

    static func visible(_ sessions: [TerminalSession], filter: DeckFilter, search: String) -> [TerminalSession] {
        sessions.filter { filter.includes($0) && matches($0, search: search) }
    }

    /// One session per window, in order, so tiling moves each window once.
    static func distinctWindows(_ sessions: [TerminalSession]) -> [TerminalSession] {
        var seen = Set<Int>()
        return sessions.filter { seen.insert($0.windowId).inserted }
    }
}

enum DeckFilter: String, CaseIterable, Identifiable {
    case all = "All", needsYou = "Needs you", working = "Working", idle = "Idle", shells = "Shells"

    var id: String { rawValue }

    func includes(_ s: TerminalSession) -> Bool {
        switch self {
        case .all: return true
        case .needsYou: return s.status == .needsYou
        case .working: return s.status == .working
        case .idle: return s.status == .idle
        case .shells: return s.status == .shell
        }
    }
}

/// Joins Terminal tabs, process info and Claude session data into cards.
struct SessionAssembler {
    var now = Date()
    var staleAfter = Triage.defaultStaleAfter
    var claudeStats: (ClaudeSessionStore.SessionFile) -> ClaudeStats
    var gitStatus: (String) -> GitStatus?
    var summary: (String) -> AISummary?
    var notes: [String: [Note]] = [:]

    func assemble(tabs: [TerminalTab], processes: [String: TTYInfo],
                  sessionFiles: [Int32: ClaudeSessionStore.SessionFile]) -> [TerminalSession] {
        let sessions = tabs.map { tab -> TerminalSession in
            let proc = processes[tab.tty] ?? TTYInfo()
            // A tab is a Claude session when any of its processes has a session file.
            let file = proc.pids.lazy.compactMap { sessionFiles[$0] }.first
            let claude = file.map(claudeStats)
            let cwd = file?.cwd ?? proc.cwd
            var session = TerminalSession(
                tty: tab.tty, windowId: tab.windowId, tabIndex: tab.tabIndex,
                bounds: tab.bounds, miniaturized: tab.miniaturized, tabTitle: tab.title,
                cwd: cwd,
                foreground: claude == nil ? proc.foregroundCommand : nil,
                claude: claude,
                git: cwd.flatMap(gitStatus),
                summary: claude.flatMap { summary($0.sessionId) },
                status: Triage.status(of: claude, now: now, staleAfter: staleAfter))
            session.notes = notes[session.noteKey] ?? []
            return session
        }
        return Triage.sorted(sessions)
    }
}
