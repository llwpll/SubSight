import Foundation
import SubSightCore

enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}

struct Arguments {
    private(set) var command: String
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ raw: [String]) throws {
        guard let first = raw.first else {
            throw CLIError.message(Self.help)
        }
        command = first
        var index = 1
        while index < raw.count {
            let token = raw[index]
            guard token.hasPrefix("--") else {
                throw CLIError.message("Unexpected argument: \(token)")
            }
            let key = String(token.dropFirst(2))
            if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                values[key] = raw[index + 1]
                index += 2
            } else {
                flags.insert(key)
                index += 1
            }
        }
    }

    func value(_ key: String) -> String? {
        values[key]
    }

    func require(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else {
            throw CLIError.message("Missing required --\(key)")
        }
        return value
    }

    func has(_ key: String) -> Bool {
        flags.contains(key) || values[key] == "true"
    }

    static let help = """
    SubSight agent CLI

    Commands:
      subsightctl list [--json] [--query TEXT] [--status active|all|paused]
      subsightctl get --id UUID [--json]
      subsightctl due [--days 30] [--from YYYY-MM-DD] [--status active|all|paused] [--json]
      subsightctl add --name NAME --amount AMOUNT [--currency CNY] [--cycle monthly] [--next YYYY-MM-DD] [--category Software] [--payment Card] [--notes TEXT] [--cancel-url URL] [--account TEXT] [--total-payments N] [--completed-payments N] [--end-date YYYY-MM-DD] [--inactive] [--no-reminder] [--reminder-days N]
      subsightctl update --id UUID [--name NAME] [--amount AMOUNT] [--currency CNY] [--cycle monthly] [--next YYYY-MM-DD] [--category Software] [--payment Card] [--notes TEXT] [--cancel-url URL] [--account TEXT] [--total-payments N] [--completed-payments N] [--end-date YYYY-MM-DD|none] [--active|--inactive] [--reminder|--no-reminder] [--reminder-days N]
      subsightctl pause --id UUID
      subsightctl resume --id UUID
      subsightctl delete --id UUID
      subsightctl summary [--base CNY] [--json]
      subsightctl breakdown [--dimension category|payment] [--base CNY] [--json]
      subsightctl export-csv --output PATH
      subsightctl import-csv --input PATH [--replace]
      subsightctl export-json --output PATH
      subsightctl import-json --input PATH [--replace]
      subsightctl rates --base USD --quotes CNY,EUR,HKD
      subsightctl templates [--json]
    """
}

@main
struct SubSightCLI {
    static func main() async {
        do {
            let args = try Arguments(Array(CommandLine.arguments.dropFirst()))
            let repository = try SubscriptionRepository.live()
            switch args.command {
            case "list":
                try list(args: args, repository: repository)
            case "get":
                try get(args: args, repository: repository)
            case "due":
                try due(args: args, repository: repository)
            case "add":
                try add(args: args, repository: repository)
            case "update":
                try update(args: args, repository: repository)
            case "pause":
                try setActive(args: args, repository: repository, isActive: false)
            case "resume":
                try setActive(args: args, repository: repository, isActive: true)
            case "delete":
                try delete(args: args, repository: repository)
            case "summary":
                try await summary(args: args, repository: repository)
            case "breakdown":
                try await breakdown(args: args, repository: repository)
            case "export-csv":
                try exportCSV(args: args, repository: repository)
            case "import-csv":
                try importCSV(args: args, repository: repository)
            case "export-json":
                try exportJSON(args: args, repository: repository)
            case "import-json":
                try importJSON(args: args, repository: repository)
            case "rates":
                try await rates(args: args)
            case "templates":
                templates(args: args)
            case "help", "--help", "-h":
                print(Arguments.help)
            default:
                throw CLIError.message("Unknown command: \(args.command)\n\n\(Arguments.help)")
            }
        } catch {
            fputs("subsightctl: \(error)\n", stderr)
            exit(1)
        }
    }

    static func list(args: Arguments, repository: SubscriptionRepository) throws {
        let status = try parseStatus(args.value("status") ?? "active")
        let subscriptions = SubscriptionFilter.apply(
            try repository.load(),
            query: args.value("query") ?? "",
            status: status
        )
        if args.has("json") {
            printJSON(subscriptions)
            return
        }
        if subscriptions.isEmpty {
            print("No subscriptions.")
            return
        }
        for item in subscriptions {
            let status = item.isActive ? "active" : "paused"
            let date = DateFormats.day.string(from: item.nextBillingDate)
            print("\(item.id.uuidString)  \(item.name)  \(item.amount) \(item.currencyCode)  \(BillingCycle.from(item.cycle).rawValue)  next:\(date)  \(status)")
        }
    }

