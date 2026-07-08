import Foundation
import AppKit
import SubSightCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@main
struct SubscriptionLedgerApp: App {
    @StateObject private var store = SubscriptionStore()

    init() {
        AppIconProvider.installApplicationIcon()
        StatusBarController.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1230, maxWidth: .infinity, minHeight: 820, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
        }
    }
}

enum AppIconProvider {
    static func image() -> NSImage? {
        if let url = Bundle.main.url(forResource: "SubSight", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: "SubSight")
    }

    @MainActor
    static func installApplicationIcon() {
        guard let image = image() else {
            return
        }
        NSApplication.shared.applicationIconImage = image
    }
}

enum StatusBarIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let upperArc = NSBezierPath()
            upperArc.lineWidth = 1.8
            upperArc.lineCapStyle = .round
            upperArc.appendArc(
                withCenter: center,
                radius: 6.1,
                startAngle: 28,
                endAngle: 166,
                clockwise: false
            )
            upperArc.stroke()

            let lowerArc = NSBezierPath()
            lowerArc.lineWidth = 1.8
            lowerArc.lineCapStyle = .round
            lowerArc.appendArc(
                withCenter: center,
                radius: 6.1,
                startAngle: 208,
                endAngle: 346,
                clockwise: false
            )
            lowerArc.stroke()

            NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - 1.45,
                    y: center.y - 1.45,
                    width: 2.9,
                    height: 2.9
                )
            )
            .fill()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SubSight"
        return image
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var privacyMode = false
    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()

    func install() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = statusBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = "SubSight"
        }
        item.menu = menu
        statusItem = item
        rebuildMenu()
    }

    func setPrivacyMode(_ isEnabled: Bool) {
        privacyMode = isEnabled
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let openItem = NSMenuItem(title: "打开 SubSight", action: #selector(showApplication), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let subscriptions = loadSubscriptions()
        let active = subscriptions.filter(\.isActive)
        menu.addItem(disabledItem("有效订阅 \(active.count) 个"))

        let upcoming = SubscriptionSchedule.upcoming(subscriptions, days: 30)
        if upcoming.isEmpty {
            menu.addItem(disabledItem("30 天内没有扣费"))
        } else {
            menu.addItem(disabledItem("即将扣费"))
            for subscription in upcoming.prefix(4) {
                let date = subscription.nextBillingDate.formatted(date: .numeric, time: .omitted)
                let amount = privacyCurrency(subscription.amount, code: subscription.currencyCode, privacyMode: privacyMode)
                let item = NSMenuItem(title: "\(date)  \(subscription.name)  \(amount)", action: #selector(selectSubscription(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = subscription.id
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 SubSight", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func loadSubscriptions() -> [Subscription] {
        guard let repository = try? SubscriptionRepository.live() else {
            return []
        }
        return (try? repository.load()) ?? []
    }

    private func statusBarImage() -> NSImage? {
        StatusBarIcon.image()
    }

    @objc private func showApplication() {
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows where window.canBecomeKey || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    @objc private func selectSubscription(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Subscription.ID else {
            return
        }
        showApplication()
        NotificationCenter.default.post(name: .statusBarSubscriptionSelected, object: id)
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}

extension Notification.Name {
    static let statusBarSubscriptionSelected = Notification.Name("SubSightStatusBarSubscriptionSelected")
}

enum DS {
    static let radius: CGFloat = 8
    static let sidebarWidth: CGFloat = 330
    static let contentInset: CGFloat = 26
    static let sidebarInset: CGFloat = 22
    static let sectionGap: CGFloat = 18
    static let componentGap: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let detailLargePanelHeight: CGFloat = 372
    static let divider = Color.white.opacity(0.20)
    static let panelStroke = Color.white.opacity(0.40)
    static let softPanelStroke = Color.white.opacity(0.32)
    static let controlFill = Color.black.opacity(0.075)
    static let controlStroke = Color.white.opacity(0.22)
    static let secondaryText = Color.primary.opacity(0.58)

    static func iconBackground(_ color: Color) -> Color {
        color.opacity(0.12)
    }
}

private struct PrivacyModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var privacyMode: Bool {
        get { self[PrivacyModeKey.self] }
        set { self[PrivacyModeKey.self] = newValue }
    }
}

struct PrivacyText: View {
    @Environment(\.privacyMode) private var privacyMode
    let text: String
    var placeholder = "••••"

    var body: some View {
        Text(privacyMode ? placeholder : text)
    }
}

func privacyCurrency(_ amount: Double, code: String, privacyMode: Bool) -> String {
    privacyMode ? "\(code) ••••" : amount.formatted(.currency(code: code))
}

struct IconHitBox<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = DS.radius
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.clear
            content
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published var subscriptions: [Subscription] = [] {
        didSet {
            guard !isApplyingDiskSnapshot else {
                return
            }
            save()
        }
    }

    private let repository: SubscriptionRepository
    private var isApplyingDiskSnapshot = false
    private var lastKnownFileModificationDate: Date?

    init() {
        repository = (try? SubscriptionRepository.live()) ?? SubscriptionRepository(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "subsight-subscriptions.json"))
        load(allowFallback: true)
    }

    func binding(for id: Subscription.ID) -> Binding<Subscription>? {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: { self.subscriptions[index] },
            set: { self.subscriptions[index] = $0 }
        )
    }

    @discardableResult
    func add(_ subscription: Subscription) -> Subscription.ID {
        subscriptions.append(subscription)
        subscriptions.sort { $0.nextBillingDate < $1.nextBillingDate }
        return subscription.id
    }

    func delete(at offsets: IndexSet) {
        subscriptions.remove(atOffsets: offsets)
    }

    func delete(id: Subscription.ID) {
        subscriptions.removeAll { $0.id == id }
    }

    func setActive(_ isActive: Bool, id: Subscription.ID) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else {
            return
        }
        subscriptions[index].isActive = isActive
    }

    func reloadIfChanged() {
        let currentDate = fileModificationDate()
        guard currentDate != lastKnownFileModificationDate else {
            return
        }
        load(allowFallback: false)
    }

    private func load(allowFallback: Bool) {
        do {
            let snapshot = try applyingAutomaticBillingRollover(to: repository.load())
            applyDiskSnapshot(snapshot)
        } catch {
            if allowFallback {
                applyDiskSnapshot([])
            }
        }
    }

    private func applyingAutomaticBillingRollover(to snapshot: [Subscription]) -> [Subscription] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var rolledSubscriptions = snapshot
        var didRoll = false

        for index in rolledSubscriptions.indices where rolledSubscriptions[index].isActive {
            var safetyLimit = 120
            while rolledSubscriptions[index].isActive,
                  calendar.startOfDay(for: rolledSubscriptions[index].nextBillingDate) < today,
                  safetyLimit > 0 {
                rolledSubscriptions[index].markCurrentPeriodPaid(calendar: calendar)
                safetyLimit -= 1
                didRoll = true
            }
        }

        if didRoll {
            do {
                try repository.save(rolledSubscriptions)
            } catch {
                NSSound.beep()
            }
        }

        return rolledSubscriptions
    }

    private func save() {
        do {
            try repository.save(subscriptions)
            lastKnownFileModificationDate = fileModificationDate()
        } catch {
            NSSound.beep()
        }
    }

    private func applyDiskSnapshot(_ snapshot: [Subscription]) {
        isApplyingDiskSnapshot = true
        subscriptions = snapshot
        isApplyingDiskSnapshot = false
        lastKnownFileModificationDate = fileModificationDate()
    }

    private func fileModificationDate() -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: repository.fileURL.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

}

struct ContentView: View {
    @EnvironmentObject private var store: SubscriptionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Subscription.ID?
    @State private var addSheetRequest: AddSheetRequest?
    @State private var templateSheetRequest: TemplateSheetRequest?
    @State private var overviewDetailKind: OverviewDetailKind?
    @State private var exchangeRates: [String: Double] = ["CNY": 1.0]
    @State private var exchangeUpdatedAt: Date?
    @State private var exchangeFailed = false
    @State private var privacyMode = false

    private var activeSubscriptions: [Subscription] {
        store.subscriptions.filter(\.isActive)
    }

    private var monthlyTotal: Double {
        activeSubscriptions.reduce(0) { total, subscription in
            let cycle = BillingCycle.from(subscription.cycle)
            let monthlyNative = subscription.amount * cycle.monthlyMultiplier
            return total + convertToCNY(monthlyNative, currencyCode: subscription.currencyCode)
        }
    }

    private var categoryBreakdown: SubscriptionBreakdown {
        SubscriptionCalculator.breakdown(
            subscriptions: store.subscriptions,
            baseCurrency: "CNY",
            rates: exchangeRates,
            dimension: .category
        )
    }

