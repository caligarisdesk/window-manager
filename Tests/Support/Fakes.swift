import Foundation

/// A `CommandRunning` that records calls and answers from a handler. Thread-safe, since the
/// summarizer calls it from background operations.
final class FakeRunner: CommandRunning {
    struct Call: Equatable {
        var path: String
        var args: [String]
        var stdin: String?
        var cwd: String?
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    var handler: (Call) -> CommandResult

    init(handler: @escaping (Call) -> CommandResult = { _ in CommandResult(out: "", status: 0) }) {
        self.handler = handler
    }

    /// Answers by executable name, e.g. `["ps": psOutput, "lsof": lsofOutput]`.
    convenience init(outputs: [String: String]) {
        self.init { call in
            CommandResult(out: outputs[(call.path as NSString).lastPathComponent] ?? "", status: 0)
        }
    }

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func run(_ path: String, _ args: [String], stdin: String?, cwd: String?, timeout: TimeInterval) -> CommandResult {
        let call = Call(path: path, args: args, stdin: stdin, cwd: cwd)
        lock.lock()
        recorded.append(call)
        lock.unlock()
        return handler(call)
    }
}

/// A fresh temporary directory, removed when the value is released.
final class TempDir {
    let url: URL
    var path: String { url.path }

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-tests-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ relativePath: String, _ contents: String) -> String {
        let file = url.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? contents.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    func append(_ relativePath: String, _ contents: String) {
        let handle = FileHandle(forWritingAtPath: url.appendingPathComponent(relativePath).path)!
        handle.seekToEndOfFile()
        handle.write(Data(contents.utf8))
        try? handle.close()
    }
}

/// Builders for test fixtures.
enum Fixture {
    static func tab(_ tty: String, window: Int = 1, index: Int = 1, title: String = "") -> TerminalTab {
        TerminalTab(windowId: window, tabIndex: index, bounds: WindowBounds(left: 0, top: 0, right: 100, bottom: 100),
                    miniaturized: false, tty: tty, title: title, busy: false, selected: true)
    }

    static func session(_ tty: String = "ttys000", window: Int = 1, status: SessionStatus = .shell,
                        cwd: String? = "/tmp/project", claude: ClaudeStats? = nil, lastActivity: Date? = nil) -> TerminalSession {
        var stats = claude
        if let lastActivity { stats = (stats ?? ClaudeStats(sessionId: "s-\(tty)")); stats?.lastActivity = lastActivity }
        return TerminalSession(tty: tty, windowId: window, tabIndex: 1,
                               bounds: WindowBounds(left: 0, top: 0, right: 100, bottom: 100),
                               miniaturized: false, tabTitle: "", cwd: cwd, foreground: nil, claude: stats,
                               git: nil, summary: nil, status: status)
    }

    /// One JSONL line.
    static func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
    }

    static func user(_ content: Any, extra: [String: Any] = [:]) -> [String: Any] {
        ["type": "user", "message": ["role": "user", "content": content]].merging(extra) { $1 }
    }

    static func assistant(id: String? = "msg_1", model: String? = "claude-opus-5-5", content: [[String: Any]]? = nil,
                          usage: [String: Any]? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        var message: [String: Any] = ["role": "assistant"]
        if let id { message["id"] = id }
        if let model { message["model"] = model }
        if let content { message["content"] = content }
        if let usage { message["usage"] = usage }
        return ["type": "assistant", "message": message].merging(extra) { $1 }
    }

    static func usage(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, cacheWrite1h: Int = 0) -> [String: Any] {
        ["input_tokens": input, "output_tokens": output, "cache_read_input_tokens": cacheRead,
         "cache_creation_input_tokens": cacheWrite, "cache_creation": ["ephemeral_1h_input_tokens": cacheWrite1h]]
    }
}
