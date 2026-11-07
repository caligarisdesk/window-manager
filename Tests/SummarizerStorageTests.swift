import Foundation

enum SummarizerTests: TestSuite {
    static let name = "Summarizer"
    static let now = Date(timeIntervalSince1970: 1_000)

    static func idleStats(_ id: String = "s", size: UInt64 = 100) -> ClaudeStats {
        var stats = ClaudeStats(sessionId: id)
        stats.aiTitle = "Title"
        stats.transcriptSize = size
        stats.recentTurns = [Turn(role: "user", text: "fix it"), Turn(role: "assistant", text: "fixed")]
        return stats
    }

    static func cliOutput(_ json: String) -> String {
        Fixture.line(["result": json, "is_error": false])
    }

    static func summary(size: UInt64, last: String? = "l") -> AISummary {
        AISummary(done: "d", next: "n", last: last, transcriptSize: size, createdAt: now)
    }

    static let tests: [(String, () throws -> Void)] = [
        ("policy: only idle sessions with turns, once at a time", {
            var busy = idleStats(); busy.rawStatus = "busy"
            var empty = idleStats(); empty.recentTurns = []
            func decide(_ stats: ClaudeStats, existing: AISummary? = nil, idleFor: TimeInterval = 60,
                        force: Bool = false, inFlight: Bool = false) -> Bool {
                Summarizer.shouldSummarize(stats: stats, existing: existing, idleSince: now.addingTimeInterval(-idleFor),
                                           now: now, debounce: 20, force: force, inFlight: inFlight)
            }
            check(!decide(busy, force: true))
            check(!decide(empty, force: true))
            check(!decide(idleStats(), force: true, inFlight: true))
            check(decide(idleStats(), existing: summary(size: 100), force: true))
            check(decide(idleStats(), idleFor: 0))                                   // First summary: no wait.
            check(!decide(idleStats(), existing: summary(size: 100)))               // Up to date.
            check(decide(idleStats(), existing: summary(size: 50)))                 // Transcript grew.
            check(!decide(idleStats(), existing: summary(size: 50), idleFor: 5))    // ...but still debouncing.
            check(decide(idleStats(), existing: summary(size: 100, last: nil)))    // Old cache format.
        }),
        ("prompt includes the title and recent turns", {
            let prompt = Summarizer.prompt(for: idleStats())
            check(prompt.contains("Session title: Title"))
            check(prompt.contains("USER: fix it") && prompt.contains("ASSISTANT: fixed"))
            check(Summarizer.prompt(for: ClaudeStats(sessionId: "x")).contains("Session title: unknown"))
        }),
        ("parse reads the JSON inside the CLI result", {
            let parsed = Summarizer.parse(cliOutput("Sure! ```{\"done\": \"A\", \"next\": \"B\", \"last\": \"C\"}```"),
                                          transcriptSize: 9, now: now)
            checkEqual(parsed, AISummary(done: "A", next: "B", last: "C", transcriptSize: 9, createdAt: now))
            checkEqual(Summarizer.parse(cliOutput("{}"), transcriptSize: 1, now: now),
                       AISummary(done: "", next: "", last: nil, transcriptSize: 1, createdAt: now))
            checkNil(Summarizer.parse("not json", transcriptSize: 0, now: now))
            checkNil(Summarizer.parse(Fixture.line(["other": 1]), transcriptSize: 0, now: now))
            checkNil(Summarizer.parse(cliOutput("no braces"), transcriptSize: 0, now: now))
            checkNil(Summarizer.parse(cliOutput("} backwards {"), transcriptSize: 0, now: now))
            checkNil(Summarizer.parse(cliOutput("{not: json}"), transcriptSize: 0, now: now))
        }),
        ("consider runs claude in the background, caches and notifies", {
            let dir = TempDir()
            let cache = JSONFile<[String: AISummary]>(url: dir.url.appendingPathComponent("summaries.json"))
            let fake = FakeRunner { _ in CommandResult(out: cliOutput("{\"done\":\"D\",\"next\":\"N\",\"last\":\"L\"}"), status: 0) }
            let summarizer = Summarizer(runner: fake, claudePath: "/bin/claude", cacheFile: cache, workDir: dir.path,
                                        now: { now })
            var updates = 0
            summarizer.onUpdate = { updates += 1 }
            summarizer.consider(idleStats())
            check(waitUntil { updates == 1 }, "no update")
            checkEqual(summarizer.summary(for: "s")?.next, "N")
            checkEqual(cache.load()?["s"]?.last, "L")
            let call = try unwrap(fake.calls.first)
            checkEqual(call.path, "/bin/claude")
            checkEqual(call.args, Summarizer.arguments)
            checkEqual(call.cwd, dir.path)
            check(call.stdin?.contains("fix it") == true)

            // Up to date now, so nothing new starts; a busy session resets its idle clock.
            summarizer.consider(idleStats())
            var busy = idleStats(); busy.rawStatus = "busy"
            summarizer.consider(busy)
            check(waitUntil { summarizer.isIdle })
            checkEqual(fake.calls.count, 1)

            // A new instance starts from the on-disk cache.
            let reloaded = Summarizer(claudePath: nil, cacheFile: cache, workDir: dir.path)
            checkEqual(reloaded.summary(for: "s")?.done, "D")
        }),
        ("failures leave no summary and allow retrying", {
            let dir = TempDir()
            let cache = JSONFile<[String: AISummary]>(url: dir.url.appendingPathComponent("s.json"))
            let fake = FakeRunner { _ in CommandResult(out: "", status: 1) }
            let summarizer = Summarizer(runner: fake, claudePath: "/bin/claude", cacheFile: cache, workDir: dir.path)
            summarizer.consider(idleStats())
            check(waitUntil { fake.calls.count == 1 && summarizer.isIdle })
            checkNil(summarizer.summary(for: "s"))
            checkNil(cache.load())
            checkNil(Summarizer(claudePath: nil, cacheFile: cache, workDir: dir.path).generate(for: idleStats()))
        }),
        ("locating the CLI tries known paths, then the login shell", {
            let shell = FakeRunner { _ in CommandResult(out: "/custom/claude\n", status: 0) }
            checkEqual(Summarizer.locateClaude(candidates: ["/a", "/b"], runner: shell, isExecutable: { $0 == "/b" }), "/b")
            checkEqual(Summarizer.locateClaude(candidates: ["/a"], runner: shell, isExecutable: { _ in false }), "/custom/claude")
            checkEqual(shell.calls.first?.args, ["-lc", "command -v claude"])
            checkNil(Summarizer.locateClaude(candidates: [], runner: FakeRunner()))
            checkEqual(Summarizer.locateClaude(candidates: ["/bin/sh"], runner: FakeRunner()), "/bin/sh")   // Real file check.
            check(Summarizer.defaultCandidates.contains("/opt/homebrew/bin/claude"))
        }),
    ]
}