    private var paymentBreakdown: SubscriptionBreakdown {
        SubscriptionCalculator.breakdown(
            subscriptions: store.subscriptions,
            baseCurrency: "CNY",
            rates: exchangeRates,
            dimension: .paymentMethod
        )
    }

    private var upcomingSubscriptions: [Subscription] {
        SubscriptionSchedule.upcoming(store.subscriptions, days: 30)
    }

    private var exchangeSubtitle: String {
        if exchangeFailed {
            return "汇率暂不可用，部分金额按原币种估算。"
        }
        if let exchangeUpdatedAt {
            return "按 CNY 折算，汇率更新于 \(exchangeUpdatedAt.formatted(date: .abbreviated, time: .omitted))。"
        }
        return "按 CNY 折算，正在获取最新汇率。"
    }

    var body: some View {
        ZStack {
            AppBackground()

            HStack(spacing: 0) {
                SidebarView(
                    subscriptions: store.subscriptions,
                    exchangeRates: exchangeRates,
                    selection: $selection,
                    privacyMode: $privacyMode,
                    overviewAction: {
                        selection = nil
                    },
                    activeStateAction: setSubscriptionActive,
                    deleteAction: deleteSubscription
                )
                .frame(width: DS.sidebarWidth)

                Rectangle()
                    .fill(DS.divider)
                    .frame(width: 1)

                ZStack(alignment: .top) {
                    Group {
                        if let selection, let binding = store.binding(for: selection) {
                            VStack(spacing: DS.sectionGap) {
                                SubscriptionDetail(
                                    subscription: binding,
                                    overviewAction: {
                                        self.selection = nil
                                    },
                                    enableReminders: {
                                        ReminderScheduler.requestAuthorizationAndSchedule(store.subscriptions)
                                    }
                                )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        } else {
                            VStack(spacing: DS.sectionGap) {
                                DashboardHeader(
                                    activeCount: activeSubscriptions.count,
                                    monthlyTotal: monthlyTotal,
                                    yearlyTotal: monthlyTotal * 12,
                                    subtitle: exchangeSubtitle,
                                    templateAction: {
                                        templateSheetRequest = TemplateSheetRequest()
                                    },
                                    importAction: importCSV,
                                    exportAction: exportCSV,
                                    addAction: {
                                        addSheetRequest = AddSheetRequest()
                                    }
                                )

                                OverviewInsights(
                                    categoryBreakdown: categoryBreakdown,
                                    paymentBreakdown: paymentBreakdown,
                                    upcomingSubscriptions: upcomingSubscriptions,
                                    categoryDetailAction: {
                                        overviewDetailKind = .categoryBreakdown
                                    },
                                    paymentDetailAction: {
                                        overviewDetailKind = .paymentBreakdown
                                    },
                                    upcomingDetailAction: {
                                        overviewDetailKind = .upcoming
                                    }
                                )

                                OverviewWorkspace(
                                    subscriptions: store.subscriptions,
                                    upcomingSubscriptions: upcomingSubscriptions,
                                    addAction: {
                                        addSheetRequest = AddSheetRequest()
                                    },
                                    detailAction: {
                                        overviewDetailKind = .workspace
                                    }
                                )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .padding(.top, 58)
                    .padding(.horizontal, DS.contentInset)
                    .padding(.bottom, DS.contentInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.privacyMode, privacyMode)
        .ignoresSafeArea()
        .sheet(item: $addSheetRequest) { _ in
            NewSubscriptionSheet { newID in
                selection = newID
            }
                .environmentObject(store)
                .frame(width: 560)
                .presentationBackground(.clear)
        }
        .sheet(item: $templateSheetRequest) { _ in
            TemplatePickerSheet { template in
                let subscription = Subscription(
                    name: template.name,
                    amount: 0,
                    currencyCode: template.currencyCode,
                    cycle: template.cycle.rawValue,
                    category: template.category,
                    paymentMethod: "Card",
                    nextBillingDate: .now,
                    notes: "",
                    isActive: true,
                    reminderEnabled: true,
                    reminderLeadDays: 1,
                    cancellationURL: template.cancellationURL
                )
                selection = store.add(subscription)
            }
            .frame(width: 520)
        }
        .sheet(item: $overviewDetailKind) { kind in
            OverviewDetailSheet(
                kind: kind,
                categoryBreakdown: categoryBreakdown,
                paymentBreakdown: paymentBreakdown,
                upcomingSubscriptions: upcomingSubscriptions,
                subscriptions: store.subscriptions
            )
            .frame(width: 760, height: 560)
            .presentationBackground(.clear)
        }
        .onAppear {
            StatusBarController.shared.setPrivacyMode(privacyMode)
            if ProcessInfo.processInfo.arguments.contains("--show-add-sheet") {
                addSheetRequest = AddSheetRequest()
            }
            if ProcessInfo.processInfo.arguments.contains("--select-first-subscription") {
                selection = store.subscriptions.first?.id
            }
        }
        .task {
            await refreshExchangeRates()
        }
        .onChange(of: store.subscriptions) {
            keepValidSelection()
            Task {
                await refreshExchangeRates()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                store.reloadIfChanged()
                keepValidSelection()
            }
        }
        .onChange(of: privacyMode) {
            StatusBarController.shared.setPrivacyMode(privacyMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .statusBarSubscriptionSelected)) { notification in
            guard let id = notification.object as? Subscription.ID else {
                return
            }
            store.reloadIfChanged()
            if store.subscriptions.contains(where: { $0.id == id }) {
                selection = id
            } else {
                NSSound.beep()
            }
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            store.reloadIfChanged()
            keepValidSelection()
        }
        .background(WindowConfigurator())
    }

    private func convertToCNY(_ amount: Double, currencyCode: String) -> Double {
        let code = currencyCode.uppercased()
        guard code != "CNY" else {
            return amount
        }
        guard let rate = exchangeRates[code], rate > 0 else {
            return amount
        }
        return amount / rate
    }

    private func refreshExchangeRates() async {
        let currencies = Array(Set(activeSubscriptions.map { $0.currencyCode.uppercased() } + ["CNY"]))
        do {
            exchangeRates = try await ExchangeRateClient().rates(base: "CNY", quotes: currencies)
            exchangeUpdatedAt = .now
            exchangeFailed = false
        } catch {
            exchangeFailed = true
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "导出 SubSight CSV"
        panel.nameFieldStringValue = "subsight-subscriptions.csv"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.commaSeparatedText]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try SubscriptionCSV.export(store.subscriptions).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSSound.beep()
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.title = "导入 SubSight CSV"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText, .text]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let csv = try String(contentsOf: url, encoding: .utf8)
            let imported = try SubscriptionCSV.import(csv)
            guard !imported.isEmpty else {
                NSSound.beep()
                return
            }
            store.subscriptions.append(contentsOf: imported)
            store.subscriptions.sort { $0.nextBillingDate < $1.nextBillingDate }
            selection = imported.first?.id
        } catch {
            NSSound.beep()
        }
    }

    private func keepValidSelection() {
        if let selection, !store.subscriptions.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    private func deleteSubscription(id: Subscription.ID) {
        if selection == id {
            self.selection = nil
        }
        store.delete(id: id)
    }

    private func setSubscriptionActive(id: Subscription.ID, isActive: Bool) {
        store.setActive(isActive, id: id)
    }
}

enum ReminderScheduler {
    static func requestAuthorizationAndSchedule(_ subscriptions: [Subscription]) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                return
            }
            schedule(subscriptions)
        }
    }

    private static func schedule(_ subscriptions: [Subscription], center: UNUserNotificationCenter = .current()) {
        let identifiers = subscriptions.map { $0.id.uuidString }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for subscription in subscriptions where subscription.isActive && subscription.reminderEnabled {
            guard let reminderDate = Calendar.current.date(
                byAdding: .day,
                value: -max(subscription.reminderLeadDays, 0),
                to: subscription.nextBillingDate
            ), reminderDate > .now else {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = "\(subscription.name) 即将扣费"
            content.body = "\(subscription.amount.formatted(.currency(code: subscription.currencyCode))) · \(BillingCycle.from(subscription.cycle).displayName)"
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let request = UNNotificationRequest(
                identifier: subscription.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            center.add(request)
        }
    }
}

struct AddSheetRequest: Identifiable {
    let id = UUID()
}

struct TemplateSheetRequest: Identifiable {
    let id = UUID()
}

enum OverviewDetailKind: String, Identifiable {
    case categoryBreakdown
    case paymentBreakdown
    case upcoming
    case workspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .categoryBreakdown: return "分类占比"
        case .paymentBreakdown: return "付款方式"
        case .upcoming: return "30 天内扣费"
        case .workspace: return "工作台"
        }
    }

    var systemImage: String {
        switch self {
        case .categoryBreakdown: return "chart.pie"
        case .paymentBreakdown: return "creditcard"
        case .upcoming: return "calendar.badge.clock"
        case .workspace: return "rectangle.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .categoryBreakdown: return .purple
        case .paymentBreakdown: return .blue
        case .upcoming: return .orange
        case .workspace: return .green
        }
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.white.opacity(0.07)
            LinearGradient(
                colors: [
                    Color(red: 0.65, green: 0.78, blue: 0.95).opacity(0.11),
                    Color.clear,
                    Color(red: 0.95, green: 0.72, blue: 0.48).opacity(0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

struct CardBackground: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.10)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.04),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
    }
}

struct SidebarView: View {
    let subscriptions: [Subscription]
    let exchangeRates: [String: Double]
    @Binding var selection: Subscription.ID?
    @Binding var privacyMode: Bool
    let overviewAction: () -> Void
    let activeStateAction: (Subscription.ID, Bool) -> Void
    let deleteAction: (Subscription.ID) -> Void
    @State private var searchText = ""
    @State private var statusFilter = SubscriptionStatusFilter.active
    @State private var sortOrder = SidebarSortOrder.nextBilling
    @State private var showsSearch = false
    @State private var showsFilters = false

    private var filteredSubscriptions: [Subscription] {
        let filtered = SubscriptionFilter.apply(subscriptions, query: searchText, status: statusFilter)
        switch sortOrder {
        case .nextBilling:
            return filtered.sorted { $0.nextBillingDate < $1.nextBillingDate }
        case .monthlyAscending:
            return filtered.sorted {
                monthlyBaseAmount(for: $0) == monthlyBaseAmount(for: $1)
                    ? $0.nextBillingDate < $1.nextBillingDate
                    : monthlyBaseAmount(for: $0) < monthlyBaseAmount(for: $1)
            }
        case .monthlyDescending:
            return filtered.sorted {
                monthlyBaseAmount(for: $0) == monthlyBaseAmount(for: $1)
                    ? $0.nextBillingDate < $1.nextBillingDate
                    : monthlyBaseAmount(for: $0) > monthlyBaseAmount(for: $1)
            }
        }
    }

    private func monthlyBaseAmount(for subscription: Subscription) -> Double {
        let monthlyNative = subscription.amount * BillingCycle.from(subscription.cycle).monthlyMultiplier
        let code = subscription.currencyCode.uppercased()
        guard code != "CNY" else {
            return monthlyNative
        }
        guard let rate = exchangeRates[code], rate > 0 else {
            return monthlyNative
        }
        return monthlyNative / rate
    }

    private var listTitle: String {
        switch sortOrder {
        case .nextBilling: return "即将扣费"
        case .monthlyAscending: return "月均低到高"
        case .monthlyDescending: return "月均高到低"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sectionGap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    AppIconMark(size: 60)

                    Text("SubSight")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }

                Text("看清每一笔周期订阅")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.sidebarInset)
            .padding(.top, 74)

            HStack(spacing: 8) {
                Button(action: overviewAction) {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.grid.2x2")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selection == nil ? .blue : .secondary)
                            .frame(width: 30, height: 30)
                            .background(DS.iconBackground(selection == nil ? .blue : .gray))
                            .clipShape(RoundedRectangle(cornerRadius: DS.radius))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("总览")
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(subscriptions.filter(\.isActive).count) 个有效订阅")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: DS.radius))
                }
                .buttonStyle(.plain)

                SidebarUtilityButton(
                    systemImage: "magnifyingglass",
                    isActive: showsSearch || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    accessibilityLabel: "搜索"
                ) {
                    showsSearch.toggle()
                }
                .popover(isPresented: $showsSearch, arrowEdge: .bottom) {
                    SidebarSearchPopover(searchText: $searchText)
                        .frame(width: 260)
                }

                SidebarUtilityButton(
                    systemImage: "line.3.horizontal.decrease.circle",
                    isActive: showsFilters || statusFilter != .active || sortOrder != .nextBilling,
                    accessibilityLabel: "筛选与排序"
                ) {
                    showsFilters.toggle()
                }
                .popover(isPresented: $showsFilters, arrowEdge: .bottom) {
                    SidebarFilterPopover(statusSelection: $statusFilter, sortSelection: $sortOrder)
                        .frame(width: 280)
                }

                SidebarUtilityButton(
                    systemImage: privacyMode ? "eye.slash.fill" : "eye",
                    isActive: privacyMode,
                    accessibilityLabel: privacyMode ? "关闭隐私模式" : "开启隐私模式"
                ) {
                    privacyMode.toggle()
                }
            }
            .padding(10)
            .background(selection == nil ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
            .contentShape(RoundedRectangle(cornerRadius: DS.radius))
            .padding(.horizontal, 12)

            Text(listTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.sidebarInset)

            if filteredSubscriptions.isEmpty {
                SidebarEmptyState(isFiltering: !subscriptions.isEmpty)
                    .padding(.horizontal, DS.sidebarInset)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(filteredSubscriptions) { subscription in
                            Button {
                                selection = subscription.id
                            } label: {
                                SubscriptionRow(
                                    subscription: subscription,
                                    isSelected: selection == subscription.id,
                                    amountDisplay: amountDisplay(for: subscription)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: DS.radius))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(RoundedRectangle(cornerRadius: DS.radius))
                            .contextMenu {
                                Button(subscription.isActive ? "暂停订阅" : "恢复订阅") {
                                    activeStateAction(subscription.id, !subscription.isActive)
                                }

                                Divider()

                                Button("删除") {
                                    deleteAction(subscription.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, DS.sectionGap)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func amountDisplay(for subscription: Subscription) -> SubscriptionRow.AmountDisplay {
        switch sortOrder {
        case .nextBilling:
            return .native
        case .monthlyAscending, .monthlyDescending:
            return .monthlyBase(monthlyBaseAmount(for: subscription), currencyCode: "CNY")
        }
    }
}

struct AppIconMark: View {
    let size: CGFloat

    private var bundleIcon: NSImage? {
        AppIconProvider.image()
    }

    var body: some View {
        Group {
            if let bundleIcon {
                Image(nsImage: bundleIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.radius)
                        .fill(.regularMaterial)
                    Circle()
                        .stroke(.blue.opacity(0.28), lineWidth: 4)
                        .padding(7)
                    Circle()
                        .trim(from: 0.08, to: 0.78)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-40))
                        .padding(7)
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .offset(x: 9, y: -7)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .accessibilityHidden(true)
    }
}

enum SidebarSortOrder: String, CaseIterable, Identifiable {
    case nextBilling
    case monthlyAscending
    case monthlyDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextBilling: return "扣费日"
        case .monthlyAscending: return "月均低"
        case .monthlyDescending: return "月均高"
        }
    }
}

struct SidebarUtilityButton: View {
    let systemImage: String
    let isActive: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconHitBox(width: 38, height: 34) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .background(isActive ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius)
                    .stroke(isActive ? Color.accentColor.opacity(0.35) : DS.controlStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

struct SidebarSearchPopover: View {
    @Binding var searchText: String

    var body: some View {
        ZStack {
            SheetGlassBackground()

            VStack(alignment: .leading, spacing: 10) {
                Text("搜索")
                    .font(.headline)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("名称、分类、付款方式", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            IconHitBox(width: 22, height: 22, cornerRadius: 5) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("清空搜索")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(DS.controlFill)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius)
                        .stroke(DS.controlStroke, lineWidth: 1)
                )
            }
            .padding(14)
        }
    }
}

struct SidebarFilterPopover: View {
    @Binding var statusSelection: SubscriptionStatusFilter
    @Binding var sortSelection: SidebarSortOrder

    var body: some View {
        ZStack {
            SheetGlassBackground()

            VStack(spacing: 8) {
                SidebarControlLine(title: "状态", systemImage: "checkmark.circle.fill", tint: .green) {
                    StatusFilterControl(selection: $statusSelection)
                }

                Divider()
                    .overlay(DS.divider)

                SidebarControlLine(title: "排序", systemImage: "arrow.up.arrow.down", tint: .blue) {
                    SidebarSortControl(selection: $sortSelection)
                }
            }
            .padding(10)
        }
    }
}

struct SidebarControlLine<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text(title)
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(width: 48, alignment: .leading)

            content
        }
    }
}

struct StatusFilterControl: View {
    @Binding var selection: SubscriptionStatusFilter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SubscriptionStatusFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Text(filter.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == filter ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .center)
                        .contentShape(RoundedRectangle(cornerRadius: DS.radius - 2))
                }
                .buttonStyle(.plain)
                .background(selection == filter ? Color.white.opacity(0.26) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius - 2))
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.controlStroke, lineWidth: 1)
        )
    }
}