    static func due(args: Arguments, repository: SubscriptionRepository) throws {
        let days = Int(args.value("days") ?? "30") ?? -1
        guard days >= 0 else {
            throw CLIError.message("--days must be an integer >= 0")
        }
        let from = try DateFormats.parseDay(args.value("from")) ?? .now
        let status = try parseStatus(args.value("status") ?? "active")
        let subscriptions = SubscriptionSchedule.upcoming(
            try repository.load(),
            from: from,
            days: days,
            status: status
        )
        if args.has("json") {
            printJSON(subscriptions)
            return
        }
        if subscriptions.isEmpty {
            print("No upcoming renewals.")
            return
        }
        for item in subscriptions {
            print(describe(item))
        }
    }

    static func get(args: Arguments, repository: SubscriptionRepository) throws {
        let id = try parseID(args)
        guard let subscription = try repository.get(id: id) else {
            throw CLIError.message("No subscription found for id \(id.uuidString)")
        }
        if args.has("json") {
            printJSON(subscription)
        } else {
            print(describe(subscription))
        }
    }

    static func add(args: Arguments, repository: SubscriptionRepository) throws {
        let amount = Double(try args.require("amount")) ?? -1
        guard amount >= 0 else {
            throw CLIError.message("--amount must be a number >= 0")
        }
        let cycle = try BillingCycle.parse(args.value("cycle") ?? "monthly")
        let nextDate = try DateFormats.parseDay(args.value("next")) ?? .now
        let totalPaymentCount = try parseOptionalCount(args.value("total-payments"), argument: "total-payments")
        let completedPaymentCount = try parseOptionalCount(args.value("completed-payments"), argument: "completed-payments") ?? 0
        let paymentEndDate = try parseOptionalDate(args.value("end-date"), argument: "end-date")
        let subscription = Subscription(
            name: try args.require("name"),
            amount: amount,
            currencyCode: (args.value("currency") ?? "CNY").uppercased(),
            cycle: cycle.rawValue,
            category: args.value("category") ?? "Software",
            paymentMethod: args.value("payment") ?? "Card",
            nextBillingDate: nextDate,
            notes: args.value("notes") ?? "",
            isActive: !args.has("inactive"),
            reminderEnabled: !args.has("no-reminder"),
            reminderLeadDays: Int(args.value("reminder-days") ?? "1") ?? 1,
            cancellationURL: args.value("cancel-url") ?? "",
            accountHint: args.value("account") ?? "",
            completedPaymentCount: min(completedPaymentCount, totalPaymentCount ?? completedPaymentCount),
            totalPaymentCount: totalPaymentCount,
            paymentEndDate: paymentEndDate
        )
        _ = try repository.add(subscription)
        printJSON(subscription)
    }

    static func update(args: Arguments, repository: SubscriptionRepository) throws {
        let id = try parseID(args)
        guard var subscription = try repository.get(id: id) else {
            throw CLIError.message("No subscription found for id \(id.uuidString)")
        }

        try applyUpdate(args: args, to: &subscription)
        guard let updated = try repository.update(subscription) else {
            throw CLIError.message("No subscription found for id \(id.uuidString)")
        }
        printJSON(updated)
    }

    static func setActive(args: Arguments, repository: SubscriptionRepository, isActive: Bool) throws {
        let id = try parseID(args)
        guard var subscription = try repository.get(id: id) else {
            throw CLIError.message("No subscription found for id \(id.uuidString)")
        }
        subscription.isActive = isActive
        guard let updated = try repository.update(subscription) else {
            throw CLIError.message("No subscription found for id \(id.uuidString)")
        }
        printJSON(updated)
    }

    static func delete(args: Arguments, repository: SubscriptionRepository) throws {
        let id = try parseID(args)
        guard try repository.delete(id: id) else {
            throw CLIError.message("No subscription found for id \(id.uuidString)")
        }
        print("{\"deleted\":\"\(id.uuidString)\"}")
    }

