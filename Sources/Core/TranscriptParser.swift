import Foundation

/// Accumulates statistics from a Claude Code JSONL transcript, fed incrementally as the file grows.
struct TranscriptParser {
    private(set) var stats: ClaudeStats
    /// Claude Code writes one line per content block, each repeating its message's usage, so usage is
    /// tracked per message id and replaced (not added) when the same message appears again.
    private var usageByMessage: [String: Usage] = [:]

    static let maxStoredText = 1500
    static let maxRecentTurns = 8

    struct Usage: Equatable {
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
        var cost: Double = 0
    }

    init(sessionId: String) {
        stats = ClaudeStats(sessionId: sessionId)
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Feeds complete newline-terminated JSONL lines.
    mutating func ingest(_ lines: Data) {
        for line in lines.split(separator: 0x0A) {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            ingest(entry: entry)
        }
    }

    mutating func ingest(entry: [String: Any]) {
        if let ts = entry["timestamp"] as? String, let date = Self.timestampFormatter.date(from: ts) {
            if stats.firstActivity == nil { stats.firstActivity = date }
            stats.lastActivity = date
        }
        switch entry["type"] as? String {
        case "ai-title":
            if let title = entry["aiTitle"] as? String { stats.aiTitle = title }
        case "user":
            ingestUser(entry)
        case "assistant":
            ingestAssistant(entry)
        default:
            break
        }
    }

    // MARK: - User messages

    private mutating func ingestUser(_ entry: [String: Any]) {
        guard !Self.isSidechainOrMeta(entry), let message = entry["message"] as? [String: Any] else { return }
        let content = message["content"]
        if let blocks = content as? [[String: Any]], blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
            stats.lastRoleIsAssistant = false   // Claude is mid-turn, running tools.
            return
        }
        guard let text = Self.text(of: content), !Self.isHarnessInjected(text) else { return }
        let stored = String(text.prefix(Self.maxStoredText))
        stats.lastPrompt = stored
        stats.userTurns += 1
        stats.lastRoleIsAssistant = false
        remember(Turn(role: "user", text: stored))
    }

    /// Slash-command wrappers, system reminders and interrupt markers aren't real prompts.
    static func isHarnessInjected(_ text: String) -> Bool {
        text.hasPrefix("<") || text.hasPrefix("[Request interrupted") || text.hasPrefix("Caveat:")
    }

    // MARK: - Assistant messages

    private mutating func ingestAssistant(_ entry: [String: Any]) {
        guard !Self.isSidechainOrMeta(entry), let message = entry["message"] as? [String: Any] else { return }
        let model = message["model"] as? String
        if let model, model != "<synthetic>" { stats.model = model }

        if let usage = message["usage"] as? [String: Any] {
            record(Self.usage(from: usage, model: stats.model), messageId: message["id"] as? String ?? UUID().uuidString)
            let context = Self.int(usage["input_tokens"]) + Self.int(usage["cache_read_input_tokens"])
                + Self.int(usage["cache_creation_input_tokens"])
            if context > 0 {
                stats.contextTokens = context
                stats.contextWindow = Pricing.contextWindow(model: model ?? stats.model, observedTokens: context)
            }
        }

        guard let blocks = message["content"] as? [[String: Any]] else { return }
        if let text = Self.text(of: blocks) {
            let stored = String(text.prefix(Self.maxStoredText))
            stats.lastAssistantText = stored
            remember(Turn(role: "assistant", text: stored))
        }
        stats.lastRoleIsAssistant = !blocks.contains { $0["type"] as? String == "tool_use" }
    }

    private mutating func record(_ usage: Usage, messageId: String) {
        if let previous = usageByMessage[messageId] {
            apply(previous, sign: -1)
        } else {
            stats.assistantTurns += 1
        }
        usageByMessage[messageId] = usage
        apply(usage, sign: 1)
    }

    private mutating func apply(_ u: Usage, sign: Int) {
        stats.inputTokens += sign * u.input
        stats.outputTokens += sign * u.output
        stats.cacheReadTokens += sign * u.cacheRead
        stats.cacheWriteTokens += sign * u.cacheWrite
        stats.costUSD += Double(sign) * u.cost
    }

    static func usage(from json: [String: Any], model: String?) -> Usage {
        let cacheWrite = int(json["cache_creation_input_tokens"])
        let cacheWrite1h = int((json["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"])
        var u = Usage(input: int(json["input_tokens"]), output: int(json["output_tokens"]),
                      cacheRead: int(json["cache_read_input_tokens"]), cacheWrite: cacheWrite)
        u.cost = Pricing.cost(model: model, input: u.input, output: u.output, cacheRead: u.cacheRead,
                              cacheWrite5m: max(0, cacheWrite - cacheWrite1h), cacheWrite1h: cacheWrite1h)
        return u
    }

    // MARK: - Helpers

    private mutating func remember(_ turn: Turn) {
        stats.recentTurns.append(turn)
        if stats.recentTurns.count > Self.maxRecentTurns {
            stats.recentTurns.removeFirst(stats.recentTurns.count - Self.maxRecentTurns)
        }
    }

    static func isSidechainOrMeta(_ entry: [String: Any]) -> Bool {
        entry["isSidechain"] as? Bool == true || entry["isMeta"] as? Bool == true
    }

    /// Text of a message's content: a plain string, or the joined `text` blocks. Nil when empty.
    static func text(of content: Any?) -> String? {
        var text: String?
        if let string = content as? String {
            text = string
        } else if let blocks = content as? [[String: Any]] {
            text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func int(_ value: Any?) -> Int { value as? Int ?? 0 }

    /// Splits off the part of `data` that ends with a newline. A trailing partial line is left for later.
    static func completeLines(in data: Data) -> Data? {
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return nil }
        return data[data.startIndex...lastNewline]
    }
}