struct SidebarSortControl: View {
    @Binding var selection: SidebarSortOrder

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SidebarSortOrder.allCases) { order in
                Button {
                    selection = order
                } label: {
                    Text(order.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == order ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                        .contentShape(RoundedRectangle(cornerRadius: DS.radius - 2))
                }
                .buttonStyle(.plain)
                .background(selection == order ? Color.white.opacity(0.22) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius - 2))
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.controlStroke, lineWidth: 1)
        )
        .help("左侧列表排序：按扣费日期、月均额度正序或月均额度倒序")
    }
}

struct SidebarEmptyState: View {
    var isFiltering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle" : "tray")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            Text(isFiltering ? "没有匹配结果" : "还没有订阅")
                .font(.headline)

            Text(isFiltering ? "换个关键词或筛选条件试试。" : "点击右侧 + 添加第一项，之后这里会按下次扣费日期排序。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.softPanelStroke, lineWidth: 1)
        )
    }
}

struct DashboardHeader: View {
    let activeCount: Int
    let monthlyTotal: Double
    let yearlyTotal: Double
    let subtitle: String
    let templateAction: () -> Void
    let importAction: () -> Void
    let exportAction: () -> Void
    let addAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: DS.sectionGap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("订阅概览")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    HeaderActionButton(icon: "square.grid.2x2", title: "模板", action: templateAction)
                    HeaderActionButton(icon: "tray.and.arrow.down", title: "导入 CSV", action: importAction)
                    HeaderActionButton(icon: "tray.and.arrow.up", title: "导出 CSV", action: exportAction)
                    HeaderActionButton(icon: "plus", title: "添加订阅", action: addAction)
                }
            }

            HStack(spacing: DS.componentGap) {
                MetricTile(icon: "checkmark.seal.fill", title: "有效订阅", value: "\(activeCount)", tint: .green)
                MetricTile(icon: "calendar.badge.clock", title: "预计月支出", value: monthlyTotal, currencyCode: "CNY", tint: .blue)
                MetricTile(icon: "chart.line.uptrend.xyaxis", title: "预计年支出", value: yearlyTotal, currencyCode: "CNY", tint: .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DetailHeader: View {
    let subscription: Subscription
    let overviewAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.sectionGap) {
            VStack(alignment: .leading, spacing: 8) {
                Text("订阅详情")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(subscription.name.isEmpty ? "编辑单个订阅，变更会自动保存。" : "\(subscription.name) · 编辑单项记录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Button(action: overviewAction) {
                Label("返回总览", systemImage: "rectangle.grid.2x2")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("返回总览")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HeaderActionButton: View {
    let icon: String
    let title: String
    var accessibilityTitle: String?
    var showsTitle = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: showsTitle ? 7 : 0) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                if showsTitle {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, showsTitle ? 13 : 0)
            .frame(width: showsTitle ? nil : 44, height: 44)
            .background(CardBackground())
            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius)
                    .stroke(DS.panelStroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.radius))
        }
        .frame(height: 44)
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: DS.radius))
        .accessibilityLabel(accessibilityTitle ?? title)
        .help(accessibilityTitle ?? title)
    }
}

