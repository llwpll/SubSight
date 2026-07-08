import Foundation

public struct SubscriptionRepository: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func live() throws -> SubscriptionRepository {
        if let override = ProcessInfo.processInfo.environment["SUBSIGHT_DATA_FILE"], !override.isEmpty {
            let url = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return SubscriptionRepository(fileURL: url)
        }

        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folderURL = baseURL.appending(path: "SubSight", directoryHint: .isDirectory)
        let legacyFolderURL = baseURL.appending(path: "SubscriptionLedger", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let fileURL = folderURL.appending(path: "subscriptions.json")
        let legacyFileURL = legacyFolderURL.appending(path: "subscriptions.json")
        if !FileManager.default.fileExists(atPath: fileURL.path),
           FileManager.default.fileExists(atPath: legacyFileURL.path) {
            try? FileManager.default.copyItem(at: legacyFileURL, to: fileURL)
        }

        return SubscriptionRepository(fileURL: fileURL)
    }

    public func load() throws -> [Subscription] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty ||
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Subscription].self, from: data)
    }

    public func save(_ subscriptions: [Subscription]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(subscriptions.sorted { $0.nextBillingDate < $1.nextBillingDate })
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func add(_ subscription: Subscription) throws -> UUID {
        var subscriptions = try load()
        subscriptions.append(subscription)
        try save(subscriptions)
        return subscription.id
    }

    public func get(id: UUID) throws -> Subscription? {
        try load().first { $0.id == id }
    }

    public func update(_ subscription: Subscription) throws -> Subscription? {
        var subscriptions = try load()
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else {
            return nil
        }
        subscriptions[index] = subscription
        try save(subscriptions)
        return subscription
    }

    public func delete(id: UUID) throws -> Bool {
        var subscriptions = try load()
        let before = subscriptions.count
        subscriptions.removeAll { $0.id == id }
        try save(subscriptions)
        return subscriptions.count < before
    }
}

public enum SubscriptionFilter {
    public static func apply(_ subscriptions: [Subscription], query: String = "", status: SubscriptionStatusFilter = .all) -> [Subscription] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return subscriptions.filter { subscription in
            let matchesStatus: Bool
            switch status {
            case .all: matchesStatus = true
            case .active: matchesStatus = subscription.isActive
            case .paused: matchesStatus = !subscription.isActive
            }

            let matchesQuery = normalizedQuery.isEmpty
                || subscription.name.lowercased().contains(normalizedQuery)
                || subscription.category.lowercased().contains(normalizedQuery)
                || subscription.paymentMethod.lowercased().contains(normalizedQuery)
                || subscription.accountHint.lowercased().contains(normalizedQuery)
                || subscription.cancellationURL.lowercased().contains(normalizedQuery)
                || subscription.notes.lowercased().contains(normalizedQuery)

            return matchesStatus && matchesQuery
        }
    }
}
