import CoreGraphics
import Foundation

enum TriageTests: TestSuite {
    static let name = "Triage"
    static let now = Date(timeIntervalSince1970: 100_000)

    static func claude(busy: Bool = false, last: Date? = nil, statusAt: Date? = nil) -> ClaudeStats {
        var stats = ClaudeStats(sessionId: "s")
        stats.rawStatus = busy ? "busy" : "idle"
        stats.lastActivity = last
        stats.statusUpdatedAt = statusAt
        return stats
    }

    static let tests: [(String, () throws -> Void)] = [
        ("status: shell, working, needs you, idle", {
            checkEqual(Triage.status(of: nil, now: now), .shell)
            checkEqual(Triage.status(of: claude(busy: true), now: now), .working)
            checkEqual(Triage.status(of: claude(last: now.addingTimeInterval(-60)), now: now), .needsYou)
            checkEqual(Triage.status(of: claude(statusAt: now.addingTimeInterval(-60)), now: now), .needsYou)
            checkEqual(Triage.status(of: claude(last: now.addingTimeInterval(-4 * 3600)), now: now), .idle)
            checkEqual(Triage.status(of: claude(), now: now), .idle)
            checkEqual(Triage.status(of: claude(last: now.addingTimeInterval(-60)), now: now, staleAfter: 30), .idle)
        }),
        ("sorting groups by status then recency", {
            let sessions = [
                Fixture.session("a", status: .shell),
                Fixture.session("b", status: .needsYou, lastActivity: now.addingTimeInterval(-100)),
                Fixture.session("c", status: .working),
                Fixture.session("d", status: .needsYou, lastActivity: now),
                Fixture.session("e", status: .needsYou),
            ]
            checkEqual(Triage.sorted(sessions).map(\.tty), ["d", "b", "e", "c", "a"])
        }),
        ("search matches title, path, prompt, command, next step and notes", {
            var s = Fixture.session(cwd: "/code/Shelf")
            s.foreground = "npm run dev"
            s.summary = AISummary(done: "", next: "Review the PR", last: nil, transcriptSize: 0, createdAt: now)
            s.notes = [Note(text: "ask Sam about auth")]
            check(Triage.matches(s, search: ""))
            check(Triage.matches(s, search: "  "))
            check(Triage.matches(s, search: "shelf"))
            check(Triage.matches(s, search: "NPM"))
            check(Triage.matches(s, search: "review"))
            check(Triage.matches(s, search: "sam"))
            check(!Triage.matches(s, search: "nothing"))
            check(!Triage.matches(Fixture.session(cwd: nil), search: "nothing"))
        }),
        ("visible applies filter and search", {
            let sessions = [Fixture.session("a", status: .working, cwd: "/x"), Fixture.session("b", status: .shell, cwd: "/y")]
            checkEqual(Triage.visible(sessions, filter: .working, search: "").map(\.tty), ["a"])
            checkEqual(Triage.visible(sessions, filter: .all, search: "y").map(\.tty), ["b"])
        }),
        ("filters include matching statuses", {
            let byStatus = Dictionary(uniqueKeysWithValues: SessionStatus.allCases.map { ($0, Fixture.session(status: $0)) })
            checkEqual(DeckFilter.allCases.map { f in SessionStatus.allCases.filter { f.includes(byStatus[$0]!) }.count },
                       [4, 1, 1, 1, 1])
            checkEqual(DeckFilter.needsYou.id, "Needs you")
            check(DeckFilter.idle.includes(byStatus[.idle]!))
            check(DeckFilter.shells.includes(byStatus[.shell]!))
        }),
        ("distinct windows keeps the first tab of each window", {
            let sessions = [Fixture.session("a", window: 1), Fixture.session("b", window: 1), Fixture.session("c", window: 2)]
            checkEqual(Triage.distinctWindows(sessions).map(\.tty), ["a", "c"])
        }),
        ("assembler joins tabs, processes, claude data, git, summaries and notes", {
            let file = ClaudeSessionStore.SessionFile(pid: 7, sessionId: "abc", cwd: "/claude/cwd", name: nil, status: "busy", statusUpdatedAt: nil)
            let summary = AISummary(done: "d", next: "n", last: nil, transcriptSize: 0, createdAt: now)
            let note = Note(text: "remember")
            let assembler = SessionAssembler(
                now: now,
                claudeStats: { file in var s = ClaudeStats(sessionId: file.sessionId); s.rawStatus = file.status!; return s },
                gitStatus: { $0 == "/claude/cwd" ? GitStatus(branch: "main", dirty: 2) : nil },
                summary: { $0 == "abc" ? summary : nil },
                notes: ["claude:abc": [note], "dir:/shell": [note]])
            let sessions = assembler.assemble(
                tabs: [Fixture.tab("ttys001", window: 2), Fixture.tab("ttys000"), Fixture.tab("ttys005")],
                processes: ["ttys000": TTYInfo(pids: [6, 7], foregroundCommand: "claude", cwd: "/proc/cwd"),
                            "ttys001": TTYInfo(pids: [9], foregroundCommand: "vim", cwd: "/shell")],
                sessionFiles: [7: file])
            checkEqual(sessions.map(\.tty), ["ttys000", "ttys001", "ttys005"])
            let claude = sessions[0], shell = sessions[1], unknown = sessions[2]
            checkEqual(claude.status, .working)
            checkEqual(claude.cwd, "/claude/cwd")
            checkNil(claude.foreground)
            checkEqual(claude.git, GitStatus(branch: "main", dirty: 2))
            checkEqual(claude.summary, summary)
            checkEqual(claude.notes, [note])
            checkEqual(shell.status, .shell)
            checkEqual(shell.foreground, "vim")
            checkEqual(shell.notes, [note])
            checkNil(unknown.cwd)
            checkEqual(unknown.notes, [])

            // Defaults: current time, standard staleness, no notes.
            let plain = SessionAssembler(claudeStats: { ClaudeStats(sessionId: $0.sessionId) }, gitStatus: { _ in nil }, summary: { _ in nil })
            check(abs(plain.now.timeIntervalSinceNow) < 5)
            checkEqual(plain.notes.count, 0)
            checkEqual(plain.staleAfter, Triage.defaultStaleAfter)
        }),
    ]
}