struct MetricTile: View {
    @Environment(\.privacyMode) private var privacyMode
    let icon: String
    let title: String
    let value: String
    let tint: Color

    init(icon: String, title: String, value: String, tint: Color) {
        self.icon = icon
        self.title = title
        self.value = value
        self.tint = tint
    }

    init(icon: String, title: String, value: Double, currencyCode: String, tint: Color) {
        self.icon = icon
        self.title = title
        self.value = value.formatted(.currency(code: currencyCode))
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: DS.componentGap) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(DS.iconBackground(tint))
                .clipShape(RoundedRectangle(cornerRadius: DS.radius))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(privacyMode && title != "有效订阅" ? "••••" : value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.panelStroke, lineWidth: 1)
        )
    }
}

struct OverviewInsights: View {
    let categoryBreakdown: SubscriptionBreakdown
    let paymentBreakdown: SubscriptionBreakdown
    let upcomingSubscriptions: [Subscription]
    let categoryDetailAction: () -> Void
    let paymentDetailAction: () -> Void
    let upcomingDetailAction: () -> Void

    var body: some View {
        VStack(spacing: DS.componentGap) {
            HStack(alignment: .top, spacing: DS.componentGap) {
                BreakdownPanel(title: "分类占比", systemImage: "chart.pie", breakdown: categoryBreakdown, tint: .purple, detailAction: categoryDetailAction)
                BreakdownPanel(title: "付款方式", systemImage: "creditcard", breakdown: paymentBreakdown, tint: .blue, detailAction: paymentDetailAction)
            }

            UpcomingPanel(subscriptions: upcomingSubscriptions, detailAction: upcomingDetailAction)
        }
    }
}

struct OverviewWorkspace: View {
    @Environment(\.privacyMode) private var privacyMode
    let subscriptions: [Subscription]
    let upcomingSubscriptions: [Subscription]
    let addAction: () -> Void
    let detailAction: () -> Void

    private var activeCount: Int {
        subscriptions.filter(\.isActive).count
    }

    private var pausedCount: Int {
        subscriptions.count - activeCount
    }

    var body: some View {
        Panel(title: "工作台", showsMore: subscriptions.count > 1, moreAction: detailAction) {
            if subscriptions.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("还没有订阅")
                        .font(.title3.weight(.semibold))

                    Text("从右上角添加第一项，或通过 subsightctl / OpenClaw 写入订阅。App 会自动同步外部变更。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: addAction) {
                        Label("添加订阅", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: DS.sectionGap) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("订阅状态")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            StatusPill(title: "有效", value: activeCount, tint: .green)
                            StatusPill(title: "暂停", value: pausedCount, tint: .gray)
                            StatusPill(title: "总数", value: subscriptions.count, tint: .blue)
                        }
                    }

                    Divider()
                        .frame(height: 48)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("接下来")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            if upcomingSubscriptions.count > 1 {
                                OverviewOverflowBadge(text: "另有 \(upcomingSubscriptions.count - 1) 项", tint: .orange)
                            }
                        }

                        if let next = upcomingSubscriptions.first {
                            HStack(spacing: 10) {
                                Text(next.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("\(next.nextBillingDate.formatted(date: .abbreviated, time: .omitted)) · \(privacyCurrency(next.amount, code: next.currencyCode, privacyMode: privacyMode))")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                        } else {
                            Text("30 天内没有扣费")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 126, maxHeight: 126, alignment: .topLeading)
    }
}

struct StatusPill: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
}

struct BreakdownPanel: View {
    @Environment(\.privacyMode) private var privacyMode
    let title: String
    let systemImage: String
    let breakdown: SubscriptionBreakdown
    let tint: Color
    let detailAction: () -> Void

    private var visibleItems: [SubscriptionBreakdownItem] {
        guard breakdown.items.count > 5 else {
            return breakdown.items
        }

        let leadingItems = Array(breakdown.items.prefix(4))
        let hiddenItems = breakdown.items.dropFirst(4)
        let hiddenMonthly = hiddenItems.reduce(0) { $0 + $1.monthlyBase }
        let hiddenYearly = hiddenItems.reduce(0) { $0 + $1.yearlyBase }
        let hiddenCount = hiddenItems.reduce(0) { $0 + $1.activeCount }
        let hiddenShare = breakdown.monthlyTotal > 0 ? hiddenMonthly / breakdown.monthlyTotal : 0
        return leadingItems + [
            SubscriptionBreakdownItem(
                name: "其他 \(hiddenItems.count) 项",
                activeCount: hiddenCount,
                monthlyBase: hiddenMonthly,
                yearlyBase: hiddenYearly,
                share: hiddenShare
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PanelHeader(title: title, systemImage: systemImage, tint: tint)

                Spacer()

                if !breakdown.items.isEmpty {
                    OverviewMoreButton(action: detailAction)
                }
            }

            if visibleItems.isEmpty {
                Text("暂无有效订阅")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .center)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(visibleItems) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(item.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(privacyCurrency(item.monthlyBase, code: breakdown.baseCurrency, privacyMode: privacyMode))
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                }

                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.16))
                                        Capsule()
                                            .fill(tint.opacity(0.48))
                                            .frame(width: max(4, proxy.size.width * item.share))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200, alignment: .topLeading)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.panelStroke, lineWidth: 1)
        )
    }
}

struct UpcomingPanel: View {
    let subscriptions: [Subscription]
    let detailAction: () -> Void

    private var previewSubscriptions: [Subscription] {
        Array(subscriptions.prefix(4))
    }

    private var hiddenCount: Int {
        max(0, subscriptions.count - previewSubscriptions.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PanelHeader(title: "30 天内扣费", systemImage: "calendar.badge.clock", tint: .orange)

                Spacer()

                if hiddenCount > 0 {
                    OverviewOverflowBadge(text: "还有 \(hiddenCount) 项", tint: .orange)
                    OverviewMoreButton(action: detailAction)
                }
            }

            if subscriptions.isEmpty {
                Text("近期没有扣费")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
            } else {
                HStack(spacing: 10) {
                    ForEach(previewSubscriptions) { subscription in
                        UpcomingChargeCard(subscription: subscription)
                    }
                }
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160, alignment: .topLeading)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.panelStroke, lineWidth: 1)
        )
    }
}

