import Foundation

/// What is running on one tty.
struct TTYInfo: Equatable {
    var pids: [Int32] = []
    var shellPid: Int32?
    var foregroundPid: Int32?
    var foregroundCommand: String?
    var cwd: String?
}

/// Maps ttys to their processes and working directories using `ps` and `lsof`.
struct ProcessScanner {
    var runner: CommandRunning = ProcessRunner()

    static let shells: Set<String> = ["zsh", "bash", "fish", "sh", "tcsh", "ksh", "login"]

    func scan(ttys: [String]) -> [String: TTYInfo] {
        let psOutput = runner.run("/bin/ps", ["-axo", "pid=,ppid=,tty=,stat=,command="]).out
        var info = Self.parsePS(psOutput, ttys: Set(ttys))

        // One lsof call resolves the cwd of every tty's foreground process (or its shell).
        let targets = Self.cwdTargets(info)
        if !targets.isEmpty {
            let pidList = targets.keys.sorted().map(String.init).joined(separator: ",")
            let lsofOutput = runner.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fpn", "-p", pidList]).out
            Self.applyLsof(lsofOutput, targets: targets, to: &info)
        }
        return info
    }

    /// Parses `ps -axo pid=,ppid=,tty=,stat=,command=` output, keeping only the wanted ttys.
    static func parsePS(_ output: String, ttys wanted: Set<String>) -> [String: TTYInfo] {
        var info: [String: TTYInfo] = [:]
        var foreground: [String: [(pid: Int32, command: String)]] = [:]

        for line in output.split(separator: "\n") {
            let cols = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard cols.count == 5, let pid = Int32(cols[0]) else { continue }
            let tty = String(cols[2])
            guard wanted.contains(tty) else { continue }
            // ps pads columns, so the command keeps leading spaces after the split.
            let stat = cols[3], command = cols[4].trimmingCharacters(in: .whitespaces)

            var entry = info[tty] ?? TTYInfo()
            entry.pids.append(pid)
            let exe = baseName(command)
            if shells.contains(exe), exe != "login", entry.shellPid == nil { entry.shellPid = pid }
            if stat.contains("+") { foreground[tty, default: []].append((pid, command)) }
            info[tty] = entry
        }

        // The foreground job is the newest process in the foreground group that isn't a shell.
        for (tty, candidates) in foreground {
            if let job = candidates.filter({ !shells.contains(baseName($0.command)) }).max(by: { $0.pid < $1.pid }) {
                info[tty]?.foregroundPid = job.pid
                info[tty]?.foregroundCommand = job.command
            }
        }
        return info
    }

    /// pid → tty for the process whose cwd best describes each tty.
    static func cwdTargets(_ info: [String: TTYInfo]) -> [Int32: String] {
        var targets: [Int32: String] = [:]
        for (tty, entry) in info {
            if let pid = entry.foregroundPid ?? entry.shellPid { targets[pid] = tty }
        }
        return targets
    }

    /// Applies `lsof -Fpn` output (alternating `p<pid>` / `n<path>` lines).
    static func applyLsof(_ output: String, targets: [Int32: String], to info: inout [String: TTYInfo]) {
        var currentPid: Int32?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPid, let tty = targets[pid] {
                info[tty]?.cwd = String(line.dropFirst())
            }
        }
    }

    /// "/bin/zsh -l" → "zsh"; "-zsh" (login shell) → "zsh".
    static func baseName(_ command: String) -> String {
        let executable = command.split(separator: " ").first.map(String.init) ?? command
        return (executable as NSString).lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
