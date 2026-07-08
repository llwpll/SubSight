import Foundation

public struct Subscription: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var amount: Double
    public var currencyCode: String
    public var cycle: String
    public var category: String
    public var paymentMethod: String
    public var nextBillingDate: Date
    public var notes: String
    public var isActive: Bool
    public var reminderEnabled: Bool
    public var reminderLeadDays: Int
    public var cancellationURL: String
    public var accountHint: String
    public var paymentHistory: [PaymentRecord]
    public var completedPaymentCount: Int
    public var totalPaymentCount: Int?
    public var paymentEndDate: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case currencyCode
        case cycle
        case category
        case paymentMethod
        case nextBillingDate
        case notes
        case isActive
        case reminderEnabled
        case reminderLeadDays
        case cancellationURL
        case accountHint
        case paymentHistory
        case completedPaymentCount
        case totalPaymentCount
        case paymentEndDate
    }

    public init(
        id: UUID = UUID(),
        name: String = "",
        amount: Double = 0,
        currencyCode: String = "CNY",
        cycle: String = BillingCycle.monthly.rawValue,
        category: String = "Software",
        paymentMethod: String = "Card",
        nextBillingDate: Date = .now,
        notes: String = "",
        isActive: Bool = true,
        reminderEnabled: Bool = true,
        reminderLeadDays: Int = 1,
        cancellationURL: String = "",
        accountHint: String = "",
        paymentHistory: [PaymentRecord] = [],
        completedPaymentCount: Int = 0,
        totalPaymentCount: Int? = nil,
        paymentEndDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode
        self.cycle = cycle
        self.category = category
        self.paymentMethod = paymentMethod
        self.nextBillingDate = nextBillingDate
        self.notes = notes
        self.isActive = isActive
        self.reminderEnabled = reminderEnabled
        self.reminderLeadDays = reminderLeadDays
        self.cancellationURL = cancellationURL
        self.accountHint = accountHint
        self.paymentHistory = paymentHistory
        self.completedPaymentCount = completedPaymentCount
        self.totalPaymentCount = totalPaymentCount
        self.paymentEndDate = paymentEndDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "CNY"
        cycle = try container.decodeIfPresent(String.self, forKey: .cycle) ?? BillingCycle.monthly.rawValue
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Software"
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod) ?? "Card"
        nextBillingDate = try container.decodeIfPresent(Date.self, forKey: .nextBillingDate) ?? .now
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        reminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? true
        reminderLeadDays = try container.decodeIfPresent(Int.self, forKey: .reminderLeadDays) ?? 1
        cancellationURL = try container.decodeIfPresent(String.self, forKey: .cancellationURL) ?? ""
        accountHint = try container.decodeIfPresent(String.self, forKey: .accountHint) ?? ""
        paymentHistory = try container.decodeIfPresent([PaymentRecord].self, forKey: .paymentHistory) ?? []
        completedPaymentCount = try container.decodeIfPresent(Int.self, forKey: .completedPaymentCount) ?? paymentHistory.count
        totalPaymentCount = try container.decodeIfPresent(Int.self, forKey: .totalPaymentCount)
        paymentEndDate = try container.decodeIfPresent(Date.self, forKey: .paymentEndDate)
    }

    public var remainingPaymentCount: Int? {
        guard let totalPaymentCount else {
            return nil
        }
        return max(totalPaymentCount - completedPaymentCount, 0)
    }

    @discardableResult
    public mutating func markCurrentPeriodPaid(calendar: Calendar = .current) -> PaymentRecord {
        let paidDate = nextBillingDate
        let record = PaymentRecord(
            paidDate: paidDate,
            amount: amount,
            currencyCode: currencyCode,
            cycle: cycle
        )
        paymentHistory.append(record)
        completedPaymentCount += 1

        if let totalPaymentCount, completedPaymentCount >= totalPaymentCount {
            completedPaymentCount = totalPaymentCount
            isActive = false
        } else {
            let advancedDate = BillingCycle.from(cycle).advancedDate(from: paidDate, calendar: calendar)
            if let paymentEndDate, calendar.startOfDay(for: advancedDate) > calendar.startOfDay(for: paymentEndDate) {
                isActive = false
            } else {
                nextBillingDate = advancedDate
            }
        }

        return record
    }
}

public struct PaymentRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var paidDate: Date
    public var amount: Double
    public var currencyCode: String
    public var cycle: String

    public init(
        id: UUID = UUID(),
        paidDate: Date,
        amount: Double,
        currencyCode: String,
        cycle: String
    ) {
        self.id = id
        self.paidDate = paidDate
        self.amount = amount
        self.currencyCode = currencyCode
        self.cycle = cycle
    }
}

