import Foundation

public enum SubscriptionCSV {
    public static func export(_ subscriptions: [Subscription]) -> String {
        var rows = ["id,name,amount,currency,cycle,category,payment_method,next_billing_date,is_active,reminder_enabled,reminder_lead_days,cancellation_url,account_hint,notes"]
        for item in subscriptions {
            rows.append([
                item.id.uuidString,
                item.name,
                String(item.amount),
                item.currencyCode,
                item.cycle,
                item.category,
                item.paymentMethod,
                DateFormats.day.string(from: item.nextBillingDate),
                String(item.isActive),
                String(item.reminderEnabled),
                String(item.reminderLeadDays),
                item.cancellationURL,
                item.accountHint,
                item.notes
            ].map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    public static func `import`(_ csv: String) throws -> [Subscription] {
        let rows = parseRows(csv)
        guard let header = rows.first, !header.isEmpty else {
            return []
        }
        let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })

        return try rows.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { row in
            func value(_ key: String) -> String {
                guard let index = indexes[key], index < row.count else {
                    return ""
                }
                return row[index]
            }

            let id = UUID(uuidString: value("id")) ?? UUID()
            let amount = Double(value("amount")) ?? 0
            let nextDate = try DateFormats.parseDay(value("next_billing_date")) ?? .now
            return Subscription(
                id: id,
                name: value("name"),
                amount: amount,
                currencyCode: value("currency").isEmpty ? "CNY" : value("currency").uppercased(),
                cycle: value("cycle").isEmpty ? BillingCycle.monthly.rawValue : value("cycle"),
                category: value("category").isEmpty ? "Software" : value("category"),
                paymentMethod: value("payment_method").isEmpty ? "Card" : value("payment_method"),
                nextBillingDate: nextDate,
                notes: value("notes"),
                isActive: parseBool(value("is_active"), defaultValue: true),
                reminderEnabled: parseBool(value("reminder_enabled"), defaultValue: true),
                reminderLeadDays: Int(value("reminder_lead_days")) ?? 1,
                cancellationURL: value("cancellation_url"),
                accountHint: value("account_hint")
            )
        }
    }

    private static func parseBool(_ value: String, defaultValue: Bool) -> Bool {
        if value.isEmpty {
            return defaultValue
        }
        return ["true", "1", "yes", "y"].contains(value.lowercased())
    }

    private static func parseRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = csv.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if character == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\n" && !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

public enum DateFormats {
    public static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func parseDay(_ value: String?) throws -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        if let date = day.date(from: value) {
            return date
        }
        throw SubSightCoreError.message("Invalid date \(value). Use YYYY-MM-DD.")
    }
}
