import Foundation

enum ModelsTests: TestSuite {
    static let name = "Models"
    static let tests: [(String, () throws -> Void)] = [
        ("statuses sort in triage order and have labels", {
            checkEqual(SessionStatus.allCases.sorted(), [.needsYou, .working, .idle, .shell])
            checkEqual(SessionStatus.allCases.map(\.label), ["Needs you", "Working", "Idle", "Shell"])
        }),
        ("claude stats derive totals, busy flag and context fill", {
            var stats = ClaudeStats(sessionId: "s")
            stats.inputTokens = 1; stats.outputTokens = 2; stats.cacheReadTokens = 3; stats.cacheWriteTokens = 4
            checkEqual(stats.totalTokens, 10)
            check(!stats.isBusy)
            stats.rawStatus = "busy"
            check(stats.isBusy)
            stats.contextTokens = 50_000
            checkEqual(stats.contextFill, 0.25)
            stats.contextTokens = 500_000
            checkEqual(stats.contextFill, 1)          // Capped.
            stats.contextWindow = 0
            checkEqual(stats.contextFill, 1)          // No division by zero.
        }),
        ("summary reports whether it has done/next text", {
            check(!AISummary(done: "", next: "", last: nil, transcriptSize: 0, createdAt: Date()).hasDoneOrNext)
            check(AISummary(done: "x", next: "", last: nil, transcriptSize: 0, createdAt: Date()).hasDoneOrNext)
        }),
        ("note keys follow the claude session or the directory", {
            var shell = Fixture.session("ttys001", cwd: "/w")
            checkEqual(shell.id, "ttys001")
            check(!shell.isClaude)
            checkEqual(shell.noteKey, "dir:/w")
            shell.cwd = nil
            checkEqual(shell.noteKey, "dir:ttys001")
            let claude = Fixture.session(claude: ClaudeStats(sessionId: "abc"))
            check(claude.isClaude)
            checkEqual(claude.noteKey, "claude:abc")
        }),
        ("last activity prefers the transcript, then the status timestamp", {
            var stats = ClaudeStats(sessionId: "s")
            stats.statusUpdatedAt = Date(timeIntervalSince1970: 1)
            checkEqual(Fixture.session(claude: stats).lastActivity, Date(timeIntervalSince1970: 1))
            stats.lastActivity = Date(timeIntervalSince1970: 2)
            checkEqual(Fixture.session(claude: stats).lastActivity, Date(timeIntervalSince1970: 2))
            checkNil(Fixture.session().lastActivity)
        }),
        ("title falls back from AI title to tab title to directory to tty", {
            var stats = ClaudeStats(sessionId: "s")
            stats.aiTitle = "Fix login"
            var s = Fixture.session(cwd: "/code/app", claude: stats)
            s.tabTitle = "✳ Tab title"
            checkEqual(s.title, "Fix login")
            s.claude?.aiTitle = ""
            checkEqual(s.title, "Tab title")           // Status glyph stripped.
            s.tabTitle = "✳ "
            checkEqual(s.title, "app")
            s.claude = nil
            s.tabTitle = "ignored for shells"
            checkEqual(s.title, "app")
            s.cwd = nil
            checkEqual(s.title, "ttys000")
        }),
        ("short path abbreviates the home directory", {
            checkEqual(Fixture.session(cwd: "/Users/me/code").shortPath(home: "/Users/me"), "~/code")
            checkEqual(Fixture.session(cwd: "/opt/x").shortPath(home: "/Users/me"), "/opt/x")
            checkEqual(Fixture.session(cwd: nil).shortPath(home: "/Users/me"), "—")
            check(!Fixture.session(cwd: "/").shortPath().isEmpty)
        }),
        ("accent hue is stable per directory and in range", {
            let a = Fixture.session(cwd: "/a").accentHue
            checkEqual(a, Fixture.session("ttys009", cwd: "/a").accentHue)
            check(a != Fixture.session(cwd: "/b").accentHue)
            check(a >= 0 && a < 1)
            checkEqual(Fixture.session("ttys1", cwd: nil).accentHue, Fixture.session("ttys1", cwd: nil).accentHue)
        }),
    ]
}

