import Foundation
@testable import SubSightCore
import XCTest

final class SubSightCoreTests: XCTestCase {
    func testCSVImportExportRoundTripEscapesFields() throws {
        let subscription = Subscription(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Design, Pro",
            amount: 12.5,
            currencyCode: "USD",
            cycle: BillingCycle.monthly.rawValue,
            category: "Software",
            paymentMethod: "Card",
            nextBillingDate: DateFormats.day.date(from: "2026-08-12")!,
            notes: "line \"one\"\nline two",
            cancellationURL: "https://example.com/cancel",
            accountHint: "team@example.com"
        )

        let csv = SubscriptionCSV.export([subscription])
        let imported = try SubscriptionCSV.import(csv)

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].id, subscription.id)
        XCTAssertEqual(imported[0].name, subscription.name)
        XCTAssertEqual(imported[0].notes, subscription.notes)
        XCTAssertEqual(imported[0].cancellationURL, subscription.cancellationURL)
        XCTAssertEqual(imported[0].accountHint, subscription.accountHint)
        XCTAssertEqual(DateFormats.day.string(from: imported[0].nextBillingDate), "2026-08-12")
    }

    func testSummaryConvertsUsingBaseCurrencyRates() {
        let subscriptions = [
            Subscription(name: "USD Tool", amount: 20, currencyCode: "USD"),
            Subscription(name: "CNY Tool", amount: 30, currencyCode: "CNY")
        ]

        let summary = SubscriptionCalculator.summary(
            subscriptions: subscriptions,
            baseCurrency: "CNY",
            rates: ["CNY": 1, "USD": 0.14]
        )

        XCTAssertEqual(summary.activeCount, 2)
        XCTAssertEqual(summary.monthlyTotal, 172.8571, accuracy: 0.001)
        XCTAssertEqual(summary.yearlyTotal, 2074.2857, accuracy: 0.001)
    }

    func testSemiannualCycleConvertsToMonthlyCost() throws {
        let cycle = try BillingCycle.parse("每半年")
        XCTAssertEqual(cycle, .semiannual)
        XCTAssertEqual(cycle.displayName, "每半年")
        XCTAssertEqual(cycle.monthlyMultiplier, 1.0 / 6.0, accuracy: 0.0001)

        let summary = SubscriptionCalculator.summary(
            subscriptions: [
                Subscription(name: "Netflix", amount: 110, currencyCode: "CNY", cycle: cycle.rawValue)
            ],
            baseCurrency: "CNY",
            rates: ["CNY": 1]
        )

        XCTAssertEqual(summary.monthlyTotal, 18.3333, accuracy: 0.001)
        XCTAssertEqual(summary.yearlyTotal, 220, accuracy: 0.001)
    }

    func testMarkCurrentPeriodPaidAdvancesDateAndCompletesTerm() {
        var subscription = Subscription(
            name: "Term Plan",
            amount: 500,
            cycle: BillingCycle.yearly.rawValue,
            nextBillingDate: DateFormats.day.date(from: "2026-07-07")!,
            totalPaymentCount: 2
        )

        subscription.markCurrentPeriodPaid(calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(subscription.completedPaymentCount, 1)
        XCTAssertEqual(subscription.paymentHistory.count, 1)
        XCTAssertEqual(DateFormats.day.string(from: subscription.paymentHistory[0].paidDate), "2026-07-07")
        XCTAssertEqual(DateFormats.day.string(from: subscription.nextBillingDate), "2027-07-07")
        XCTAssertTrue(subscription.isActive)

        subscription.markCurrentPeriodPaid(calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(subscription.completedPaymentCount, 2)
        XCTAssertEqual(subscription.paymentHistory.count, 2)
        XCTAssertEqual(DateFormats.day.string(from: subscription.nextBillingDate), "2027-07-07")
        XCTAssertFalse(subscription.isActive)
    }

    func testMarkCurrentPeriodPaidPausesAfterEndDate() {
        var subscription = Subscription(
            name: "End Date Plan",
            amount: 100,
            cycle: BillingCycle.monthly.rawValue,
            nextBillingDate: DateFormats.day.date(from: "2026-07-15")!,
            paymentEndDate: DateFormats.day.date(from: "2026-07-31")!
        )

        subscription.markCurrentPeriodPaid(calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(subscription.completedPaymentCount, 1)
        XCTAssertEqual(DateFormats.day.string(from: subscription.nextBillingDate), "2026-07-15")
        XCTAssertFalse(subscription.isActive)
    }

    func testBreakdownGroupsByCategoryAndPaymentMethod() {
        let subscriptions = [
            Subscription(name: "AI A", amount: 20, currencyCode: "USD", category: "AI", paymentMethod: "Card"),
            Subscription(name: "AI B", amount: 10, currencyCode: "CNY", category: "AI", paymentMethod: "Alipay"),
            Subscription(name: "Cloud", amount: 30, currencyCode: "CNY", category: "Cloud", paymentMethod: "Card"),
            Subscription(name: "Paused", amount: 99, currencyCode: "CNY", category: "Cloud", paymentMethod: "Card", isActive: false)
        ]

        let byCategory = SubscriptionCalculator.breakdown(
            subscriptions: subscriptions,
            baseCurrency: "CNY",
            rates: ["CNY": 1, "USD": 0.2],
            dimension: .category
        )
        let byPayment = SubscriptionCalculator.breakdown(
            subscriptions: subscriptions,
            baseCurrency: "CNY",
            rates: ["CNY": 1, "USD": 0.2],
            dimension: .paymentMethod
        )

        XCTAssertEqual(byCategory.items.map(\.name), ["AI", "Cloud"])
        XCTAssertEqual(byCategory.items[0].activeCount, 2)
        XCTAssertEqual(byCategory.items[0].monthlyBase, 110, accuracy: 0.001)
        XCTAssertEqual(byPayment.items.map(\.name), ["Card", "Alipay"])
        XCTAssertEqual(byPayment.items[0].monthlyBase, 130, accuracy: 0.001)
    }

    func testJSONImportExportRoundTrip() throws {
        let subscriptions = [
            Subscription(
                id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                name: "JSON Tool",
                amount: 88,
                currencyCode: "HKD",
                nextBillingDate: DateFormats.day.date(from: "2026-10-01")!,
                cancellationURL: "https://example.com",
                accountHint: "json@example.com"
            )
        ]

        let data = try SubscriptionJSON.export(subscriptions)
        let imported = try SubscriptionJSON.import(data)

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].id, subscriptions[0].id)
        XCTAssertEqual(imported[0].name, "JSON Tool")
        XCTAssertEqual(imported[0].accountHint, "json@example.com")
    }

    func testRepositoryGetUpdateDeleteAndSort() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repository = SubscriptionRepository(fileURL: folder.appending(path: "subscriptions.json"))
        let later = Subscription(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Later",
            nextBillingDate: DateFormats.day.date(from: "2026-09-01")!
        )
        var sooner = Subscription(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            name: "Sooner",
            nextBillingDate: DateFormats.day.date(from: "2026-08-01")!
        )

        try repository.save([later, sooner])
        XCTAssertEqual(try repository.load().map(\.name), ["Sooner", "Later"])
        XCTAssertEqual(try repository.get(id: sooner.id)?.name, "Sooner")

        sooner.isActive = false
        _ = try repository.update(sooner)
        XCTAssertEqual(try repository.get(id: sooner.id)?.isActive, false)

        XCTAssertTrue(try repository.delete(id: sooner.id))
        XCTAssertNil(try repository.get(id: sooner.id))
    }

    func testRepositoryLoadsEmptyDataFileAsEmptyList() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = folder.appending(path: "subscriptions.json")
        let repository = SubscriptionRepository(fileURL: fileURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try Data().write(to: fileURL)
        XCTAssertEqual(try repository.load().count, 0)

        try Data(" \n\t".utf8).write(to: fileURL)
        XCTAssertEqual(try repository.load().count, 0)
    }

    func testFilterSearchesAccountAndCancellationURL() {
        let subscriptions = [
            Subscription(name: "ChatGPT", cancellationURL: "https://chatgpt.com/cancel", accountHint: "personal@example.com"),
            Subscription(name: "Cloud", category: "Storage", accountHint: "family")
        ]

        XCTAssertEqual(SubscriptionFilter.apply(subscriptions, query: "personal").map(\.name), ["ChatGPT"])
        XCTAssertEqual(SubscriptionFilter.apply(subscriptions, query: "cancel").map(\.name), ["ChatGPT"])
        XCTAssertEqual(SubscriptionFilter.apply(subscriptions, query: "family").map(\.name), ["Cloud"])
    }

    func testUpcomingScheduleFiltersByWindowAndStatus() {
        let start = DateFormats.day.date(from: "2026-08-01")!
        let subscriptions = [
            Subscription(name: "Today", nextBillingDate: DateFormats.day.date(from: "2026-08-01")!),
            Subscription(name: "Soon", nextBillingDate: DateFormats.day.date(from: "2026-08-08")!),
            Subscription(name: "Later", nextBillingDate: DateFormats.day.date(from: "2026-08-20")!),
            Subscription(name: "Paused", nextBillingDate: DateFormats.day.date(from: "2026-08-03")!, isActive: false)
        ]

        XCTAssertEqual(
            SubscriptionSchedule.upcoming(subscriptions, from: start, days: 7).map(\.name),
            ["Today", "Soon"]
        )
        XCTAssertEqual(
            SubscriptionSchedule.upcoming(subscriptions, from: start, days: 7, status: .all).map(\.name),
            ["Today", "Paused", "Soon"]
        )
    }
}