enum StorageTests: TestSuite {
    static let name = "Storage"
    static let tests: [(String, () throws -> Void)] = [
        ("JSON files round-trip, and report missing, corrupt and unwritable files", {
            let dir = TempDir()
            let file = JSONFile<[String: Int]>(url: dir.url.appendingPathComponent("x.json"))
            checkNil(file.load())
            check(file.save(["a": 1]))
            checkEqual(file.load(), ["a": 1])
            dir.write("x.json", "corrupt")
            checkNil(file.load())
            check(!JSONFile<[String: Int]>(url: dir.url.appendingPathComponent("no/such/dir/x.json")).save([:]))
            check(!JSONFile<Double>(url: dir.url.appendingPathComponent("nan.json")).save(.nan))   // Not encodable.
        }),
        ("support directory is created under the base", {
            let base = TempDir()
            let dir = AppPaths.supportDirectory(base: base.url)
            checkEqual(dir.lastPathComponent, "Shelf")
            var isDir: ObjCBool = false
            check(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue)
            check(AppPaths.supportDirectory().path.hasSuffix("Application Support/Shelf"))
        }),
        ("notes book adds trimmed notes and deletes them", {
            var book = NotesBook()
            check(!book.add("   ", to: "k"))
            check(book.add("  first ", to: "k", at: Date(timeIntervalSince1970: 5)))
            book.add("second", to: "k")
            checkEqual(book["k"].map(\.text), ["first", "second"])
            checkEqual(book["k"].first?.createdAt, Date(timeIntervalSince1970: 5))
            checkEqual(book["missing"], [])
            book.delete(book["k"][0].id, from: "k")
            checkEqual(book["k"].map(\.text), ["second"])
            book.delete(book["k"][0].id, from: "k")
            checkNil(book.notes["k"])
            book.delete(UUID(), from: "nothing")
            checkEqual(book, NotesBook(notes: [:]))
        }),
    ]
}

enum GitInfoTests: TestSuite {
    static let name = "GitInfo"
    static let tests: [(String, () throws -> Void)] = [
        ("reports branch and dirty count, cached for the TTL", {
            var clock = Date(timeIntervalSince1970: 0)
            let fake = FakeRunner { call in
                call.args.contains("rev-parse") ? CommandResult(out: "main\n", status: 0)
                                                : CommandResult(out: " M a.swift\n?? b.swift\n", status: 0)
            }
            let git = GitInfo(runner: fake, ttl: 15, now: { clock })
            checkEqual(git.status(for: "/repo"), GitStatus(branch: "main", dirty: 2))
            checkEqual(fake.calls.first?.args, ["-C", "/repo", "rev-parse", "--abbrev-ref", "HEAD"])
            clock = clock.addingTimeInterval(10)
            _ = git.status(for: "/repo")
            checkEqual(fake.calls.count, 2)          // Cached.
            clock = clock.addingTimeInterval(10)
            _ = git.status(for: "/repo")
            checkEqual(fake.calls.count, 4)          // Expired.
        }),
        ("returns nil outside a repository, and caches that too", {
            let fake = FakeRunner { _ in CommandResult(out: "", status: 128) }
            let git = GitInfo(runner: fake)
            checkNil(git.status(for: "/tmp"))
            checkNil(git.status(for: "/tmp"))
            checkEqual(fake.calls.count, 1)
        }),
    ]
}
