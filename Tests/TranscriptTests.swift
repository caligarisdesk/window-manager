import Foundation

enum TranscriptParserTests: TestSuite {
    static let name = "TranscriptParser"

    static func parse(_ entries: [[String: Any]]) -> ClaudeStats {
        var parser = TranscriptParser(sessionId: "s")
        parser.ingest(Data(entries.map(Fixture.line).joined().utf8))
        return parser.stats
    }

    static let tests: [(String, () throws -> Void)] = [
        ("tracks titles and first/last timestamps", {
            let stats = parse([
                ["type": "ai-title", "aiTitle": "Refactor parser", "timestamp": "2026-11-06T10:00:00.000Z"],
                ["type": "mode", "timestamp": "2026-11-06T11:30:00.500Z"],
                ["type": "mode", "timestamp": "not a date"],
            ])
            checkEqual(stats.aiTitle, "Refactor parser")
            checkEqual(stats.firstActivity, ISO8601DateFormatter().date(from: "2026-11-06T10:00:00Z"))
            checkEqual(stats.lastActivity, ISO8601DateFormatter().date(from: "2026-11-06T11:30:00Z")?.addingTimeInterval(0.5))
        }),
        ("records real user prompts from strings and text blocks", {
            let stats = parse([
                Fixture.user("  first  "),
                Fixture.user([["type": "text", "text": "second"], ["type": "image"]]),
            ])
            checkEqual(stats.lastPrompt, "second")
            checkEqual(stats.userTurns, 2)
            checkEqual(stats.recentTurns, [Turn(role: "user", text: "first"), Turn(role: "user", text: "second")])
        }),
        ("ignores injected, meta, sidechain, empty and malformed user entries", {
            let stats = parse([
                Fixture.user("<command-name>/clear</command-name>"),
                Fixture.user("[Request interrupted by user]"),
                Fixture.user("Caveat: generated"),
                Fixture.user("meta", extra: ["isMeta": true]),
                Fixture.user("side", extra: ["isSidechain": true]),
                Fixture.user("   "),
                Fixture.user(42),
                ["type": "user"],
            ])
            checkNil(stats.lastPrompt)
            checkEqual(stats.userTurns, 0)
        }),
        ("tool results mean Claude is mid-turn", {
            let stats = parse([
                Fixture.assistant(content: [["type": "text", "text": "Done."]]),
                Fixture.user([["type": "tool_result", "content": "ok"]]),
            ])
            check(!stats.lastRoleIsAssistant)
            checkEqual(stats.userTurns, 0)
        }),
        ("assistant usage sums once per message id and prices the model", {
            let stats = parse([
                Fixture.assistant(id: "m1", content: [["type": "text", "text": "a"]],
                                  usage: Fixture.usage(input: 10, output: 5, cacheRead: 100, cacheWrite: 50, cacheWrite1h: 20)),
                // The same message repeated with grown output replaces the earlier usage.
                Fixture.assistant(id: "m1", content: [["type": "tool_use", "name": "Bash"]],
                                  usage: Fixture.usage(input: 10, output: 8, cacheRead: 100, cacheWrite: 50, cacheWrite1h: 20)),
                Fixture.assistant(id: "m2", usage: Fixture.usage(input: 1, output: 1)),
            ])
            checkEqual(stats.inputTokens, 11)
            checkEqual(stats.outputTokens, 9)
            checkEqual(stats.cacheReadTokens, 100)
            checkEqual(stats.cacheWriteTokens, 50)
            checkEqual(stats.assistantTurns, 2)
            let expected = Pricing.cost(model: "claude-opus-5-5", input: 10, output: 8, cacheRead: 100, cacheWrite5m: 30, cacheWrite1h: 20)
                + Pricing.cost(model: "claude-opus-5-5", input: 1, output: 1, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)
            check(abs(stats.costUSD - expected) < 1e-12, "cost \(stats.costUSD) != \(expected)")
            checkEqual(stats.contextTokens, 1)               // Latest call: 1 input token.
            checkEqual(stats.contextWindow, 1_000_000)
            checkEqual(stats.model, "claude-opus-5-5")
        }),
        ("final text without tool calls means Claude is waiting on the user", {
            var stats = parse([Fixture.assistant(content: [["type": "text", "text": "  Here you go  "]])])
            check(stats.lastRoleIsAssistant)
            checkEqual(stats.lastAssistantText, "Here you go")
            stats = parse([Fixture.assistant(content: [["type": "tool_use", "name": "Read"]])])
            check(!stats.lastRoleIsAssistant)
            checkNil(stats.lastAssistantText)
        }),
        ("synthetic models, missing ids, zero usage and missing content are tolerated", {
            let stats = parse([
                Fixture.assistant(id: nil, model: "<synthetic>", usage: Fixture.usage()),
                Fixture.assistant(model: nil),
                Fixture.assistant(extra: ["isSidechain": true]),
                ["type": "assistant"],
            ])
            checkNil(stats.model)
            checkEqual(stats.assistantTurns, 1)
            checkEqual(stats.contextTokens, 0)
            // Without any model id the window is sized from the token count alone.
            let unknown = parse([Fixture.assistant(model: nil, usage: Fixture.usage(input: 300_000))])
            checkEqual(unknown.contextWindow, 1_000_000)
            checkEqual(TranscriptParser.Usage(), TranscriptParser.Usage(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0))
        }),
        ("long text is truncated and only recent turns are kept", {
            let long = String(repeating: "x", count: TranscriptParser.maxStoredText + 50)
            let stats = parse((0..<10).map { Fixture.user("prompt \($0)") } + [Fixture.user(long)])
            checkEqual(stats.lastPrompt?.count, TranscriptParser.maxStoredText)
            checkEqual(stats.recentTurns.count, TranscriptParser.maxRecentTurns)
            checkEqual(stats.recentTurns.first?.text, "prompt 3")
        }),
        ("invalid JSON lines are skipped", {
            var parser = TranscriptParser(sessionId: "s")
            parser.ingest(Data("not json\n[1,2]\n".utf8) + Data(Fixture.line(["type": "ai-title", "aiTitle": "ok"]).utf8))
            checkEqual(parser.stats.aiTitle, "ok")
        }),
        ("complete lines stop at the last newline", {
            checkNil(TranscriptParser.completeLines(in: Data("partial".utf8)))
            checkEqual(TranscriptParser.completeLines(in: Data("a\nb\npart".utf8)), Data("a\nb\n".utf8))
        }),
        ("helpers extract text and integers defensively", {
            checkNil(TranscriptParser.text(of: nil))
            checkNil(TranscriptParser.text(of: [["type": "image"]]))
            checkEqual(TranscriptParser.int("7"), 0)
            checkEqual(TranscriptParser.int(7), 7)
        }),
    ]
}

