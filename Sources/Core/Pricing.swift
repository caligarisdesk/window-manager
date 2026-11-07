import Foundation

/// Estimated API-equivalent cost and context window size per model.
enum Pricing {
    struct Rate: Equatable {
        var input: Double      // $ per million tokens
        var output: Double
        var cacheRead: Double
    }

    /// Matched in order against the lowercased model id, so more specific entries come first.
    /// Cache writes are billed at 1.25× input (5-minute TTL) or 2× input (1-hour TTL).
    static let rates: [(match: String, rate: Rate)] = [
        ("fable", Rate(input: 10, output: 50, cacheRead: 0.25)),
        ("mythos", Rate(input: 10, output: 50, cacheRead: 0.25)),
        ("opus-5-5", Rate(input: 4, output: 20, cacheRead: 0.20)),
        ("opus-5", Rate(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4-8", Rate(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4-7", Rate(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4-6", Rate(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4-5", Rate(input: 5, output: 25, cacheRead: 0.50)),
        ("opus-4", Rate(input: 15, output: 75, cacheRead: 1.50)),
        ("sonnet-5", Rate(input: 2, output: 10, cacheRead: 0.20)),
        ("sonnet-4", Rate(input: 3, output: 15, cacheRead: 0.30)),
        ("haiku-5", Rate(input: 0.10, output: 0.50, cacheRead: 0.01)),
        ("haiku-4", Rate(input: 1, output: 5, cacheRead: 0.10)),
        ("haiku", Rate(input: 0.80, output: 4, cacheRead: 0.08)),
    ]

    /// Used for unknown models: the current default (Opus 5.5).
    static let fallback = Rate(input: 4, output: 20, cacheRead: 0.20)

    static func rate(for model: String?) -> Rate {
        let id = (model ?? "").lowercased()
        return rates.first { id.contains($0.match) }?.rate ?? fallback
    }

    static func cost(model: String?, input: Int, output: Int, cacheRead: Int,
                     cacheWrite5m: Int, cacheWrite1h: Int) -> Double {
        let r = rate(for: model)
        let dollars = Double(input) * r.input + Double(output) * r.output + Double(cacheRead) * r.cacheRead
            + Double(cacheWrite5m) * r.input * 1.25 + Double(cacheWrite1h) * r.input * 2
        return dollars / 1_000_000
    }

    private static let millionContextModels = ["fable", "mythos", "opus-5", "opus-4-6", "opus-4-7", "opus-4-8",
                                               "sonnet-5", "sonnet-4-6", "haiku-5"]

    /// 1M for models (or `[1m]` variants) with a million-token window, else 200k — unless more has
    /// already been observed, which proves the larger window.
    static func contextWindow(model: String?, observedTokens: Int) -> Int {
        let id = (model ?? "").lowercased()
        let isMillion = id.contains("[1m]") || millionContextModels.contains { id.contains($0) } || observedTokens > 200_000
        return isMillion ? 1_000_000 : 200_000
    }
}
