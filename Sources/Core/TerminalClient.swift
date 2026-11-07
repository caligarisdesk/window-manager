import Foundation

/// Reads and arranges Terminal.app windows through its AppleScript dictionary.
///
/// Scripts only ever interpolate integers, so window titles can't inject AppleScript.
struct TerminalClient {
    var runner: CommandRunning = ProcessRunner()

    /// Every tab of every Terminal window.
    func snapshot() -> [TerminalTab] {
        Self.parseSnapshot(runner.osascript(Self.snapshotScript))
    }

    /// Selects a tab, raises its window and activates Terminal, optionally resizing the window.
    func focus(windowId: Int, tabIndex: Int, bounds: WindowBounds?) {
        _ = runner.osascript(Self.focusScript(windowId: windowId, tabIndex: tabIndex, bounds: bounds))
    }

    /// Moves many windows in one AppleScript round-trip.
    func setBounds(_ placements: [WindowPlacement], activate: Bool) {
        guard !placements.isEmpty else { return }
        _ = runner.osascript(Self.setBoundsScript(placements, activate: activate))
    }

    // MARK: - Scripts

    /// One line per tab: windowId, tabIndex, "l,t,r,b", miniaturized, tty, title, busy, selected (tab-separated).
    /// `tab` is a Terminal class name, so the separator is built outside the `tell` block, and titles are
    /// stripped of tabs and line breaks so they can't break the format.
    static let snapshotScript = """
    on clean(s)
        set AppleScript's text item delimiters to {character id 9, linefeed, return}
        set parts to text items of s
        set AppleScript's text item delimiters to " "
        set s to parts as text
        set AppleScript's text item delimiters to ""
        return s
    end clean

    set sep to character id 9
    set out to ""
    tell application "Terminal"
        repeat with w in windows
            try
                set wid to id of w
                set b to bounds of w
                set mini to miniaturized of w
                set bs to ((item 1 of b) as text) & "," & ((item 2 of b) as text) & "," & ((item 3 of b) as text) & "," & ((item 4 of b) as text)
                set ti to 0
                repeat with t in tabs of w
                    set ti to ti + 1
                    set ct to ""
                    try
                        set ct to my clean(custom title of t)
                    end try
                    set out to out & wid & sep & ti & sep & bs & sep & mini & sep & (tty of t) & sep & ct & sep & (busy of t) & sep & (selected of t) & linefeed
                end repeat
            end try
        end repeat
    end tell
    return out
    """

    static func focusScript(windowId: Int, tabIndex: Int, bounds: WindowBounds?) -> String {
        let resize = bounds.map { "set bounds of w to \(literal($0))" } ?? ""
        return """
        tell application "Terminal"
            set w to window id \(windowId)
            set miniaturized of w to false
            set selected tab of w to tab \(tabIndex) of w
            \(resize)
            set index of w to 1
            activate
        end tell
        """
    }

    static func setBoundsScript(_ placements: [WindowPlacement], activate: Bool) -> String {
        let moves = placements.map { p in
            """
                try
                    set w to window id \(p.windowId)
                    set miniaturized of w to false
                    set bounds of w to \(literal(p.bounds))
                end try
            """
        }.joined(separator: "\n")
        return """
        tell application "Terminal"
        \(moves)
        \(activate ? "activate" : "")
        end tell
        """
    }

    static func literal(_ b: WindowBounds) -> String {
        "{\(b.left), \(b.top), \(b.right), \(b.bottom)}"
    }

    // MARK: - Parsing

    static func parseSnapshot(_ output: String) -> [TerminalTab] {
        output.split(separator: "\n").compactMap { parseTabLine(String($0)) }
    }

    /// Parses one snapshot line; returns nil for anything malformed.
    static func parseTabLine(_ line: String) -> TerminalTab? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 8,
              let windowId = Int(fields[0]),
              let tabIndex = Int(fields[1]),
              let bounds = parseBounds(fields[2]) else { return nil }
        return TerminalTab(
            windowId: windowId, tabIndex: tabIndex, bounds: bounds,
            miniaturized: fields[3] == "true",
            tty: fields[4].replacingOccurrences(of: "/dev/", with: ""),
            title: fields[5], busy: fields[6] == "true", selected: fields[7] == "true")
    }

    static func parseBounds(_ text: String) -> WindowBounds? {
        let n = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard n.count == 4 else { return nil }
        return WindowBounds(left: n[0], top: n[1], right: n[2], bottom: n[3])
    }
}

struct WindowPlacement: Equatable {
    var windowId: Int
    var bounds: WindowBounds
}
