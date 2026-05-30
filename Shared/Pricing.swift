import Foundation

struct TokenUsage: Equatable {
    let input: Int
    let output: Int
    let cacheWrite: Int        // cache_creation_input_tokens
    let cacheRead: Int         // cache_read_input_tokens

    /// Tokens that count toward utilization caps. Cache reads are essentially free.
    var utilizationTokens: Int { input + output + cacheWrite }
}

enum Pricing {
    /// $ per million tokens, by token bucket.
    private struct Rate {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double
    }

    // $/Mtok. Opus 4.5+ was repriced to $5/$25 (down from the old $15/$75); cache write =
    // 1.25× input, cache read = 0.1× input. Verified against ccusage/LiteLLM — with these
    // rates our per-model cost matches ccusage exactly for opus, sonnet, and haiku.
    private static let rates: [(prefix: String, rate: Rate)] = [
        ("claude-opus-4",   Rate(input:  5.00, output: 25.00, cacheWrite:  6.25, cacheRead: 0.50)),
        ("claude-sonnet-4", Rate(input:  3.00, output: 15.00, cacheWrite:  3.75, cacheRead: 0.30)),
        ("claude-haiku-4",  Rate(input:  1.00, output:  5.00, cacheWrite:  1.25, cacheRead: 0.10)),
    ]

    static func cost(model: String, usage: TokenUsage) -> Double {
        guard let r = rates.first(where: { model.hasPrefix($0.prefix) })?.rate else { return 0 }
        return (Double(usage.input)      * r.input
              + Double(usage.output)     * r.output
              + Double(usage.cacheWrite) * r.cacheWrite
              + Double(usage.cacheRead)  * r.cacheRead) / 1_000_000.0
    }
}