enum CommandRunnerTests: TestSuite {
    static let name = "CommandRunner"
    static let tests: [(String, () throws -> Void)] = [
        ("captures stdout and exit status", {
            let result = ProcessRunner().run("/bin/echo", ["hello"])
            checkEqual(result, CommandResult(out: "hello\n", status: 0))
            check(result.succeeded)
            check(!ProcessRunner().run("/usr/bin/false", []).succeeded)
        }),
        ("feeds stdin and honours the working directory", {
            checkEqual(ProcessRunner().run("/bin/cat", [], stdin: "piped", cwd: nil, timeout: 5).out, "piped")
            let dir = TempDir()
            let pwd = ProcessRunner().run("/bin/pwd", [], stdin: nil, cwd: dir.path, timeout: 5).out
            check(pwd.hasSuffix(dir.url.lastPathComponent + "\n"), "pwd was \(pwd)")
        }),
        ("reports -1 for a missing executable", {
            checkEqual(ProcessRunner().run("/nonexistent/tool", []).status, -1)
        }),
        ("kills commands that exceed the timeout", {
            let start = Date()
            let result = ProcessRunner().run("/bin/sleep", ["5"], timeout: 0.3)
            check(!result.succeeded)
            check(Date().timeIntervalSince(start) < 3, "timeout not enforced")
        }),
        ("osascript passes the script with -e", {
            let fake = FakeRunner { _ in CommandResult(out: "ok", status: 0) }
            checkEqual(fake.osascript("return 1"), "ok")
            checkEqual(fake.calls, [FakeRunner.Call(path: "/usr/bin/osascript", args: ["-e", "return 1"], stdin: nil, cwd: nil)])
        }),
    ]
}

enum TerminalClientTests: TestSuite {
    static let name = "TerminalClient"
    static let bounds = WindowBounds(left: 1, top: 2, right: 3, bottom: 4)

    static let tests: [(String, () throws -> Void)] = [
        ("defaults to the real process runner", {
            check(TerminalClient().runner is ProcessRunner)
        }),
        ("snapshot parses osascript output into tabs", {
            let output = "17\t1\t0, 25, 800, 600\tfalse\t/dev/ttys003\t✳ Title\ttrue\ttrue\n"
                + "17\t2\t0,25,800,600\ttrue\tttys004\t\tfalse\tfalse\n"
            let fake = FakeRunner { _ in CommandResult(out: output, status: 0) }
            let tabs = TerminalClient(runner: fake).snapshot()
            checkEqual(tabs, [
                TerminalTab(windowId: 17, tabIndex: 1, bounds: WindowBounds(left: 0, top: 25, right: 800, bottom: 600),
                            miniaturized: false, tty: "ttys003", title: "✳ Title", busy: true, selected: true),
                TerminalTab(windowId: 17, tabIndex: 2, bounds: WindowBounds(left: 0, top: 25, right: 800, bottom: 600),
                            miniaturized: true, tty: "ttys004", title: "", busy: false, selected: false),
            ])
            check(fake.calls.first?.args.last == TerminalClient.snapshotScript)
            check(TerminalClient.snapshotScript.contains("on clean(s)"))
        }),
        ("malformed snapshot lines are skipped", {
            checkNil(TerminalClient.parseTabLine("too\tfew"))
            checkNil(TerminalClient.parseTabLine("x\t1\t0,0,1,1\tfalse\tt\tn\tfalse\tfalse"))
            checkNil(TerminalClient.parseTabLine("1\tx\t0,0,1,1\tfalse\tt\tn\tfalse\tfalse"))
            checkNil(TerminalClient.parseTabLine("1\t1\t0,0,1\tfalse\tt\tn\tfalse\tfalse"))
            checkEqual(TerminalClient.parseSnapshot("garbage\n\n").count, 0)
            checkNil(TerminalClient.parseBounds("a,b,c,d"))
        }),
        ("focus selects the tab and optionally resizes", {
            let fake = FakeRunner()
            TerminalClient(runner: fake).focus(windowId: 9, tabIndex: 2, bounds: bounds)
            TerminalClient(runner: fake).focus(windowId: 9, tabIndex: 2, bounds: nil)
            let withResize = fake.calls[0].args[1], withoutResize = fake.calls[1].args[1]
            check(withResize.contains("window id 9") && withResize.contains("tab 2 of w"))
            check(withResize.contains("set bounds of w to {1, 2, 3, 4}"))
            check(!withoutResize.contains("set bounds"))
        }),
        ("setBounds moves all windows in one script and skips empty requests", {
            let fake = FakeRunner()
            let client = TerminalClient(runner: fake)
            client.setBounds([], activate: true)
            checkEqual(fake.calls.count, 0)
            client.setBounds([WindowPlacement(windowId: 1, bounds: bounds), WindowPlacement(windowId: 2, bounds: bounds)], activate: true)
            client.setBounds([WindowPlacement(windowId: 3, bounds: bounds)], activate: false)
            let first = fake.calls[0].args[1], second = fake.calls[1].args[1]
            check(first.contains("window id 1") && first.contains("window id 2") && first.contains("activate"))
            check(second.contains("window id 3") && !second.contains("activate"))
        }),
        ("bounds render as an AppleScript list", {
            checkEqual(TerminalClient.literal(bounds), "{1, 2, 3, 4}")
        }),
    ]
}