public enum BillingCycle: String, CaseIterable, Identifiable, Codable, Sendable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case semiannual = "Semiannual"
    case yearly = "Yearly"

    public var id: String { rawValue }

    public var monthlyMultiplier: Double {
        switch self {
        case .weekly: return 52 / 12
        case .monthly: return 1
        case .quarterly: return 1.0 / 3.0
        case .semiannual: return 1.0 / 6.0
        case .yearly: return 1.0 / 12.0
        }
    }

    public var displayName: String {
        switch self {
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .quarterly: return "每季度"
        case .semiannual: return "每半年"
        case .yearly: return "每年"
        }
    }

    public func advancedDate(from date: Date, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component
        let value: Int

        switch self {
        case .weekly:
            component = .day
            value = 7
        case .monthly:
            component = .month
            value = 1
        case .quarterly:
            component = .month
            value = 3
        case .semiannual:
            component = .month
            value = 6
        case .yearly:
            component = .year
            value = 1
        }

        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    public static func from(_ rawValue: String) -> BillingCycle {
        BillingCycle(rawValue: rawValue) ?? .monthly
    }

    public static func parse(_ value: String) throws -> BillingCycle {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "weekly", "week", "w", "每周": return .weekly
        case "monthly", "month", "m", "每月": return .monthly
        case "quarterly", "quarter", "q", "每季度": return .quarterly
        case "semiannual", "semi-annually", "semiannually", "half-year", "halfyear", "half_year", "6m", "半年", "每半年": return .semiannual
        case "yearly", "annual", "year", "y", "每年": return .yearly
        default:
            throw SubSightCoreError.message("Unsupported cycle: \(value). Use weekly, monthly, quarterly, semiannual, or yearly.")
        }
    }
}

public enum SubscriptionStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case active
    case all
    case paused

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: return "有效"
        case .all: return "全部"
        case .paused: return "暂停"
        }
    }
}

public struct SubscriptionTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var currencyCode: String
    public var cycle: BillingCycle
    public var cancellationURL: String

    public init(id: String, name: String, category: String, currencyCode: String, cycle: BillingCycle, cancellationURL: String = "") {
        self.id = id
        self.name = name
        self.category = category
        self.currencyCode = currencyCode
        self.cycle = cycle
        self.cancellationURL = cancellationURL
    }
}

public enum SubscriptionTemplates {
    public static let popular: [SubscriptionTemplate] = [
        SubscriptionTemplate(id: "chatgpt", name: "ChatGPT", category: "AI", currencyCode: "USD", cycle: .monthly, cancellationURL: "https://chatgpt.com/#settings/Subscription"),
        SubscriptionTemplate(id: "claude", name: "Claude", category: "AI", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "gemini-advanced", name: "Gemini Advanced", category: "AI", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "perplexity", name: "Perplexity", category: "AI", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "midjourney", name: "Midjourney", category: "AI", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "cursor", name: "Cursor", category: "AI", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "github-copilot", name: "GitHub Copilot", category: "AI", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "minimax", name: "MiniMax", category: "AI", currencyCode: "CNY", cycle: .monthly),

        SubscriptionTemplate(id: "icloud", name: "iCloud+", category: "Cloud", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "google-one", name: "Google One", category: "Cloud", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "dropbox", name: "Dropbox", category: "Cloud", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "onedrive", name: "OneDrive", category: "Cloud", currencyCode: "USD", cycle: .monthly),

        SubscriptionTemplate(id: "netflix", name: "Netflix", category: "娱乐", currencyCode: "USD", cycle: .monthly, cancellationURL: "https://www.netflix.com/cancelplan"),
        SubscriptionTemplate(id: "disney-plus", name: "Disney+", category: "娱乐", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "max", name: "Max", category: "娱乐", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "youtube-premium", name: "YouTube Premium", category: "娱乐", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "apple-tv", name: "Apple TV+", category: "娱乐", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "bilibili", name: "Bilibili 大会员", category: "娱乐", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "iqiyi", name: "爱奇艺", category: "娱乐", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "tencent-video", name: "腾讯视频", category: "娱乐", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "youku", name: "优酷", category: "娱乐", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "infuse", name: "Infuse", category: "娱乐", currencyCode: "USD", cycle: .yearly),

        SubscriptionTemplate(id: "spotify", name: "Spotify", category: "音乐", currencyCode: "USD", cycle: .monthly, cancellationURL: "https://www.spotify.com/account/subscription/"),
        SubscriptionTemplate(id: "apple-music", name: "Apple Music", category: "音乐", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "qq-music", name: "QQ 音乐", category: "音乐", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "netease-music", name: "网易云音乐", category: "音乐", currencyCode: "CNY", cycle: .monthly),

        SubscriptionTemplate(id: "notion", name: "Notion", category: "工具", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "setapp", name: "Setapp", category: "工具", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "adobe", name: "Adobe Creative Cloud", category: "工具", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "microsoft-365", name: "Microsoft 365", category: "工具", currencyCode: "USD", cycle: .yearly),
        SubscriptionTemplate(id: "onepassword", name: "1Password", category: "工具", currencyCode: "USD", cycle: .yearly),
        SubscriptionTemplate(id: "raycast", name: "Raycast Pro", category: "工具", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "vpn", name: "VPN / 梯子", category: "工具", currencyCode: "CNY", cycle: .yearly),

        SubscriptionTemplate(id: "mobile-phone", name: "手机号", category: "通信", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "broadband", name: "宽带", category: "通信", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "data-card", name: "流量卡", category: "通信", currencyCode: "CNY", cycle: .monthly),

        SubscriptionTemplate(id: "rent", name: "房租", category: "住房", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "mortgage", name: "房贷", category: "住房", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "property-fee", name: "物业费", category: "住房", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "utilities", name: "水电燃气", category: "账单", currencyCode: "CNY", cycle: .monthly),

        SubscriptionTemplate(id: "medical-insurance", name: "医疗险", category: "保险", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "critical-illness-insurance", name: "重疾险", category: "保险", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "accident-insurance", name: "意外险", category: "保险", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "car-insurance", name: "车险", category: "保险", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "applecare", name: "AppleCare+", category: "保险", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "gym", name: "健身房", category: "健康", currencyCode: "CNY", cycle: .monthly),

        SubscriptionTemplate(id: "amazon-prime", name: "Amazon Prime", category: "会员", currencyCode: "USD", cycle: .yearly),
        SubscriptionTemplate(id: "88vip", name: "88VIP", category: "会员", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "costco", name: "Costco 会员", category: "会员", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "sams-club", name: "山姆会员", category: "会员", currencyCode: "CNY", cycle: .yearly),

        SubscriptionTemplate(id: "coursera", name: "Coursera", category: "教育", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "skillshare", name: "Skillshare", category: "教育", currencyCode: "USD", cycle: .yearly),
        SubscriptionTemplate(id: "duolingo", name: "Duolingo", category: "教育", currencyCode: "USD", cycle: .yearly),
        SubscriptionTemplate(id: "dedao", name: "得到", category: "教育", currencyCode: "CNY", cycle: .yearly),
        SubscriptionTemplate(id: "medium", name: "Medium", category: "阅读", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "readwise", name: "Readwise", category: "阅读", currencyCode: "USD", cycle: .monthly),
        SubscriptionTemplate(id: "kindle-unlimited", name: "Kindle Unlimited", category: "阅读", currencyCode: "USD", cycle: .monthly),

        SubscriptionTemplate(id: "parking", name: "停车费", category: "交通", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "etc", name: "ETC", category: "交通", currencyCode: "CNY", cycle: .monthly),
        SubscriptionTemplate(id: "credit-card-annual-fee", name: "信用卡年费", category: "账单", currencyCode: "CNY", cycle: .yearly)
    ]
}