enum PricingTests: TestSuite {
    static let name = "Pricing"
    static let tests: [(String, () throws -> Void)] = [
        ("models match the most specific rate", {
            checkEqual(Pricing.rate(for: "claude-opus-5-5"), Pricing.Rate(input: 4, output: 20, cacheRead: 0.20))
            checkEqual(Pricing.rate(for: "claude-opus-5"), Pricing.Rate(input: 5, output: 25, cacheRead: 0.50))
            checkEqual(Pricing.rate(for: "CLAUDE-HAIKU-5-5"), Pricing.Rate(input: 0.10, output: 0.50, cacheRead: 0.01))
            checkEqual(Pricing.rate(for: "mystery"), Pricing.fallback)
            checkEqual(Pricing.rate(for: nil), Pricing.fallback)
        }),
        ("cost weighs each token kind", {
            // Opus 5.5: $4 in, $20 out, $0.20 cache read, cache writes 1.25×/2× input.
            let cost = Pricing.cost(model: "claude-opus-5-5", input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000,
                                    cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000)
            check(abs(cost - (4 + 20 + 0.2 + 5 + 8)) < 1e-9, "cost was \(cost)")
        }),
        ("context window is 1M for large-context models or when observed", {
            checkEqual(Pricing.contextWindow(model: "claude-opus-5-5", observedTokens: 10), 1_000_000)
            checkEqual(Pricing.contextWindow(model: "claude-haiku-4-5[1m]", observedTokens: 10), 1_000_000)
            checkEqual(Pricing.contextWindow(model: "claude-haiku-4-5", observedTokens: 250_000), 1_000_000)
            checkEqual(Pricing.contextWindow(model: "claude-haiku-4-5", observedTokens: 10), 200_000)
            checkEqual(Pricing.contextWindow(model: nil, observedTokens: 10), 200_000)
        }),
    ]
}

enum ClaudeSessionStoreTests: TestSuite {
    static let name = "ClaudeSessionStore"

    static func sessionJSON(pid: Int32, id: String, cwd: String?, status: String? = "idle") -> String {
        var object: [String: Any] = ["pid": pid, "sessionId": id, "name": "n", "statusUpdatedAt": 1_000_000.0]
        if let cwd { object["cwd"] = cwd }
        if let status { object["status"] = status }
        return Fixture.line(object)
    }

