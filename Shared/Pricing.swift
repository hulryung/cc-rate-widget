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

    private static let rates: [(prefix: String, rate: Rate)] = [
        ("claude-opus-4",   Rate(input: 15.00, output: 75.00, cacheWrite: 18.75, cacheRead: 1.50)),
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
