import Foundation

/// A Codable value persisted as a JSON file.
struct JSONFile<Value: Codable> {
    let url: URL

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    @discardableResult
    func save(_ value: Value) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

enum AppPaths {
    /// `~/Library/Application Support/Shelf`, created if needed.
    static func supportDirectory(base: URL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                                       in: .userDomainMask)[0]) -> URL {
        let dir = base.appendingPathComponent("Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// User notes, keyed by `TerminalSession.noteKey`.
struct NotesBook: Equatable {
    private(set) var notes: [String: [Note]] = [:]

    init(notes: [String: [Note]] = [:]) {
        self.notes = notes
    }

    /// Adds a note unless it is blank. Returns whether anything changed.
    @discardableResult
    mutating func add(_ text: String, to key: String, at date: Date = Date()) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        notes[key, default: []].append(Note(text: trimmed, createdAt: date))
        return true
    }

    mutating func delete(_ id: UUID, from key: String) {
        notes[key]?.removeAll { $0.id == id }
        if notes[key]?.isEmpty == true { notes[key] = nil }
    }

    subscript(key: String) -> [Note] { notes[key] ?? [] }
}
