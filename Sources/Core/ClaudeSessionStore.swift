import Foundation

/// Live Claude Code sessions (`~/.claude/sessions/<pid>.json`) and their parsed transcripts
/// (`~/.claude/projects/<cwd-slug>/<sessionId>.jsonl`). Transcripts are read incrementally.
final class ClaudeSessionStore {
    struct SessionFile: Decodable, Equatable {
        let pid: Int32
        let sessionId: String
        let cwd: String?
        let name: String?
        let status: String?
        let statusUpdatedAt: Double?   // milliseconds since 1970
    }

    private struct Transcript {
        var path: String
        var offset: UInt64 = 0
        var parser: TranscriptParser
    }

    let claudeDir: String
    /// Largest slice of a transcript held in memory at once.
    let maxReadBytes: Int
    private let fm = FileManager.default
    private var transcripts: [String: Transcript] = [:]   // by sessionId
    private var pathCache: [String: String] = [:]

    init(claudeDir: String = NSHomeDirectory() + "/.claude", maxReadBytes: Int = 8 << 20) {
        self.claudeDir = claudeDir
        self.maxReadBytes = maxReadBytes
    }

    /// Session descriptors keyed by the pid of the `claude` process.
    func sessionFiles() -> [Int32: SessionFile] {
        let dir = claudeDir + "/sessions"
        let names = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        var files: [Int32: SessionFile] = [:]
        for name in names where name.hasSuffix(".json") {
            guard let data = fm.contents(atPath: dir + "/" + name),
                  let file = try? JSONDecoder().decode(SessionFile.self, from: data) else { continue }
            files[file.pid] = file
        }
        return files
    }

    /// Stats for a session, reading whatever the transcript gained since the last call.
    func stats(for file: SessionFile) -> ClaudeStats {
        var stats: ClaudeStats
        if let path = transcriptPath(sessionId: file.sessionId, cwd: file.cwd) {
            var transcript = transcripts[file.sessionId].flatMap { $0.path == path ? $0 : nil }
                ?? Transcript(path: path, parser: TranscriptParser(sessionId: file.sessionId))
            readNewLines(into: &transcript)
            transcripts[file.sessionId] = transcript
            stats = transcript.parser.stats
            stats.transcriptSize = transcript.offset
        } else {
            stats = ClaudeStats(sessionId: file.sessionId)
        }
        stats.name = file.name
        stats.rawStatus = file.status ?? "idle"
        stats.statusUpdatedAt = file.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        return stats
    }

    /// Drops cached transcripts for sessions that are no longer running.
    func retain(sessionIds: Set<String>) {
        transcripts = transcripts.filter { sessionIds.contains($0.key) }
        pathCache = pathCache.filter { sessionIds.contains($0.key) }
    }

    var cachedSessionIds: Set<String> { Set(transcripts.keys) }

    /// Claude Code names project folders after the cwd with every non-alphanumeric character as "-".
    static func projectSlug(for cwd: String) -> String {
        String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    func transcriptPath(sessionId: String, cwd: String?) -> String? {
        if let cached = pathCache[sessionId], fm.fileExists(atPath: cached) { return cached }
        let projects = claudeDir + "/projects"
        let fileName = sessionId + ".jsonl"
        var candidates: [String] = []
        if let cwd { candidates.append("\(projects)/\(Self.projectSlug(for: cwd))/\(fileName)") }
        // Fallback: the slug rule may change; look in every project folder.
        candidates += ((try? fm.contentsOfDirectory(atPath: projects)) ?? []).map { "\(projects)/\($0)/\(fileName)" }
        let found = candidates.first { fm.fileExists(atPath: $0) }
        pathCache[sessionId] = found
        return found
    }

    private func readNewLines(into transcript: inout Transcript) {
        guard let handle = FileHandle(forReadingAtPath: transcript.path) else { return }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        if size < transcript.offset {   // The file was rewritten; start over.
            transcript = Transcript(path: transcript.path, parser: TranscriptParser(sessionId: transcript.parser.stats.sessionId))
        }
        while transcript.offset < size {
            handle.seek(toFileOffset: transcript.offset)
            let chunk = handle.readData(ofLength: maxReadBytes)
            guard let lines = TranscriptParser.completeLines(in: chunk) else {
                // No newline in this slice: a partial trailing line, or one line longer than the slice.
                if chunk.count < maxReadBytes { break }
                transcript.offset += UInt64(chunk.count)   // Skip an absurdly long line.
                continue
            }
            transcript.parser.ingest(lines)
            transcript.offset += UInt64(lines.count)
        }
    }
}
