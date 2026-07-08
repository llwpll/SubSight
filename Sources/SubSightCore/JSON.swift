import Foundation

public enum SubscriptionJSON {
    public static func export(_ subscriptions: [Subscription]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(subscriptions.sorted { $0.nextBillingDate < $1.nextBillingDate })
    }

    public static func `import`(_ data: Data) throws -> [Subscription] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Subscription].self, from: data)
    }
}
