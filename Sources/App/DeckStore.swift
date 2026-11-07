import AppKit
import Combine

/// The dashboard's state. Gathers data off the main thread every few seconds and performs card actions.
@MainActor
final class DeckStore: NSObject, ObservableObject {
    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var tiled = false
    @Published private(set) var notes = NotesBook()
    @Published var filter: DeckFilter = .all
    @Published var search = ""
    @Published var aiSummariesEnabled = UserDefaults.standard.object(forKey: "aiSummaries") as? Bool ?? true {
        didSet { UserDefaults.standard.set(aiSummariesEnabled, forKey: "aiSummaries") }
    }

    static let refreshInterval: TimeInterval = 3

    private let terminal = TerminalClient()
    private let processes = ProcessScanner()
    private let claudeStore = ClaudeSessionStore()
    private let git = GitInfo()
    private let summarizer: Summarizer
    private let notesFile: JSONFile<[String: [Note]]>
    private let worker = DispatchQueue(label: "shelf.refresh", qos: .utility)
    private var timer: Timer?
    private var refreshing = false
    /// Window positions from before tiling, restored when tiling is toggled off.
    private var savedBounds: [Int: WindowBounds] = [:]

    override init() {
        let support = AppPaths.supportDirectory()
        notesFile = JSONFile(url: support.appendingPathComponent("notes.json"))
        summarizer = Summarizer(claudePath: Summarizer.locateClaude(),
                                cacheFile: JSONFile(url: support.appendingPathComponent("summaries.json")),
                                workDir: support.path)
        super.init()
        notes = NotesBook(notes: notesFile.load() ?? [:])
        summarizer.onUpdate = { [weak self] in self?.refresh() }
        refresh()
        let t = Timer(timeInterval: Self.refreshInterval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func tick() { refresh() }

    // MARK: - Derived state

    var visible: [TerminalSession] { Triage.visible(sessions, filter: filter, search: search) }
    func count(_ f: DeckFilter) -> Int { sessions.filter(f.includes).count }
    var totalCost: Double { sessions.compactMap { $0.claude?.costUSD }.reduce(0, +) }
    var totalTokens: Int { sessions.compactMap { $0.claude?.totalTokens }.reduce(0, +) }

    // MARK: - Refresh

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let summarize = aiSummariesEnabled
        let notes = notes.notes
        worker.async { [terminal, processes, claudeStore, git, summarizer] in
            let tabs = TerminalBridge.isTerminalRunning ? terminal.snapshot() : []
            let procs = processes.scan(ttys: tabs.map(\.tty))
            let files = claudeStore.sessionFiles()
            let assembler = SessionAssembler(
                claudeStats: claudeStore.stats(for:),
                gitStatus: git.status(for:),
                summary: summarizer.summary(for:),
                notes: notes)
            let sessions = assembler.assemble(tabs: tabs, processes: procs, sessionFiles: files)
            claudeStore.retain(sessionIds: Set(sessions.compactMap { $0.claude?.sessionId }))
            if summarize { sessions.compactMap(\.claude).forEach { summarizer.consider($0) } }

            DispatchQueue.main.async {
                self.sessions = sessions
                self.lastRefresh = Date()
                self.refreshing = false
            }
        }
    }

    // MARK: - Card actions

    /// Brings the session's window forward, sized to fill the screen.
    func expand(_ s: TerminalSession) {
        let bounds = ScreenGeometry.layout().expanded()
        TerminalBridge.run { $0.focus(windowId: s.windowId, tabIndex: s.tabIndex, bounds: bounds) }
        NSApp.hide(nil)
    }

    /// Brings the session's window forward without resizing it.
    func focus(_ s: TerminalSession) {
        TerminalBridge.run { $0.focus(windowId: s.windowId, tabIndex: s.tabIndex, bounds: nil) }
        NSApp.hide(nil)
    }

    func resummarize(_ s: TerminalSession) {
        if let claude = s.claude { summarizer.consider(claude, force: true) }
    }

    /// Tiles the windows of the visible cards into a grid; calling again restores their positions.
    func toggleTile() {
        if tiled {
            let restore = savedBounds.map { WindowPlacement(windowId: $0.key, bounds: $0.value) }
            TerminalBridge.run { $0.setBounds(restore, activate: false) }
            savedBounds = [:]
            tiled = false
            return
        }
        let windows = Triage.distinctWindows(visible)
        guard !windows.isEmpty else { return }
        savedBounds = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowId, $0.bounds) })
        let cells = ScreenGeometry.layout().grid(count: windows.count)
        let placements = zip(windows, cells).map { WindowPlacement(windowId: $0.windowId, bounds: $1) }
        TerminalBridge.run { $0.setBounds(placements, activate: true) }
        tiled = true
        NSApp.hide(nil)
    }

    // MARK: - Notes

    func addNote(_ text: String, to key: String) {
        guard notes.add(text, to: key) else { return }
        notesChanged()
    }

    func deleteNote(_ id: UUID, from key: String) {
        notes.delete(id, from: key)
        notesChanged()
    }

    private func notesChanged() {
        notesFile.save(notes.notes)
        // Show the change right away instead of waiting for the next refresh.
        sessions = sessions.map { var s = $0; s.notes = notes[s.noteKey]; return s }
    }
}

/// Main-thread-safe access to Terminal: AppleScript calls run on a background queue.
enum TerminalBridge {
    private static let queue = DispatchQueue(label: "shelf.terminal", qos: .userInitiated)
    private static let client = TerminalClient()

    static var isTerminalRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty
    }

    static func run(_ action: @escaping (TerminalClient) -> Void) {
        queue.async { action(client) }
    }
}

/// Reads screen geometry from AppKit for `WindowLayout`.
enum ScreenGeometry {
    /// Layout for the screen under the mouse, so windows land where the user is looking.
    static func layout() -> WindowLayout {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        return WindowLayout(primaryHeight: NSScreen.screens.first?.frame.height ?? screen.frame.height,
                            frame: screen.visibleFrame)
    }
}
