import Foundation

/// Generates the AI card text ("Done / Next" and a summary of Claude's last reply) for idle sessions,
/// by running `claude -p` with Haiku in the background. Results are cached on disk.
final class Summarizer {
    let runner: CommandRunning
    let claudePath: String?
    let cacheFile: JSONFile<[String: AISummary]>
    /// Where `claude -p` runs, so it never touches a project directory.
    let workDir: String
    /// How long a session must stay idle before it is summarized, so quick back-and-forth doesn't spend calls.
    let debounce: TimeInterval
    let now: () -> Date
    /// Called on the main queue whenever a new summary lands.
    var onUpdate: (() -> Void)?

    private let queue = OperationQueue()
    private let lock = NSLock()
    private var inFlight: Set<String> = []
    private var cache: [String: AISummary]
    private var idleSince: [String: Date] = [:]

    init(runner: CommandRunning = ProcessRunner(), claudePath: String?, cacheFile: JSONFile<[String: AISummary]>,
         workDir: String, debounce: TimeInterval = 20, maxConcurrent: Int = 2, now: @escaping () -> Date = Date.init) {
        self.runner = runner
        self.claudePath = claudePath
        self.cacheFile = cacheFile
        self.workDir = workDir
        self.debounce = debounce
        self.now = now
        queue.maxConcurrentOperationCount = maxConcurrent
        queue.qualityOfService = .utility
        self.cache = cacheFile.load() ?? [:]
    }

    func summary(for sessionId: String) -> AISummary? {
        lock.lock(); defer { lock.unlock() }
        return cache[sessionId]
    }

    var isIdle: Bool {
        lock.lock(); defer { lock.unlock() }
        return inFlight.isEmpty
    }

    /// Call on every refresh. Starts a background summary when `Self.shouldSummarize` says so.
    func consider(_ stats: ClaudeStats, force: Bool = false) {
        let id = stats.sessionId
        lock.lock()
        if stats.isBusy {
            idleSince[id] = nil
            lock.unlock()
            return
        }
        let since = idleSince[id] ?? now()
        idleSince[id] = since
        let start = Self.shouldSummarize(stats: stats, existing: cache[id], idleSince: since, now: now(),
                                         debounce: debounce, force: force, inFlight: inFlight.contains(id))
        if start { inFlight.insert(id) }
        lock.unlock()
        guard start else { return }

        queue.addOperation { [self] in
            finish(id, with: generate(for: stats))
        }
    }

    private func finish(_ id: String, with result: AISummary?) {
        lock.lock()
        if let result { cache[id] = result }
        let snapshot = cache
        inFlight.remove(id)
        lock.unlock()
        guard result != nil else { return }
        cacheFile.save(snapshot)
        DispatchQueue.main.async { self.onUpdate?() }
    }

    func generate(for stats: ClaudeStats) -> AISummary? {
        guard let claudePath else { return nil }
        let result = runner.run(claudePath, Self.arguments, stdin: Self.prompt(for: stats), cwd: workDir, timeout: 90)
        guard result.succeeded else { return nil }
        return Self.parse(result.out, transcriptSize: stats.transcriptSize, now: now())
    }

    // MARK: - Policy

    /// Summarize when the session is idle, has something to summarize, isn't already being summarized,
    /// and either has no summary yet or has grown since (after the debounce), or the user forced it.
    static func shouldSummarize(stats: ClaudeStats, existing: AISummary?, idleSince: Date, now: Date,
                                debounce: TimeInterval, force: Bool, inFlight: Bool) -> Bool {
        guard !stats.isBusy, !inFlight, !stats.recentTurns.isEmpty else { return false }
        if force { return true }
        guard let existing else { return true }
        let outdated = existing.transcriptSize < stats.transcriptSize || existing.last == nil
        return outdated && now.timeIntervalSince(idleSince) >= debounce
    }

    // MARK: - Prompt and response

    /// No tools, MCP servers, slash commands or saved session: a single cheap text completion.
    static let arguments = ["-p", "--model", "haiku", "--output-format", "json", "--no-session-persistence",
                            "--strict-mcp-config", "--disable-slash-commands", "--tools", ""]

    static func prompt(for stats: ClaudeStats) -> String {
        let transcript = stats.recentTurns.suffix(6)
            .map { "\($0.role.uppercased()): \($0.text.prefix(1000))" }
            .joined(separator: "\n\n")
        return """
        You are summarizing a Claude Code coding session for a dashboard card.
        Session title: \(stats.aiTitle ?? "unknown")

        Recent conversation:
        \(transcript.prefix(6000))

        Reply with ONLY a JSON object, no prose, no code fences:
        {"done": "<what has been accomplished, max 15 words>",
         "next": "<what the user should do next, max 15 words>",
         "last": "<2-3 plain sentences summarizing the ASSISTANT's final message above: key findings, questions it asked, decisions it needs>"}
        """
    }

    /// Parses `claude -p --output-format json` output, whose `result` holds the model's JSON (possibly
    /// wrapped in prose or code fences).
    static func parse(_ output: String, transcriptSize: UInt64, now: Date) -> AISummary? {
        guard let envelope = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              let text = envelope["result"] as? String,
              let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let fields = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any]
        else { return nil }
        return AISummary(done: fields["done"] as? String ?? "", next: fields["next"] as? String ?? "",
                         last: fields["last"] as? String, transcriptSize: transcriptSize, createdAt: now)
    }

    // MARK: - Locating the CLI

    static let defaultCandidates = [NSHomeDirectory() + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    /// The first executable candidate, else whatever a login shell finds on PATH.
    static func locateClaude(candidates: [String] = defaultCandidates, runner: CommandRunning = ProcessRunner(),
                             isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String? {
        if let found = candidates.first(where: isExecutable) { return found }
        let path = runner.run("/bin/zsh", ["-lc", "command -v claude"], timeout: 5).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