struct OverviewOverflowBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(DS.iconBackground(tint))
            .clipShape(Capsule())
    }
}

struct OverviewMoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("查看更多", systemImage: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(DS.controlFill)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(DS.controlStroke, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("查看更多")
    }
}

struct UpcomingChargeCard: View {
    @Environment(\.privacyMode) private var privacyMode
    let subscription: Subscription

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                    .background(DS.iconBackground(.orange))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(subscription.nextBillingDate, style: .date)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(subscription.name.isEmpty ? "未命名订阅" : subscription.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(privacyCurrency(subscription.amount, code: subscription.currencyCode, privacyMode: privacyMode))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(DS.controlFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.controlStroke, lineWidth: 1)
        )
    }
}

struct OverviewDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: String?
    let kind: OverviewDetailKind
    let categoryBreakdown: SubscriptionBreakdown
    let paymentBreakdown: SubscriptionBreakdown
    let upcomingSubscriptions: [Subscription]
    let subscriptions: [Subscription]

    private var subtitle: String {
        if let selectedCategory {
            return "\(subscriptionsForCategory(selectedCategory).count) 个订阅"
        }

        switch kind {
        case .categoryBreakdown:
            return "\(categoryBreakdown.items.count) 个分类"
        case .paymentBreakdown:
            return "\(paymentBreakdown.items.count) 种付款方式"
        case .upcoming:
            return "\(upcomingSubscriptions.count) 项 30 天内扣费"
        case .workspace:
            return "\(subscriptions.count) 个订阅"
        }
    }

    var body: some View {
        ZStack {
            SheetGlassBackground()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if selectedCategory != nil {
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                selectedCategory = nil
                            }
                        } label: {
                            IconHitBox(width: 30, height: 30) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(kind.tint)
                            }
                            .background(DS.iconBackground(kind.tint))
                            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                        }
                        .buttonStyle(.plain)
                        .help("返回分类")
                    } else {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(kind.tint)
                            .frame(width: 30, height: 30)
                            .background(DS.iconBackground(kind.tint))
                            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCategory ?? kind.title)
                            .font(.title3.weight(.semibold))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(DS.controlFill)
                            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.radius)
                                    .stroke(DS.controlStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("关闭")
                }
                .padding(18)

                Divider()
                    .overlay(DS.divider)

                ScrollView {
                    VStack(spacing: 10) {
                        detailContent
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch kind {
        case .categoryBreakdown:
            if categoryBreakdown.items.isEmpty {
                OverviewDetailEmptyState(text: "暂无有效订阅")
            } else if let selectedCategory {
                let categorySubscriptions = subscriptionsForCategory(selectedCategory)
                if categorySubscriptions.isEmpty {
                    OverviewDetailEmptyState(text: "这个分类下暂无有效订阅")
                } else {
                    ForEach(categorySubscriptions) { subscription in
                        OverviewSubscriptionDetailRow(subscription: subscription, showsStatus: false)
                    }
                }
            } else {
                ForEach(categoryBreakdown.items) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            selectedCategory = item.name
                        }
                    } label: {
                        OverviewBreakdownDetailRow(item: item, baseCurrency: categoryBreakdown.baseCurrency, tint: kind.tint, showsDisclosure: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .paymentBreakdown:
            if paymentBreakdown.items.isEmpty {
                OverviewDetailEmptyState(text: "暂无有效订阅")
            } else {
                ForEach(paymentBreakdown.items) { item in
                    OverviewBreakdownDetailRow(item: item, baseCurrency: paymentBreakdown.baseCurrency, tint: kind.tint)
                }
            }
        case .upcoming:
            if upcomingSubscriptions.isEmpty {
                OverviewDetailEmptyState(text: "30 天内没有扣费")
            } else {
                ForEach(upcomingSubscriptions) { subscription in
                    OverviewSubscriptionDetailRow(subscription: subscription, showsStatus: false)
                }
            }
        case .workspace:
            if subscriptions.isEmpty {
                OverviewDetailEmptyState(text: "还没有订阅")
            } else {
                ForEach(subscriptions.sorted { $0.nextBillingDate < $1.nextBillingDate }) { subscription in
                    OverviewSubscriptionDetailRow(subscription: subscription, showsStatus: true)
                }
            }
        }
    }

    private func subscriptionsForCategory(_ category: String) -> [Subscription] {
        subscriptions
            .filter { subscription in
                subscription.isActive && normalizedCategory(subscription.category) == category
            }
            .sorted {
                if $0.nextBillingDate == $1.nextBillingDate {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.nextBillingDate < $1.nextBillingDate
            }
    }

    private func normalizedCategory(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Uncategorized" : category
    }
}

struct OverviewBreakdownDetailRow: View {
    @Environment(\.privacyMode) private var privacyMode
    let item: SubscriptionBreakdownItem
    let baseCurrency: String
    let tint: Color
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text("\(item.activeCount) 个有效订阅")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(privacyCurrency(item.monthlyBase, code: baseCurrency, privacyMode: privacyMode))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    Text(item.share.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(tint.opacity(0.52))
                        .frame(width: max(4, proxy.size.width * item.share))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(DS.controlFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.controlStroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: DS.radius))
    }
}

struct OverviewSubscriptionDetailRow: View {
    @Environment(\.privacyMode) private var privacyMode
    let subscription: Subscription
    let showsStatus: Bool

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconBadge(category: subscription.category, isActive: subscription.isActive, size: 34, iconSize: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(subscription.name.isEmpty ? "未命名订阅" : subscription.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    if showsStatus {
                        Text(subscription.isActive ? "有效" : "暂停")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(subscription.isActive ? Color.green : Color.secondary)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background((subscription.isActive ? Color.green : Color.gray).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text("\(subscription.category) · \(BillingCycle.from(subscription.cycle).displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(privacyCurrency(subscription.amount, code: subscription.currencyCode, privacyMode: privacyMode))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(subscription.nextBillingDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(DS.controlFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.controlStroke, lineWidth: 1)
        )
    }
}

struct OverviewDetailEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }
}

struct PanelHeader: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(DS.iconBackground(tint))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct SubscriptionRow: View {
    @Environment(\.privacyMode) private var privacyMode
    enum AmountDisplay {
        case native
        case monthlyBase(Double, currencyCode: String)
    }

    let subscription: Subscription
    let isSelected: Bool
    let amountDisplay: AmountDisplay

    var body: some View {
        HStack(spacing: DS.componentGap) {
            CategoryIconBadge(category: subscription.category, isActive: subscription.isActive, size: 38, iconSize: 17)

            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name.isEmpty ? "未命名订阅" : subscription.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text("\(subscription.category) · \(BillingCycle.from(subscription.cycle).displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(amountText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(secondaryAmountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: DS.radius))
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .opacity(subscription.isActive ? 1 : 0.58)
    }

    private var amountText: String {
        switch amountDisplay {
        case .native:
            return privacyCurrency(subscription.amount, code: subscription.currencyCode, privacyMode: privacyMode)
        case let .monthlyBase(amount, currencyCode):
            return privacyCurrency(amount, code: currencyCode, privacyMode: privacyMode)
        }
    }

    private var secondaryAmountText: String {
        let date = subscription.nextBillingDate.formatted(date: .numeric, time: .omitted)
        switch amountDisplay {
        case .native:
            return date
        case .monthlyBase:
            return "月均 · \(date)"
        }
    }

}

struct CategoryVisual {
    let symbol: String
    let color: Color

    static func resolve(_ category: String) -> CategoryVisual {
        let text = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if text.contains("保险") || text.contains("insurance") { return CategoryVisual(symbol: "shield.lefthalf.filled", color: .teal) }
        if text.contains("住房") || text.contains("房租") || text.contains("房贷") || text.contains("rent") || text.contains("mortgage") { return CategoryVisual(symbol: "house.fill", color: .brown) }
        if text.contains("通信") || text.contains("phone") || text.contains("mobile") || text.contains("手机号") { return CategoryVisual(symbol: "antenna.radiowaves.left.and.right", color: .indigo) }
        if text.contains("ai") { return CategoryVisual(symbol: "sparkles", color: .purple) }
        if text.contains("cloud") || text.contains("云") { return CategoryVisual(symbol: "icloud.fill", color: .cyan) }
        if text.contains("娱乐") || text.contains("video") || text.contains("stream") || text.contains("netflix") { return CategoryVisual(symbol: "play.rectangle.fill", color: .red) }
        if text.contains("会员") || text.contains("vip") { return CategoryVisual(symbol: "crown.fill", color: .orange) }
        if text.contains("music") || text.contains("音乐") { return CategoryVisual(symbol: "music.note", color: .pink) }
        if text.contains("software") || text.contains("app") || text.contains("工具") || text.contains("productivity") { return CategoryVisual(symbol: "square.stack.3d.up.fill", color: .blue) }
        if text.contains("教育") || text.contains("learning") || text.contains("course") { return CategoryVisual(symbol: "graduationcap.fill", color: .mint) }
        if text.contains("阅读") || text.contains("news") || text.contains("书") { return CategoryVisual(symbol: "book.closed.fill", color: .indigo) }
        if text.contains("健康") || text.contains("fitness") || text.contains("gym") { return CategoryVisual(symbol: "heart.fill", color: .pink) }
        if text.contains("账单") || text.contains("utility") { return CategoryVisual(symbol: "doc.text.fill", color: .yellow) }
        if text.contains("交通") || text.contains("parking") || text.contains("car") { return CategoryVisual(symbol: "car.fill", color: .gray) }

        return CategoryVisual(symbol: "creditcard.fill", color: .blue)
    }
}

struct CategoryIconBadge: View {
    let category: String
    let isActive: Bool
    let size: CGFloat
    let iconSize: CGFloat

    private var visual: CategoryVisual {
        CategoryVisual.resolve(category)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.radius)
                .fill((isActive ? visual.color : Color.gray).opacity(isActive ? 0.15 : 0.08))
            Image(systemName: isActive ? visual.symbol : "pause.circle.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? visual.color : .secondary)
        }
        .frame(width: size, height: size)
    }
}

struct SubscriptionDetail: View {
    @Environment(\.privacyMode) private var privacyMode
    @Binding var subscription: Subscription
    let overviewAction: () -> Void
    let enableReminders: () -> Void

    var body: some View {
        VStack(spacing: DS.componentGap) {
            DetailSummaryBand(subscription: subscription, overviewAction: overviewAction)

            Grid(horizontalSpacing: DS.componentGap, verticalSpacing: DS.componentGap) {
                GridRow(alignment: .top) {
                    subscriptionInfoPanel
                        .frame(maxWidth: .infinity, alignment: .top)
                    statusPanel
                        .frame(maxWidth: .infinity, alignment: .top)
                }

                GridRow(alignment: .top) {
                    billingPanel
                        .frame(maxWidth: .infinity, alignment: .top)
                    cancellationAndNotesPanel
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var subscriptionInfoPanel: some View {
        DetailPanel(
            title: "订阅资料",
            systemImage: "pencil",
            tint: .blue,
            subtitle: "搜索、归类和区分不同账号。",
            minHeight: 204
        ) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    DetailControlField(title: "名称") {
                        TextField("ChatGPT / iCloud / Netflix", text: $subscription.name)
                            .textFieldStyle(.plain)
                    }

                    DetailControlField(title: "分类") {
                        TextField("AI / Software / 通信", text: $subscription.category)
                            .textFieldStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    DetailControlField(title: "付款方式") {
                        TextField("Card / Alipay / App Store", text: $subscription.paymentMethod)
                            .textFieldStyle(.plain)
                    }

                    DetailControlField(title: "账号备注") {
                        if privacyMode {
                            Text("已隐藏")
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("Apple ID / 邮箱 / 家庭账号", text: $subscription.accountHint)
                                .textFieldStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var billingPanel: some View {
        DetailPanel(
            title: "计费计划",
            systemImage: "calendar",
            tint: .green,
            subtitle: "驱动总览统计和扣费日程。",
            minHeight: DS.detailLargePanelHeight
        ) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    DetailControlField(title: "金额") {
                        if privacyMode {
                            Text("••••")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            TextField("0", value: $subscription.amount, format: .number)
                                .textFieldStyle(.plain)
                                .monospacedDigit()
                        }
                    }

                    DetailControlField(title: "币种") {
                        GlassMenuPicker(
                            selection: $subscription.currencyCode,
                            options: CurrencyMenuOption.common
                        )
                    }
                }

                HStack(spacing: 10) {
                    DetailControlField(title: "周期") {
                        GlassMenuPicker(
                            selection: $subscription.cycle,
                            options: BillingCycle.allCases.map { MenuPickerOption(id: $0.rawValue, title: $0.displayName) }
                        )
                    }

                    DetailControlField(title: "下次扣费") {
                        DateInputField(date: $subscription.nextBillingDate)
                    }
                }

                DetailControlField(title: "结束日期") {
                    OptionalDateInputField(date: $subscription.paymentEndDate, placeholder: "不限 / YYYY-MM-DD")
                }

                DetailSettingRow(title: "缴费期限", subtitle: paymentTermSubtitle) {
                    HStack(spacing: 8) {
                        Stepper("已 \(subscription.completedPaymentCount)", value: completedPaymentBinding, in: 0...max(subscription.totalPaymentCount ?? 120, 120))
                            .labelsHidden()
                        Text("已 \(subscription.completedPaymentCount)")
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)

                        Divider()
                            .frame(height: 22)

                        Stepper(totalPaymentTitle, value: totalPaymentBinding, in: 0...120)
                            .labelsHidden()
                        Text(totalPaymentTitle)
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                    .fixedSize()
                }
            }
        }
    }

    private var paymentTermSubtitle: String {
        let lastPaid = subscription.paymentHistory.last.map {
            "最近缴费 \(DateFormats.day.string(from: $0.paidDate))"
        }

        if let total = subscription.totalPaymentCount, total > 0 {
            let remaining = max(total - subscription.completedPaymentCount, 0)
            let progress = "已缴 \(subscription.completedPaymentCount)/\(total)，剩余 \(remaining)"
            return [progress, endDateSubtitle, lastPaid].compactMap { $0 }.joined(separator: " · ")
        }

        return ["不限期数", endDateSubtitle, lastPaid].compactMap { $0 }.joined(separator: " · ")
    }

    private var endDateSubtitle: String? {
        subscription.paymentEndDate.map {
            "截至 \(DateFormats.day.string(from: $0))"
        }
    }

    private var totalPaymentTitle: String {
        guard let total = subscription.totalPaymentCount, total > 0 else {
            return "不限"
        }
        return "总 \(total)"
    }

    private var completedPaymentBinding: Binding<Int> {
        Binding(
            get: {
                subscription.completedPaymentCount
            },
            set: { newValue in
                let upperBound = subscription.totalPaymentCount ?? 120
                subscription.completedPaymentCount = min(max(newValue, 0), upperBound)
            }
        )
    }

    private var totalPaymentBinding: Binding<Int> {
        Binding(
            get: {
                subscription.totalPaymentCount ?? 0
            },
            set: { newValue in
                if newValue <= 0 {
                    subscription.totalPaymentCount = nil
                } else {
                    subscription.totalPaymentCount = newValue
                    subscription.completedPaymentCount = min(subscription.completedPaymentCount, newValue)
                }
            }
        )
    }

    private var statusPanel: some View {
        DetailPanel(
            title: "状态与提醒",
            systemImage: "bell.badge",
            tint: .orange,
            subtitle: "有效状态、本地通知和提前时间。",
            minHeight: 204
        ) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    DetailToggleTile(title: "有效", subtitle: "计入统计") {
                        CompactSwitch(isOn: $subscription.isActive, accessibilityLabel: "有效订阅")
                    }

                    DetailToggleTile(title: "提醒", subtitle: "本地通知") {
                        CompactSwitch(
                            isOn: Binding(
                                get: { subscription.reminderEnabled },
                                set: { newValue in
                                    let shouldRequestPermission = newValue && !subscription.reminderEnabled
                                    subscription.reminderEnabled = newValue
                                    if shouldRequestPermission {
                                        enableReminders()
                                    }
                                }
                            ),
                            accessibilityLabel: "扣费前提醒"
                        )
                    }
                }

                DetailSettingRow(title: "提前时间", subtitle: "最多提前 30 天") {
                    Stepper(
                        "提前 \(subscription.reminderLeadDays) 天",
                        value: $subscription.reminderLeadDays,
                        in: 0...30
                    )
                        .disabled(!subscription.reminderEnabled)
                        .foregroundStyle(subscription.reminderEnabled ? .primary : .secondary)
                }
            }
        }
    }

    private var cancellationAndNotesPanel: some View {
        DetailPanel(
            title: "退订与备注",
            systemImage: "note.text",
            tint: .purple,
            subtitle: "管理链接、套餐说明和特殊扣费规则。",
            minHeight: DS.detailLargePanelHeight
        ) {
            VStack(spacing: 10) {
                DetailControlField(title: "退订入口") {
                    if privacyMode {
                        Text("已隐藏")
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("https://...", text: $subscription.cancellationURL)
                            .textFieldStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        openCancellationURL()
                    } label: {
                        Label("打开退订入口", systemImage: "arrow.up.forward")
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .foregroundStyle(cancellationLink == nil ? DS.secondaryText : Color.primary)
                            .background(DS.controlFill)
                            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.radius)
                                    .stroke(DS.controlStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(cancellationLink == nil)

                    Text(subscription.cancellationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未设置链接" : "已保存链接")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(cancellationLink == nil ? DS.secondaryText : Color.green)
                        .frame(width: 88, height: 30)
                        .background(DS.controlFill)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radius)
                                .stroke(DS.controlStroke, lineWidth: 1)
                        )
                }

                ZStack(alignment: .topLeading) {
                    if privacyMode {
                        Text("备注内容已隐藏")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    } else if subscription.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("添加备注，例如套餐内容、优惠到期时间。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .allowsHitTesting(false)
                    }

                    if privacyMode {
                        Color.clear
                    } else {
                        PlainNotesEditor(text: $subscription.notes)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(height: 136, alignment: .topLeading)
                .background(DS.controlFill)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius)
                        .stroke(DS.controlStroke, lineWidth: 1)
                )
            }
        }
    }

    private var cancellationLink: URL? {
        let value = subscription.cancellationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        return URL(string: value)
    }

    private func openCancellationURL() {
        guard let cancellationLink else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(cancellationLink)
    }
}

struct DetailSummaryBand: View {
    let subscription: Subscription
    let overviewAction: () -> Void

    private var monthlyAmount: Double {
        subscription.amount * BillingCycle.from(subscription.cycle).monthlyMultiplier
    }

    private var yearlyAmount: Double {
        monthlyAmount * 12
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            CategoryIconBadge(category: subscription.category, isActive: subscription.isActive, size: 52, iconSize: 22)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(subscription.name.isEmpty ? "未命名订阅" : subscription.name)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .lineLimit(1)

                    Text(subscription.isActive ? "ACTIVE" : "PAUSED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(subscription.isActive ? .green : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background((subscription.isActive ? Color.green : Color.gray).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text("\(display(subscription.category, fallback: "未分类")) · \(display(subscription.paymentMethod, fallback: "未设置付款方式")) · \(BillingCycle.from(subscription.cycle).displayName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                DetailSummaryMetric(title: "月均", value: monthlyAmount, currencyCode: subscription.currencyCode)
                DetailSummaryMetric(title: "年化", value: yearlyAmount, currencyCode: subscription.currencyCode)
                DetailDateMetric(title: "下次扣费", date: subscription.nextBillingDate)
                Button(action: overviewAction) {
                    IconHitBox(width: 52, height: 52) {
                        Image(systemName: "rectangle.grid.2x2")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .background(DS.controlFill)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius)
                        .stroke(DS.controlStroke, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.radius))
                .accessibilityLabel("返回总览")
                .help("返回总览")
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.panelStroke, lineWidth: 1)
        )
    }

    private func display(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct DetailSummaryMetric: View {
    @Environment(\.privacyMode) private var privacyMode
    let title: String
    let value: Double
    let currencyCode: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(privacyCurrency(value, code: currencyCode, privacyMode: privacyMode))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 132, minHeight: 52, alignment: .trailing)
        .background(DS.controlFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.controlStroke, lineWidth: 1)
        )
    }
}

struct DetailDateMetric: View {
    let title: String
    let date: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(date, style: .date)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 106, minHeight: 52, alignment: .trailing)
        .background(DS.controlFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.controlStroke, lineWidth: 1)
        )
    }
}

struct DetailPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    var subtitle: String?
    var minHeight: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(DS.iconBackground(tint))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.panelStroke, lineWidth: 1)
        )
    }
}

