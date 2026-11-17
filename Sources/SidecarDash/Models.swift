import Foundation

// Shapes of `codexbar usage --json` output. Every field is optional because
// each provider fills a different subset.

struct RateWindow: Decodable, Sendable {
    var usedPercent: Double?
    var resetsAt: Date?
    var resetDescription: String?
    var windowMinutes: Int?
}

struct ExtraWindow: Decodable, Sendable {
    var id: String?
    var title: String?
    var window: RateWindow?
}

struct ProviderCost: Decodable, Sendable {
    var used: Double?
    var limit: Double?
    var period: String?
    var currencyCode: String?
}

struct UsageBlock: Decodable, Sendable {
    var primary: RateWindow?
    var secondary: RateWindow?
    var tertiary: RateWindow?
    var extraRateWindows: [ExtraWindow]?
    var updatedAt: Date?
    var loginMethod: String?
    var providerCost: ProviderCost?
}

struct Pace: Decodable, Sendable {
    var summary: String?
    var stage: String?
    var willLastToReset: Bool?
    var deltaPercent: Double?
    var expectedUsedPercent: Double?
}

struct ProviderError: Decodable, Sendable {
    var message: String?
}

struct ProviderResult: Decodable, Sendable {
    var provider: String
    var usage: UsageBlock?
    var error: ProviderError?
    var pace: [String: Pace]?
    var rateWindowLabels: [String: String]?
}

struct ProviderState {
    var result: ProviderResult?
    var error: String?
    var lastSuccess: Date?
    var loading = false

    var usage: UsageBlock? { result?.usage }
    var isStale: Bool {
        guard let lastSuccess else { return true }
        return Date().timeIntervalSince(lastSuccess) > 15 * 60
    }
}

struct BalanceSample: Codable, Sendable {
    var date: Date
    var balance: Double
}

/// DeepSeek reports its balance as text, e.g. "$51.60 (Paid: $51.60 / Granted: $0.00)".
struct DeepSeekBalance {
    var total: Double
    var paid: Double?
    var granted: Double?

    init?(_ text: String?) {
        guard let text else { return nil }
        guard let pattern = try? NSRegularExpression(pattern: #"-?[0-9][0-9,]*\.?[0-9]*"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let numbers = pattern.matches(in: text, range: range).compactMap { match -> Double? in
            guard let r = Range(match.range, in: text) else { return nil }
            return Double(text[r].replacingOccurrences(of: ",", with: ""))
        }
        guard let first = numbers.first else { return nil }
        total = first
        paid = numbers.count > 1 ? numbers[1] : nil
        granted = numbers.count > 2 ? numbers[2] : nil
    }
}