    static func summary(args: Arguments, repository: SubscriptionRepository) async throws {
        let subscriptions = try repository.load()
        let base = (args.value("base") ?? "CNY").uppercased()
        let currencies = Array(Set(subscriptions.filter(\.isActive).map { $0.currencyCode.uppercased() } + [base]))
        let rates = try await ExchangeRateClient().rates(base: base, quotes: currencies)
        let result = SubscriptionCalculator.summary(subscriptions: subscriptions, baseCurrency: base, rates: rates)

        if args.has("json") {
            printJSON(result)
        } else {
            print("Active subscriptions: \(result.activeCount)")
            print("Monthly total (\(base)): \(format(result.monthlyTotal))")
            print("Yearly total  (\(base)): \(format(result.yearlyTotal))")
        }
    }

    static func breakdown(args: Arguments, repository: SubscriptionRepository) async throws {
        let subscriptions = try repository.load()
        let base = (args.value("base") ?? "CNY").uppercased()
        let dimension = try parseBreakdownDimension(args.value("dimension") ?? "category")
        let currencies = Array(Set(subscriptions.filter(\.isActive).map { $0.currencyCode.uppercased() } + [base]))
        let rates = try await ExchangeRateClient().rates(base: base, quotes: currencies)
        let result = SubscriptionCalculator.breakdown(
            subscriptions: subscriptions,
            baseCurrency: base,
            rates: rates,
            dimension: dimension
        )

        if args.has("json") {
            printJSON(result)
        } else if result.items.isEmpty {
            print("No active subscriptions.")
        } else {
            print("\(dimension.title) breakdown (\(base))")
            for item in result.items {
                print("\(item.name)  \(format(item.monthlyBase))/mo  \(format(item.yearlyBase))/yr  \(Int((item.share * 100).rounded()))%  \(item.activeCount) active")
            }
        }
    }

    static func exportCSV(args: Arguments, repository: SubscriptionRepository) throws {
        let output = try args.require("output")
        let subscriptions = try repository.load()
        try SubscriptionCSV.export(subscriptions).write(toFile: NSString(string: output).expandingTildeInPath, atomically: true, encoding: .utf8)
        print("{\"exported\":\"\(output)\",\"rows\":\(subscriptions.count)}")
    }

    static func importCSV(args: Arguments, repository: SubscriptionRepository) throws {
        let input = NSString(string: try args.require("input")).expandingTildeInPath
        let csv = try String(contentsOfFile: input, encoding: .utf8)
        let imported = try SubscriptionCSV.import(csv)
        let subscriptions = args.has("replace") ? imported : try repository.load() + imported
        try repository.save(subscriptions)
        print("{\"imported\":\"\(input)\",\"rows\":\(imported.count),\"mode\":\"\(args.has("replace") ? "replace" : "append")\"}")
    }

    static func exportJSON(args: Arguments, repository: SubscriptionRepository) throws {
        let output = try args.require("output")
        let subscriptions = try repository.load()
        let data = try SubscriptionJSON.export(subscriptions)
        try data.write(to: URL(fileURLWithPath: NSString(string: output).expandingTildeInPath), options: .atomic)
        print("{\"exported\":\"\(output)\",\"rows\":\(subscriptions.count)}")
    }

    static func importJSON(args: Arguments, repository: SubscriptionRepository) throws {
        let input = NSString(string: try args.require("input")).expandingTildeInPath
        let imported = try SubscriptionJSON.import(Data(contentsOf: URL(fileURLWithPath: input)))
        let subscriptions = args.has("replace") ? imported : try repository.load() + imported
        try repository.save(subscriptions)
        print("{\"imported\":\"\(input)\",\"rows\":\(imported.count),\"mode\":\"\(args.has("replace") ? "replace" : "append")\"}")
    }

    static func rates(args: Arguments) async throws {
        let base = (args.value("base") ?? "USD").uppercased()
        let quotes = (try args.require("quotes")).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        let rates = try await ExchangeRateClient().rates(base: base, quotes: quotes)
        printJSONObject(["base": base, "rates": rates])
    }

    static func templates(args: Arguments) {
        if args.has("json") {
            printJSON(SubscriptionTemplates.popular)
        } else {
            for template in SubscriptionTemplates.popular {
                print("\(template.id)  \(template.name)  \(template.category)  \(template.currencyCode)  \(template.cycle.rawValue)")
            }
        }
    }