struct DetailActionPanel<Content: View, Action: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    var subtitle: String?
    var minHeight: CGFloat?
    @ViewBuilder var action: Action
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(DS.iconBackground(tint))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                action
            }

            content
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.panelStroke, lineWidth: 1)
        )
    }
}

struct DetailControlField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.secondaryText)

            content
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .background(DS.controlFill)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius)
                        .stroke(DS.controlStroke, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MenuPickerOption: Identifiable {
    let id: String
    let title: String
}

enum CurrencyMenuOption {
    static let common = ["CNY", "USD", "HKD", "EUR", "JPY"].map {
        MenuPickerOption(id: $0, title: $0)
    }
}

struct GlassMenuPicker: View {
    @Binding var selection: String
    let options: [MenuPickerOption]

    private var selectedTitle: String {
        options.first { $0.id == selection }?.title ?? selection
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.id
                } label: {
                    if option.id == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityValue(selectedTitle)
    }
}

struct DateInputField: View {
    @Binding var date: Date
    @State private var text = ""
    @State private var isInvalid = false
    @State private var showsCalendar = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("YYYY-MM-DD", text: $text)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .focused($isFocused)
                .onAppear {
                    syncFromDate()
                }
                .onChange(of: date) {
                    if !isFocused {
                        syncFromDate()
                    }
                }
                .onChange(of: isFocused) {
                    if !isFocused {
                        commit()
                    }
                }
                .onSubmit(commit)

            Spacer(minLength: 4)

            if isInvalid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                commit()
                showsCalendar.toggle()
            } label: {
                IconHitBox(width: 24, height: 24, cornerRadius: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.secondaryText)
            .help("打开日期选择")
            .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                DatePicker("选择日期", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
                    .frame(width: 280)
                    .onChange(of: date) {
                        syncFromDate()
                    }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isInvalid ? Color.orange.opacity(0.8) : Color.clear, lineWidth: 1)
                .padding(.vertical, -3)
                .padding(.horizontal, -4)
        )
        .help("输入 YYYY-MM-DD，或点击日历选择")
    }

    private func syncFromDate() {
        text = DateFormats.day.string(from: date)
        isInvalid = false
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            syncFromDate()
            return
        }

        if let parsedDate = DateFormats.day.date(from: trimmed) {
            date = parsedDate
            syncFromDate()
        } else {
            isInvalid = true
        }
    }
}

