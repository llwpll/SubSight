import Foundation

public struct ExchangeRate: Decodable, Sendable {
    public let date: String
    public let base: String
    public let quote: String
    public let rate: Double
}

public struct ExchangeRateClient: Sendable {
    public let endpoint: URL

    public init(endpoint: URL = URL(string: "https://api.frankfurter.dev/v2/rates")!) {
        self.endpoint = endpoint
    }

    public func rates(base: String, quotes: [String]) async throws -> [String: Double] {
        let normalizedBase = base.uppercased()
        let normalizedQuotes = Array(Set(quotes.map { $0.uppercased() })).sorted()
        let remoteQuotes = normalizedQuotes.filter { $0 != normalizedBase }
        var result = Dictionary(uniqueKeysWithValues: normalizedQuotes.filter { $0 == normalizedBase }.map { ($0, 1.0) })
        guard !remoteQuotes.isEmpty else {
            return result
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "base", value: normalizedBase),
            URLQueryItem(name: "quotes", value: remoteQuotes.joined(separator: ","))
        ]

        let url = components.url!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SubSightCoreError.message("Exchange-rate request failed: \(url.absoluteString)")
        }
        let decoded = try JSONDecoder().decode([ExchangeRate].self, from: data)
        for item in decoded {
            result[item.quote.uppercased()] = item.rate
        }
        return result
    }
}

public enum SubscriptionCalculator {
    public static func convert(_ amount: Double, from currencyCode: String, to baseCurrency: String, rates: [String: Double]) -> Double {
        let currency = currencyCode.uppercased()
        let base = baseCurrency.uppercased()
        guard currency != base else {
            return amount
        }
        guard let rate = rates[currency], rate > 0 else {
            return amount
        }
        return amount / rate
    }

    public static func summary(subscriptions: [Subscription], baseCurrency: String, rates: [String: Double]) -> SubscriptionSummary {
        let active = subscriptions.filter(\.isActive)
        var monthlyTotal = 0.0
        var yearlyTotal = 0.0
        var items: [SubscriptionSummaryItem] = []

        for subscription in active {
            let cycle = BillingCycle.from(subscription.cycle)
            let monthlyNative = subscription.amount * cycle.monthlyMultiplier
            let monthlyBase = convert(monthlyNative, from: subscription.currencyCode, to: baseCurrency, rates: rates)
            monthlyTotal += monthlyBase
            yearlyTotal += monthlyBase * 12
            items.append(
                SubscriptionSummaryItem(
                    id: subscription.id,
                    name: subscription.name,
                    nativeCurrency: subscription.currencyCode,
                    monthlyNative: monthlyNative,
                    monthlyBase: monthlyBase
                )
            )
        }

        return SubscriptionSummary(
            baseCurrency: baseCurrency.uppercased(),
            activeCount: active.count,
            monthlyTotal: monthlyTotal,
            yearlyTotal: yearlyTotal,
            items: items
        )
    }

    public static func breakdown(
        subscriptions: [Subscription],
        baseCurrency: String,
        rates: [String: Double],
        dimension: SubscriptionBreakdownDimension
    ) -> SubscriptionBreakdown {
        let active = subscriptions.filter(\.isActive)
        var totals: [String: (count: Int, monthly: Double)] = [:]

        for subscription in active {
            let key: String
            switch dimension {
            case .category:
                key = subscription.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Uncategorized" : subscription.category
            case .paymentMethod:
                key = subscription.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : subscription.paymentMethod
            }

            let monthlyNative = subscription.amount * BillingCycle.from(subscription.cycle).monthlyMultiplier
            let monthlyBase = convert(monthlyNative, from: subscription.currencyCode, to: baseCurrency, rates: rates)
            var bucket = totals[key, default: (count: 0, monthly: 0)]
            bucket.count += 1
            bucket.monthly += monthlyBase
            totals[key] = bucket
        }

        let monthlyTotal = totals.values.reduce(0) { $0 + $1.monthly }
        let items = totals.map { name, value in
            SubscriptionBreakdownItem(
                name: name,
                activeCount: value.count,
                monthlyBase: value.monthly,
                yearlyBase: value.monthly * 12,
                share: monthlyTotal > 0 ? value.monthly / monthlyTotal : 0
            )
        }
        .sorted {
            if $0.monthlyBase == $1.monthlyBase {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.monthlyBase > $1.monthlyBase
        }

        return SubscriptionBreakdown(
            dimension: dimension,
            baseCurrency: baseCurrency.uppercased(),
            monthlyTotal: monthlyTotal,
            items: items
        )
    }
}