enum ProcessScannerTests: TestSuite {
    static let name = "ProcessScanner"

    static let ps = """
      100     1 ttys000 Ss     login -pf me
      101   100 ttys000 S      -zsh
      102   101 ttys000 S+     claude
      103   102 ttys000 S+     caffeinate -i
      200     1 ttys001 Ss     login -pf me
      201   200 ttys001 S+     /bin/zsh -l
      300     1 ttys002 Ss+    /bin/bash
      301   300 ttys002 S+     npm run dev
      400     1 ttys009 S      other tty
    bad line
      x     1 ttys000 S      not a pid
    """

    static let tests: [(String, () throws -> Void)] = [
        ("defaults to the real process runner", {
            check(ProcessScanner().runner is ProcessRunner)
        }),
        ("ps output groups processes per wanted tty", {
            let info = ProcessScanner.parsePS(ps, ttys: ["ttys000", "ttys001", "ttys002"])
            checkEqual(info["ttys000"]?.pids, [100, 101, 102, 103])
            checkEqual(info["ttys000"]?.shellPid, 101)              // login is not the shell.
            checkEqual(info["ttys000"]?.foregroundPid, 103)         // Newest non-shell foreground process.
            checkEqual(info["ttys001"]?.foregroundPid, nil)         // Only the shell is in the foreground.
            checkEqual(info["ttys001"]?.shellPid, 201)
            checkEqual(info["ttys002"]?.foregroundCommand, "npm run dev")
            checkNil(info["ttys009"])
        }),
        ("cwd targets prefer the foreground process over the shell", {
            let info = ["a": TTYInfo(shellPid: 1, foregroundPid: 2), "b": TTYInfo(shellPid: 3), "c": TTYInfo()]
            checkEqual(ProcessScanner.cwdTargets(info), [2: "a", 3: "b"])
        }),
        ("lsof output assigns directories to ttys", {
            var info = ["a": TTYInfo(), "b": TTYInfo()]
            ProcessScanner.applyLsof("p2\nfcwd\nn/work/a\np9\nn/ignored\np3\nn/work/b\n", targets: [2: "a", 3: "b"], to: &info)
            checkEqual(info["a"]?.cwd, "/work/a")
            checkEqual(info["b"]?.cwd, "/work/b")
        }),
        ("scan runs ps then one lsof for all ttys", {
            let fake = FakeRunner(outputs: ["ps": ps, "lsof": "p103\nn/proj\np201\nn/home\n"])
            let info = ProcessScanner(runner: fake).scan(ttys: ["ttys000", "ttys001"])
            checkEqual(info["ttys000"]?.cwd, "/proj")
            checkEqual(info["ttys001"]?.cwd, "/home")
            checkEqual(fake.calls.count, 2)
            checkEqual(fake.calls[1].args.last, "103,201")
        }),
        ("scan skips lsof when nothing matched", {
            let fake = FakeRunner(outputs: ["ps": ps])
            checkEqual(ProcessScanner(runner: fake).scan(ttys: ["ttys777"]), [:])
            checkEqual(fake.calls.count, 1)
        }),
        ("base names strip paths, arguments and login dashes", {
            checkEqual(ProcessScanner.baseName("/bin/zsh -l"), "zsh")
            checkEqual(ProcessScanner.baseName("-zsh"), "zsh")
            checkEqual(ProcessScanner.baseName(""), "")
        }),
    ]
}