struct OptionalDateInputField: View {
    @Binding var date: Date?
    let placeholder: String
    @State private var text = ""
    @State private var draftDate = Date()
    @State private var isInvalid = false
    @State private var showsCalendar = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .focused($isFocused)
                .onAppear {
                    syncFromDate()
                }
                .onChange(of: date) {
                    if !isFocused {
                        syncFromDate()
                    }
                }
                .onChange(of: isFocused) {
                    if !isFocused {
                        commit()
                    }
                }
                .onSubmit(commit)

            Spacer(minLength: 4)

            if !text.isEmpty {
                Button {
                    date = nil
                    syncFromDate()
                } label: {
                    IconHitBox(width: 22, height: 22, cornerRadius: 5) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.secondaryText)
                .help("清空结束日期")
            }

            if isInvalid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                commit()
                draftDate = date ?? .now
                showsCalendar.toggle()
            } label: {
                IconHitBox(width: 24, height: 24, cornerRadius: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.secondaryText)
            .help("打开日期选择")
            .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                DatePicker("选择结束日期", selection: $draftDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
                    .frame(width: 280)
                    .onChange(of: draftDate) {
                        date = draftDate
                        syncFromDate()
                    }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isInvalid ? Color.orange.opacity(0.8) : Color.clear, lineWidth: 1)
                .padding(.vertical, -3)
                .padding(.horizontal, -4)
        )
        .help("留空表示不限；也可输入 YYYY-MM-DD 或点击日历选择")
    }

    private func syncFromDate() {
        text = date.map { DateFormats.day.string(from: $0) } ?? ""
        draftDate = date ?? .now
        isInvalid = false
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            date = nil
            syncFromDate()
            return
        }

        if let parsedDate = DateFormats.day.date(from: trimmed) {
            date = parsedDate
            syncFromDate()
        } else {
            isInvalid = true
        }
    }
}

struct DetailSettingRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DS.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(DS.controlFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.controlStroke, lineWidth: 1)
        )
    }
}

struct DetailToggleTile<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DS.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(DS.controlFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.controlStroke, lineWidth: 1)
        )
    }
}