    static func parseStatus(_ value: String) throws -> SubscriptionStatusFilter {
        guard let status = SubscriptionStatusFilter(rawValue: value.lowercased()) else {
            throw CLIError.message("Unsupported status: \(value). Use active, all, or paused.")
        }
        return status
    }

    static func parseBreakdownDimension(_ value: String) throws -> SubscriptionBreakdownDimension {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "category", "cat", "分类":
            return .category
        case "payment", "payment-method", "payment_method", "method", "付款", "付款方式":
            return .paymentMethod
        default:
            throw CLIError.message("Unsupported breakdown dimension: \(value). Use category or payment.")
        }
    }

    static func parseID(_ args: Arguments) throws -> UUID {
        let rawID = try args.require("id")
        guard let id = UUID(uuidString: rawID) else {
            throw CLIError.message("Invalid UUID: \(rawID)")
        }
        return id
    }

    static func applyUpdate(args: Arguments, to subscription: inout Subscription) throws {
        if let name = args.value("name") {
            subscription.name = name
        }
        if let amountValue = args.value("amount") {
            let amount = Double(amountValue) ?? -1
            guard amount >= 0 else {
                throw CLIError.message("--amount must be a number >= 0")
            }
            subscription.amount = amount
        }
        if let currency = args.value("currency") {
            subscription.currencyCode = currency.uppercased()
        }
        if let cycle = args.value("cycle") {
            subscription.cycle = try BillingCycle.parse(cycle).rawValue
        }
        if let next = args.value("next") {
            subscription.nextBillingDate = try DateFormats.parseDay(next) ?? subscription.nextBillingDate
        }
        if let category = args.value("category") {
            subscription.category = category
        }
        if let payment = args.value("payment") {
            subscription.paymentMethod = payment
        }
        if let notes = args.value("notes") {
            subscription.notes = notes
        }
        if let cancellationURL = args.value("cancel-url") {
            subscription.cancellationURL = cancellationURL
        }
        if let accountHint = args.value("account") {
            subscription.accountHint = accountHint
        }
        if let totalPaymentCount = try parseOptionalCount(args.value("total-payments"), argument: "total-payments") {
            subscription.totalPaymentCount = totalPaymentCount == 0 ? nil : totalPaymentCount
            if let total = subscription.totalPaymentCount {
                subscription.completedPaymentCount = min(subscription.completedPaymentCount, total)
            }
        }
        if let completedPaymentCount = try parseOptionalCount(args.value("completed-payments"), argument: "completed-payments") {
            subscription.completedPaymentCount = min(completedPaymentCount, subscription.totalPaymentCount ?? completedPaymentCount)
        }
        if let endDateValue = args.value("end-date") {
            subscription.paymentEndDate = try parseOptionalDate(endDateValue, argument: "end-date")
        }
        if args.has("active") {
            subscription.isActive = true
        }
        if args.has("inactive") {
            subscription.isActive = false
        }
        if args.has("reminder") {
            subscription.reminderEnabled = true
        }
        if args.has("no-reminder") {
            subscription.reminderEnabled = false
        }
        if let days = args.value("reminder-days") {
            guard let reminderLeadDays = Int(days), reminderLeadDays >= 0 else {
                throw CLIError.message("--reminder-days must be an integer >= 0")
            }
            subscription.reminderLeadDays = reminderLeadDays
        }
    }

    static func parseOptionalCount(_ value: String?, argument: String) throws -> Int? {
        guard let value else {
            return nil
        }
        guard let count = Int(value), count >= 0 else {
            throw CLIError.message("--\(argument) must be an integer >= 0")
        }
        return count
    }

    static func parseOptionalDate(_ value: String?, argument: String) throws -> Date? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "none", normalized != "null", normalized != "nil" else {
            return nil
        }
        guard let date = DateFormats.day.date(from: value) else {
            throw CLIError.message("--\(argument) must be YYYY-MM-DD or none")
        }
        return date
    }

    static func describe(_ item: Subscription) -> String {
        let status = item.isActive ? "active" : "paused"
        let date = DateFormats.day.string(from: item.nextBillingDate)
        return "\(item.id.uuidString)  \(item.name)  \(item.amount) \(item.currencyCode)  \(BillingCycle.from(item.cycle).rawValue)  next:\(date)  \(status)"
    }

    static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(value)
        print(String(data: data, encoding: .utf8)!)
    }

    static func printJSONObject(_ object: Any) {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }

    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
