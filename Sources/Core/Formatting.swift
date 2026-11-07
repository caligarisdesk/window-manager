import Foundation

/// Compact text for card metrics.
enum Fmt {
    /// 950 → "950", 12_345 → "12k", 1_234_567 → "1.2M".
    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    /// Fewer decimals as amounts grow: "$0.004", "$2.16", "$120".
    static func cost(_ dollars: Double) -> String {
        if dollars >= 100 { return String(format: "$%.0f", dollars) }
        if dollars >= 1 { return String(format: "$%.2f", dollars) }
        return String(format: "$%.3f", dollars)
    }

    /// "now", "5m ago", "3h ago", "2d ago".
    static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let s = Int(now.timeIntervalSince(date))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60)m ago"
        case ..<86400: return "\(s / 3600)h ago"
        default: return "\(s / 86400)d ago"
        }
    }

    /// Span between two dates: "12m", "3h 5m", "2d 4h".
    static func duration(from start: Date?, to end: Date?) -> String {
        guard let start, let end else { return "—" }
        let s = Int(end.timeIntervalSince(start))
        if s < 3600 { return "\(max(1, s / 60))m" }
        if s < 86400 { return "\(s / 3600)h \(s % 3600 / 60)m" }
        return "\(s / 86400)d \(s % 86400 / 3600)h"
    }
}