enum WindowLayoutTests: TestSuite {
    static let name = "WindowLayout"
    // A 1000×800 primary screen with a 25pt menu bar: visible frame y 0..775.
    static let layout = WindowLayout(primaryHeight: 800, frame: CGRect(x: 0, y: 0, width: 1000, height: 775))

    static let tests: [(String, () throws -> Void)] = [
        ("converts bottom-left frames to top-left bounds", {
            checkEqual(layout.bounds(from: CGRect(x: 10, y: 100, width: 200, height: 300)),
                       WindowBounds(left: 10, top: 400, right: 210, bottom: 700))
        }),
        ("expanded fills the visible frame minus an inset", {
            checkEqual(layout.expanded(inset: 10), WindowBounds(left: 10, top: 35, right: 990, bottom: 790))
            checkEqual(layout.expanded(), layout.expanded(inset: 12))
        }),
        ("grid shape favours landscape cells", {
            checkEqual(WindowLayout.gridShape(count: 1, aspect: 1.3).cols, 1)
            check(WindowLayout.gridShape(count: 4, aspect: 1.3) == (cols: 2, rows: 2))
            check(WindowLayout.gridShape(count: 5, aspect: 1.3) == (cols: 3, rows: 2))
            check(WindowLayout.gridShape(count: 12, aspect: 2.0) == (cols: 4, rows: 3))
        }),
        ("grid lays cells row by row from the top-left without overlap", {
            checkEqual(layout.grid(count: 0), [])
            let cells = layout.grid(count: 4, gap: 10)
            checkEqual(cells.count, 4)
            checkEqual(cells[0].left, 10)
            checkEqual(cells[0].top, 35)
            check(cells[1].left > cells[0].right, "columns overlap")
            check(cells[2].top > cells[0].bottom, "rows overlap")
            checkEqual(cells[3].right, 990)
            checkEqual(layout.grid(count: 1), [layout.bounds(from: layout.frame.insetBy(dx: 8, dy: 8))])
        }),
    ]
}

enum FormattingTests: TestSuite {
    static let name = "Formatting"
    static let now = Date(timeIntervalSince1970: 1_000_000)

    static let tests: [(String, () throws -> Void)] = [
        ("tokens", {
            checkEqual(Fmt.tokens(950), "950")
            checkEqual(Fmt.tokens(12_345), "12k")
            checkEqual(Fmt.tokens(1_234_567), "1.2M")
        }),
        ("cost", {
            checkEqual(Fmt.cost(0.0042), "$0.004")
            checkEqual(Fmt.cost(2.161), "$2.16")
            checkEqual(Fmt.cost(120.4), "$120")
        }),
        ("ago", {
            checkEqual(Fmt.ago(nil), "—")
            checkEqual(Fmt.ago(now.addingTimeInterval(-30), now: now), "now")
            checkEqual(Fmt.ago(now.addingTimeInterval(-300), now: now), "5m ago")
            checkEqual(Fmt.ago(now.addingTimeInterval(-3 * 3600), now: now), "3h ago")
            checkEqual(Fmt.ago(now.addingTimeInterval(-2 * 86400), now: now), "2d ago")
            checkEqual(Fmt.ago(Date().addingTimeInterval(-5)), "now")
        }),
        ("duration", {
            checkEqual(Fmt.duration(from: nil, to: now), "—")
            checkEqual(Fmt.duration(from: now, to: nil), "—")
            checkEqual(Fmt.duration(from: now, to: now.addingTimeInterval(10)), "1m")
            checkEqual(Fmt.duration(from: now, to: now.addingTimeInterval(12 * 60)), "12m")
            checkEqual(Fmt.duration(from: now, to: now.addingTimeInterval(3 * 3600 + 5 * 60)), "3h 5m")
            checkEqual(Fmt.duration(from: now, to: now.addingTimeInterval(2 * 86400 + 4 * 3600)), "2d 4h")
        }),
    ]
}