    static let tests: [(String, () throws -> Void)] = [
        ("reads session files keyed by pid, skipping junk", {
            let dir = TempDir()
            dir.write("sessions/42.json", sessionJSON(pid: 42, id: "a", cwd: "/w"))
            dir.write("sessions/bad.json", "{")
            dir.write("sessions/42.key", "ignored")
            let files = ClaudeSessionStore(claudeDir: dir.path).sessionFiles()
            checkEqual(Array(files.keys), [42])
            checkEqual(files[42]?.sessionId, "a")
            checkEqual(ClaudeSessionStore(claudeDir: dir.path + "/missing").sessionFiles().count, 0)
        }),
        ("finds transcripts by project slug and reads them incrementally", {
            let dir = TempDir()
            let rel = "projects/-w-my-app/a.jsonl"
            dir.write(rel, Fixture.line(Fixture.user("one")))
            let store = ClaudeSessionStore(claudeDir: dir.path)
            let file = try unwrap(try? JSONDecoder().decode(ClaudeSessionStore.SessionFile.self,
                                                             from: Data(sessionJSON(pid: 1, id: "a", cwd: "/w/my.app").utf8)))
            var stats = store.stats(for: file)
            checkEqual(stats.userTurns, 1)
            checkEqual(stats.name, "n")
            checkEqual(stats.rawStatus, "idle")
            checkEqual(stats.statusUpdatedAt, Date(timeIntervalSince1970: 1000))

            // A partial trailing line waits until it is complete.
            dir.append(rel, Fixture.line(Fixture.user("two")) + "{\"type\":\"user\"")
            stats = store.stats(for: file)
            checkEqual(stats.userTurns, 2)
            dir.append(rel, ",\"message\":{\"content\":\"three\"}}\n")
            stats = store.stats(for: file)
            checkEqual(stats.userTurns, 3)
            checkEqual(stats.lastPrompt, "three")
            checkEqual(stats.transcriptSize, UInt64(try FileManager.default.attributesOfItem(atPath: dir.path + "/" + rel)[.size] as! Int))
        }),
        ("falls back to scanning project folders and restarts on rewritten files", {
            let dir = TempDir()
            dir.write("projects/elsewhere/b.jsonl", Fixture.line(Fixture.user("x")) + Fixture.line(Fixture.user("y")))
            let store = ClaudeSessionStore(claudeDir: dir.path)
            let file = ClaudeSessionStore.SessionFile(pid: 1, sessionId: "b", cwd: nil, name: nil, status: nil, statusUpdatedAt: nil)
            checkEqual(store.stats(for: file).userTurns, 2)
            dir.write("projects/elsewhere/b.jsonl", Fixture.line(Fixture.user("z")))   // Shorter: rewritten.
            let stats = store.stats(for: file)
            checkEqual(stats.userTurns, 1)
            checkEqual(stats.lastPrompt, "z")
            checkEqual(stats.rawStatus, "idle")
            checkNil(stats.statusUpdatedAt)
        }),
        ("starts fresh when a session's transcript moves", {
            let dir = TempDir()
            dir.write("projects/one/c.jsonl", Fixture.line(Fixture.user("old")))
            let store = ClaudeSessionStore(claudeDir: dir.path)
            let file = ClaudeSessionStore.SessionFile(pid: 1, sessionId: "c", cwd: nil, name: nil, status: "busy", statusUpdatedAt: nil)
            checkEqual(store.stats(for: file).lastPrompt, "old")
            try FileManager.default.removeItem(atPath: dir.path + "/projects/one")
            dir.write("projects/two/c.jsonl", Fixture.line(Fixture.user("new")))
            checkEqual(store.stats(for: file).lastPrompt, "new")
            checkEqual(store.stats(for: file).userTurns, 1)
        }),
        ("sessions without a transcript still report status", {
            let store = ClaudeSessionStore(claudeDir: TempDir().path)
            let file = ClaudeSessionStore.SessionFile(pid: 1, sessionId: "none", cwd: "/x", name: "nm", status: "busy", statusUpdatedAt: nil)
            let stats = store.stats(for: file)
            check(stats.isBusy)
            checkEqual(stats.userTurns, 0)
        }),
        ("unreadable transcripts are skipped", {
            let dir = TempDir()
            let path = dir.write("projects/p/d.jsonl", Fixture.line(Fixture.user("secret")))
            chmod(path, 0)
            defer { chmod(path, 0o644) }
            let file = ClaudeSessionStore.SessionFile(pid: 1, sessionId: "d", cwd: nil, name: nil, status: nil, statusUpdatedAt: nil)
            checkNil(ClaudeSessionStore(claudeDir: dir.path).stats(for: file).lastPrompt)
        }),
        ("reads large files in bounded slices and skips over-long lines", {
            let dir = TempDir()
            let huge = Fixture.line(Fixture.user(String(repeating: "h", count: 300)))
            dir.write("projects/p/e.jsonl", Fixture.line(Fixture.user("a")) + huge + Fixture.line(Fixture.user("b")))
            let store = ClaudeSessionStore(claudeDir: dir.path, maxReadBytes: 128)
            let file = ClaudeSessionStore.SessionFile(pid: 1, sessionId: "e", cwd: nil, name: nil, status: nil, statusUpdatedAt: nil)
            let stats = store.stats(for: file)
            checkEqual(stats.recentTurns.map(\.text), ["a", "b"])
        }),
        ("retain forgets sessions that ended", {
            let dir = TempDir()
            dir.write("projects/p/f.jsonl", Fixture.line(Fixture.user("x")))
            let store = ClaudeSessionStore(claudeDir: dir.path)
            _ = store.stats(for: ClaudeSessionStore.SessionFile(pid: 1, sessionId: "f", cwd: nil, name: nil, status: nil, statusUpdatedAt: nil))
            checkEqual(store.cachedSessionIds, ["f"])
            store.retain(sessionIds: ["other"])
            checkEqual(store.cachedSessionIds, [])
        }),
        ("project slugs replace non-alphanumerics", {
            checkEqual(ClaudeSessionStore.projectSlug(for: "/Users/me/code/my_app.v2"), "-Users-me-code-my-app-v2")
        }),
    ]
}
