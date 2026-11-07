import Foundation

/// Branch and uncommitted-change count per directory, cached briefly since every refresh asks.
final class GitInfo {
    let runner: CommandRunning
    let ttl: TimeInterval
    let now: () -> Date
    private var cache: [String: (status: GitStatus?, fetched: Date)] = [:]

    init(runner: CommandRunning = ProcessRunner(), ttl: TimeInterval = 15, now: @escaping () -> Date = Date.init) {
        self.runner = runner
        self.ttl = ttl
        self.now = now
    }

    /// Nil when `dir` isn't inside a git work tree.
    func status(for dir: String) -> GitStatus? {
        if let hit = cache[dir], now().timeIntervalSince(hit.fetched) < ttl { return hit.status }
        var status: GitStatus?
        let branch = runner.run("/usr/bin/git", ["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"], timeout: 3)
        if branch.succeeded {
            let porcelain = runner.run("/usr/bin/git", ["-C", dir, "status", "--porcelain"], timeout: 3).out
            status = GitStatus(branch: branch.out.trimmingCharacters(in: .whitespacesAndNewlines),
                               dirty: porcelain.split(separator: "\n").count)
        }
        cache[dir] = (status, now())
        return status
    }
}
