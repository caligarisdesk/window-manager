import Foundation

/// Triage state of a terminal, in the order cards are sorted.
enum SessionStatus: Int, Comparable, CaseIterable {
    case needsYou = 0, working, idle, shell

    static func < (a: SessionStatus, b: SessionStatus) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .needsYou: return "Needs you"
        case .working: return "Working"
        case .idle: return "Idle"
        case .shell: return "Shell"
        }
    }
}

/// Window bounds as Terminal's AppleScript reports them: {left, top, right, bottom}, origin at the
/// top-left of the primary screen.
struct WindowBounds: Equatable, Codable {
    var left: Int, top: Int, right: Int, bottom: Int
}

/// One tab of a Terminal.app window.
struct TerminalTab: Equatable {
    var windowId: Int
    var tabIndex: Int
    var bounds: WindowBounds
    var miniaturized: Bool
    var tty: String          // e.g. "ttys000" (no /dev/ prefix)
    var title: String
    var busy: Bool
    var selected: Bool
}

/// A single conversational turn kept for summarizing.
struct Turn: Equatable, Codable {
    var role: String         // "user" or "assistant"
    var text: String
}

/// Everything Shelf knows about one Claude Code session.
struct ClaudeStats: Equatable {
    var sessionId: String
    var name: String?
    var rawStatus: String = "idle"   // "busy" or "idle", from ~/.claude/sessions/<pid>.json
    var statusUpdatedAt: Date?
    var aiTitle: String?
    var lastPrompt: String?
    var lastAssistantText: String?
    /// True when Claude finished its turn with text (not a tool call), i.e. it is waiting on the user.
    var lastRoleIsAssistant = false
    var model: String?
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0
    var costUSD: Double = 0
    /// Tokens sent on the most recent model call: how full the context window currently is.
    var contextTokens = 0
    var contextWindow = 200_000
    var userTurns = 0
    var assistantTurns = 0
    var firstActivity: Date?
    var lastActivity: Date?
    /// Bytes of transcript consumed so far; used to tell whether a summary is out of date.
    var transcriptSize: UInt64 = 0
    var recentTurns: [Turn] = []

    var isBusy: Bool { rawStatus == "busy" }
    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }
    var contextFill: Double { min(1, Double(contextTokens) / Double(max(contextWindow, 1))) }
}

struct GitStatus: Equatable {
    var branch: String
    var dirty: Int
}

/// AI-generated card text for a Claude session.
struct AISummary: Codable, Equatable {
    var done: String
    var next: String
    /// 2–3 sentence summary of Claude's most recent reply (nil in caches written by older versions).
    var last: String?
    var transcriptSize: UInt64
    var createdAt: Date

    var hasDoneOrNext: Bool { !(done.isEmpty && next.isEmpty) }
}

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
}

/// A Terminal tab plus everything known about what runs in it. This is what a card displays.
struct TerminalSession: Identifiable, Equatable {
    var tty: String
    var windowId: Int
    var tabIndex: Int
    var bounds: WindowBounds
    var miniaturized: Bool
    var tabTitle: String
    var cwd: String?
    var foreground: String?
    var claude: ClaudeStats?
    var git: GitStatus?
    var summary: AISummary?
    var status: SessionStatus
    var notes: [Note] = []

    var id: String { tty }
    var isClaude: Bool { claude != nil }

    /// Notes follow the Claude session; plain shells key on their directory.
    var noteKey: String { claude.map { "claude:" + $0.sessionId } ?? "dir:" + (cwd ?? tty) }

    var lastActivity: Date? { claude?.lastActivity ?? claude?.statusUpdatedAt }

    /// Card title: Claude's AI title, else the tab title without its status glyph, else the directory.
    var title: String {
        if let t = claude?.aiTitle, !t.isEmpty { return t }
        // Claude prefixes the tab title with a spinner/status glyph such as "✳ " or "◑ ".
        let cleaned = String(tabTitle.drop { !$0.isLetter && !$0.isNumber })
        if isClaude, !cleaned.isEmpty { return cleaned }
        if let cwd { return (cwd as NSString).lastPathComponent }
        return tty
    }

    func shortPath(home: String = NSHomeDirectory()) -> String {
        guard let cwd else { return "—" }
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }

    /// Stable hue in 0..<1 per project directory, used to tint cards from the same project alike.
    var accentHue: Double {
        var hash: UInt64 = 1469598103934665603          // FNV-1a
        for byte in (cwd ?? tty).utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return Double(hash % 360) / 360.0
    }
}