public struct SubscriptionSummary: Codable, Sendable {
    public var baseCurrency: String
    public var activeCount: Int
    public var monthlyTotal: Double
    public var yearlyTotal: Double
    public var items: [SubscriptionSummaryItem]

    public init(baseCurrency: String, activeCount: Int, monthlyTotal: Double, yearlyTotal: Double, items: [SubscriptionSummaryItem]) {
        self.baseCurrency = baseCurrency
        self.activeCount = activeCount
        self.monthlyTotal = monthlyTotal
        self.yearlyTotal = yearlyTotal
        self.items = items
    }
}

public struct SubscriptionSummaryItem: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var nativeCurrency: String
    public var monthlyNative: Double
    public var monthlyBase: Double
}

public enum SubscriptionBreakdownDimension: String, CaseIterable, Codable, Sendable {
    case category
    case paymentMethod

    public var title: String {
        switch self {
        case .category: return "分类"
        case .paymentMethod: return "付款方式"
        }
    }
}

public struct SubscriptionBreakdownItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var activeCount: Int
    public var monthlyBase: Double
    public var yearlyBase: Double
    public var share: Double

    public init(name: String, activeCount: Int, monthlyBase: Double, yearlyBase: Double, share: Double) {
        self.name = name
        self.activeCount = activeCount
        self.monthlyBase = monthlyBase
        self.yearlyBase = yearlyBase
        self.share = share
    }
}

public struct SubscriptionBreakdown: Codable, Sendable {
    public var dimension: SubscriptionBreakdownDimension
    public var baseCurrency: String
    public var monthlyTotal: Double
    public var items: [SubscriptionBreakdownItem]

    public init(dimension: SubscriptionBreakdownDimension, baseCurrency: String, monthlyTotal: Double, items: [SubscriptionBreakdownItem]) {
        self.dimension = dimension
        self.baseCurrency = baseCurrency
        self.monthlyTotal = monthlyTotal
        self.items = items
    }
}

public enum SubscriptionSchedule {
    public static func upcoming(
        _ subscriptions: [Subscription],
        from startDate: Date = .now,
        days: Int = 30,
        status: SubscriptionStatusFilter = .active,
        calendar: Calendar = .current
    ) -> [Subscription] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: max(days, 0) + 1, to: start) ?? start

        return SubscriptionFilter.apply(subscriptions, status: status)
            .filter { $0.nextBillingDate >= start && $0.nextBillingDate < end }
            .sorted { $0.nextBillingDate < $1.nextBillingDate }
    }
}

public enum SubSightCoreError: Error, CustomStringConvertible {
    case message(String)

    public var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}