struct CompactSwitch: View {
    @Binding var isOn: Bool
    let accessibilityLabel: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? Color.accentColor.opacity(0.90) : Color.white.opacity(0.16))

                Circle()
                    .fill(Color.white.opacity(isOn ? 0.96 : 0.70))
                    .frame(width: 14, height: 14)
                    .shadow(color: Color.black.opacity(0.14), radius: 2, x: 0, y: 1)
                    .offset(x: isOn ? 18 : 2)
            }
            .frame(width: 34, height: 18)
            .overlay(
                Capsule()
                    .stroke(isOn ? Color.accentColor.opacity(0.35) : DS.controlStroke, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "开启" : "关闭")
        .help(accessibilityLabel)
        .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

struct DetailHero: View {
    @Environment(\.privacyMode) private var privacyMode
    let subscription: Subscription

    private var monthlyAmount: Double {
        subscription.amount * BillingCycle.from(subscription.cycle).monthlyMultiplier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                CategoryIconBadge(category: subscription.category, isActive: subscription.isActive, size: 44, iconSize: 22)

                Spacer()

                Text(subscription.isActive ? "ACTIVE" : "PAUSED")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(subscription.isActive ? .green : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((subscription.isActive ? Color.green : Color.gray).opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(subscription.name.isEmpty ? "未命名订阅" : subscription.name)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text("\(subscription.category) · \(subscription.paymentMethod)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: 5) {
                Text("月均成本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(privacyCurrency(monthlyAmount, code: subscription.currencyCode, privacyMode: privacyMode))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Divider()

            HStack {
                Label {
                    Text(subscription.nextBillingDate, style: .date)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer()

                Text(BillingCycle.from(subscription.cycle).displayName)
                    .font(.callout.weight(.medium))
            }
        }
        .padding(22)
        .frame(width: DS.sidebarWidth, height: 360, alignment: .topLeading)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.panelStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 10)
    }
}

struct Panel<Content: View>: View {
    let title: String
    var showsMore = false
    var moreAction: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)

                Spacer()

                if showsMore, let moreAction {
                    OverviewMoreButton(action: moreAction)
                }
            }
            content
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.panelStroke, lineWidth: 1)
        )
    }
}

struct CompactField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.secondaryText)
            content
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .background(DS.controlFill)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius)
                        .stroke(DS.controlStroke, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            Text("选择一个订阅")
                .font(.title2.weight(.semibold))
            Text("左侧列表会按照扣费日期排序，添加一项后即可查看完整成本结构。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    let onSelect: (SubscriptionTemplate) -> Void

    private var sections: [TemplatePickerSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let templates = SubscriptionTemplates.popular.filter { template in
            guard !query.isEmpty else {
                return true
            }

            return template.name.localizedCaseInsensitiveContains(query)
                || template.category.localizedCaseInsensitiveContains(query)
                || template.currencyCode.localizedCaseInsensitiveContains(query)
                || template.cycle.displayName.localizedCaseInsensitiveContains(query)
        }

        let grouped = Dictionary(grouping: templates, by: \.category)
        return grouped.keys.sorted { left, right in
            let leftIndex = categoryOrder.firstIndex(of: left) ?? Int.max
            let rightIndex = categoryOrder.firstIndex(of: right) ?? Int.max
            if leftIndex == rightIndex {
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
            return leftIndex < rightIndex
        }
        .map { category in
            TemplatePickerSection(
                category: category,
                templates: grouped[category, default: []].sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            )
        }
    }

    private var categoryOrder: [String] {
        ["AI", "Cloud", "娱乐", "音乐", "工具", "通信", "住房", "账单", "保险", "健康", "会员", "教育", "阅读", "交通"]
    }

    var body: some View {
        ZStack {
            SheetGlassBackground()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 42, height: 42)
                        .background(DS.iconBackground(.blue))
                        .clipShape(RoundedRectangle(cornerRadius: DS.radius))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("从模板添加")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("先创建常见订阅，再补充金额和扣费日。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    SheetCloseButton {
                        dismiss()
                    }
                }
                .padding(22)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索模板、分类、周期", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(CardBackground())
                .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius)
                        .stroke(DS.softPanelStroke, lineWidth: 1)
                )
                .padding(.horizontal, 22)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if sections.isEmpty {
                            OverviewDetailEmptyState(text: "没有匹配的模板")
                        } else {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.category)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 2)

                                    ForEach(section.templates) { template in
                                        Button {
                                            onSelect(template)
                                            dismiss()
                                        } label: {
                                            HStack(spacing: 12) {
                                                CategoryIconBadge(category: template.category, isActive: true, size: 34, iconSize: 16)

                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(template.name)
                                                        .font(.system(size: 14, weight: .semibold))
                                                    Text("\(template.currencyCode) · \(template.cycle.displayName)")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }

                                                Spacer()

                                                Image(systemName: "plus.circle")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(CardBackground())
                                            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: DS.radius)
                                                    .stroke(DS.softPanelStroke, lineWidth: 1)
                                            )
                                            .contentShape(RoundedRectangle(cornerRadius: DS.radius))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.bottom, 6)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
            }
        }
    }

}

struct TemplatePickerSection: Identifiable {
    var id: String { category }
    let category: String
    let templates: [SubscriptionTemplate]
}

struct NewSubscriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SubscriptionStore
    let onAdd: (Subscription.ID) -> Void

    @State private var name = ""
    @State private var amount = 0.0
    @State private var currencyCode = "CNY"
    @State private var cycle = BillingCycle.monthly.rawValue
    @State private var category = "Software"
    @State private var paymentMethod = "Card"
    @State private var nextBillingDate = Date()
    @State private var notes = ""
    @State private var reminderEnabled = true
    @State private var reminderLeadDays = 1
    @State private var cancellationURL = ""
    @State private var accountHint = ""

    var body: some View {
        ZStack {
            SheetGlassBackground()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "plus.viewfinder")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 42, height: 42)
                        .background(DS.iconBackground(.blue))
                        .clipShape(RoundedRectangle(cornerRadius: DS.radius))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("添加订阅")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("记录下一次扣费、周期和提醒方式。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    SheetCloseButton {
                        dismiss()
                    }
                }
                .padding(22)

                ScrollView {
                    VStack(spacing: DS.sectionGap) {
                        Panel(title: "基本信息") {
                            VStack(spacing: DS.componentGap) {
                                CompactField(title: "名称") {
                                    TextField("ChatGPT / iCloud / Netflix", text: $name)
                                }
                                CompactField(title: "分类") {
                                    TextField("AI / Software / Entertainment", text: $category)
                                }
                                CompactField(title: "付款方式") {
                                    TextField("Card / Alipay / App Store", text: $paymentMethod)
                                }
                                CompactField(title: "账号备注") {
                                    TextField("Apple ID / 邮箱 / 家庭账号", text: $accountHint)
                                }
                                CompactField(title: "退订入口") {
                                    TextField("https://...", text: $cancellationURL)
                                }
                            }
                        }

                        HStack(alignment: .top, spacing: DS.sectionGap) {
                            Panel(title: "计费") {
                                VStack(spacing: DS.componentGap) {
                                    CompactField(title: "金额") {
                                        TextField("金额", value: $amount, format: .number)
                                            .monospacedDigit()
                                    }
                                    CompactField(title: "币种") {
                                        GlassMenuPicker(
                                            selection: $currencyCode,
                                            options: CurrencyMenuOption.common
                                        )
                                    }
                                    CompactField(title: "周期") {
                                        GlassMenuPicker(
                                            selection: $cycle,
                                            options: BillingCycle.allCases.map { MenuPickerOption(id: $0.rawValue, title: $0.displayName) }
                                        )
                                    }
                                    CompactField(title: "下次扣费") {
                                        DateInputField(date: $nextBillingDate)
                                    }
                                }
                            }

                            Panel(title: "提醒") {
                                VStack(alignment: .leading, spacing: DS.componentGap) {
                                    Toggle("扣费前提醒", isOn: $reminderEnabled)
                                        .toggleStyle(.switch)
                                    Stepper(
                                        "提前 \(reminderLeadDays) 天",
                                        value: $reminderLeadDays,
                                        in: 0...30
                                    )
                                    .disabled(!reminderEnabled)
                                    .foregroundStyle(reminderEnabled ? .primary : .secondary)
                                }
                            }
                        }

                        Panel(title: "备注") {
                            TextEditor(text: $notes)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 92)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.36))
                                .clipShape(RoundedRectangle(cornerRadius: DS.radius))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                }

                Rectangle()
                    .fill(DS.divider)
                    .frame(height: 1)

                HStack {
                    Button("取消") {
                        dismiss()
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button("添加") {
                        addSubscription()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(18)
            }
        }
        .frame(minHeight: 640)
    }

    private func addSubscription() {
        let subscription = Subscription(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            currencyCode: currencyCode,
            cycle: cycle,
            category: category,
            paymentMethod: paymentMethod,
            nextBillingDate: nextBillingDate,
            notes: notes,
            isActive: true,
            reminderEnabled: reminderEnabled,
            reminderLeadDays: reminderLeadDays,
            cancellationURL: cancellationURL.trimmingCharacters(in: .whitespacesAndNewlines),
            accountHint: accountHint.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let id = store.add(subscription)
        onAdd(id)
        dismiss()
    }
}

struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconHitBox(width: 32, height: 32) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .background(CardBackground())
            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius)
                    .stroke(DS.softPanelStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: DS.radius))
        .accessibilityLabel("关闭")
        .help("关闭")
    }
}

struct PlainNotesEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }
    }
}

struct SheetGlassBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            Color.white.opacity(0.08)
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.08),
                    Color.clear,
                    Color.orange.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
