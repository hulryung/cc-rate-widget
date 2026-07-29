import Foundation

/// Token counts for one assistant event, split the way Anthropic bills them.
/// Cache writes are separated by TTL: a 1-hour entry costs 2x input, a 5-minute
/// entry 1.25x, so collapsing them into one bucket materially understates cost.
struct TokenUsage: Equatable {
    let input: Int
    let output: Int
    let cacheWrite5m: Int      // cache_creation.ephemeral_5m_input_tokens
    let cacheWrite1h: Int      // cache_creation.ephemeral_1h_input_tokens
    let cacheRead: Int         // cache_read_input_tokens

    init(input: Int, output: Int, cacheWrite5m: Int, cacheWrite1h: Int, cacheRead: Int) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }

    /// For callers with only a combined cache-write figure (older logs, tests).
    /// Charged at the 5-minute rate, matching the pre-1h-cache billing.
    init(input: Int, output: Int, cacheWrite: Int, cacheRead: Int) {
        self.init(input: input, output: output,
                  cacheWrite5m: cacheWrite, cacheWrite1h: 0, cacheRead: cacheRead)
    }

    var cacheWrite: Int { cacheWrite5m + cacheWrite1h }

    /// Tokens that count toward utilization caps. Cache reads are essentially free.
    var utilizationTokens: Int { input + output + cacheWrite }
}

enum Pricing {
    /// $ per million tokens. Cache rates are derived rather than stored: Anthropic's
    /// multipliers are uniform across models, so only input/output can drift.
    private struct Rate {
        let input: Double
        let output: Double

        var cacheWrite5m: Double { input * 1.25 }
        var cacheWrite1h: Double { input * 2.00 }
        var cacheRead: Double    { input * 0.10 }
    }

    /// Matched by prefix, first hit wins — so specific IDs must precede the family
    /// fallbacks below them. The fallbacks are the point: when Anthropic ships a model
    /// this table has never heard of, it prices at its family's rate instead of silently
    /// costing $0, which is how the Claude 5 generation went unpriced here for months.
    private static let rates: [(prefix: String, rate: Rate)] = [
        // Fable/Mythos tier
        ("claude-fable-5",  Rate(input: 10.00, output: 50.00)),
        ("claude-mythos-5", Rate(input: 10.00, output: 50.00)),
        // Opus tier — 4.5 onward is $5/$25 (repriced down from $15/$75)
        ("claude-opus-5",   Rate(input:  5.00, output: 25.00)),
        ("claude-opus-4",   Rate(input:  5.00, output: 25.00)),
        // Sonnet tier
        ("claude-sonnet-5", Rate(input:  3.00, output: 15.00)),
        ("claude-sonnet-4", Rate(input:  3.00, output: 15.00)),
        // Haiku tier
        ("claude-haiku-4",  Rate(input:  1.00, output:  5.00)),

        // Family fallbacks for unrecognized versions.
        ("claude-fable",    Rate(input: 10.00, output: 50.00)),
        ("claude-mythos",   Rate(input: 10.00, output: 50.00)),
        ("claude-opus",     Rate(input:  5.00, output: 25.00)),
        ("claude-sonnet",   Rate(input:  3.00, output: 15.00)),
        ("claude-haiku",    Rate(input:  1.00, output:  5.00)),

        // Bare aliases Claude Code writes when a model shorthand is configured.
        ("opus",            Rate(input:  5.00, output: 25.00)),
        ("sonnet",          Rate(input:  3.00, output: 15.00)),
        ("haiku",           Rate(input:  1.00, output:  5.00)),
    ]

    /// USD for one event. Unknown models cost 0 — their tokens still count toward
    /// utilization, they just can't be priced.
    static func cost(model: String, usage: TokenUsage) -> Double {
        guard let r = rates.first(where: { model.hasPrefix($0.prefix) })?.rate else { return 0 }
        return (Double(usage.input)        * r.input
              + Double(usage.output)       * r.output
              + Double(usage.cacheWrite5m) * r.cacheWrite5m
              + Double(usage.cacheWrite1h) * r.cacheWrite1h
              + Double(usage.cacheRead)    * r.cacheRead) / 1_000_000.0
    }
}

/// Maps a model id onto the family name Anthropic uses when it scopes a rate-limit
/// window ("Weekly · Fable"). Matching is on the family word so a new version — the exact
/// drift that left Claude 5 unpriced — still lands in the right bucket.
enum ModelFamily {
    static let known = ["fable", "mythos", "opus", "sonnet", "haiku"]

    static func of(_ model: String) -> String {
        let m = model.lowercased()
        return known.first { m.contains($0) } ?? ""
    }

    /// Anthropic's display label ("Fable") back to the stored key.
    static func key(forDisplayName name: String) -> String {
        let n = name.lowercased()
        return known.first { n.contains($0) } ?? ""
    }
}
