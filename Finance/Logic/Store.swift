import Foundation
import Combine
import SwiftUI

/// Все данные приложения. Хранятся только на устройстве: Documents/finance.json
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var data: AppData
    private var bag = Set<AnyCancellable>()
    private let url: URL

    static let currencies = ["₽", "₴", "₸", "$", "€", "Br", "₾", "сом", "zł", "£"]

    init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("finance.json")
        if let raw = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            data = decoded
        } else {
            data = AppData()
        }
        $data.dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &bag)
    }

    func save() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Удобства

    var settings: AppSettings { data.settings }
    var budget: Double { data.settings.monthlyBudget }
    func money(_ v: Double, sign: Bool = false) -> String { Fmt.money(v, data.settings.currency, sign: sign) }

    func isMandatory(_ category: String) -> Bool {
        data.settings.mandatoryOverride[category] ?? Category.byId(category).mandatory
    }

    // MARK: - Операции

    @discardableResult
    func add(type: TxType, amount: Double, name: String, category: String, day: String = Day.today,
             mandatory: Bool? = nil, source: TxSource = .manual) -> Transaction {
        let tx = Transaction(type: type, amount: abs(amount), name: name.isEmpty ? Category.byId(category).name : name,
                             category: category, day: day,
                             isMandatory: type == .expense ? (mandatory ?? isMandatory(category)) : false,
                             source: source)
        data.transactions.append(tx)
        return tx
    }

    func addFromText(_ text: String, source: TxSource) -> [Transaction] {
        Parser.parse(text).map {
            add(type: $0.type, amount: $0.amount, name: $0.name, category: $0.category, day: Day.offset(days: $0.dayOffset), source: source)
        }
    }

    func update(_ tx: Transaction) {
        if let i = data.transactions.firstIndex(where: { $0.id == tx.id }) { data.transactions[i] = tx }
    }

    @discardableResult
    func remove(_ id: UUID) -> Transaction? {
        guard let i = data.transactions.firstIndex(where: { $0.id == id }) else { return nil }
        return data.transactions.remove(at: i)
    }

    func restore(_ txs: [Transaction]) { data.transactions.append(contentsOf: txs) }

    func transactions(month: String) -> [Transaction] {
        data.transactions.filter { $0.month == month }.sorted(by: Store.newestFirst)
    }

    var recent: [Transaction] { Array(data.transactions.sorted(by: Store.newestFirst).prefix(6)) }

    static func newestFirst(_ a: Transaction, _ b: Transaction) -> Bool {
        a.day != b.day ? a.day > b.day : a.createdAt > b.createdAt
    }

    var months: [String] {
        var set = Set(data.transactions.map { $0.month })
        set.insert(Day.currentMonth)
        return set.sorted()
    }

    // MARK: - Итоги

    func summary(_ month: String) -> MonthSummary {
        var s = MonthSummary(month: month)
        s.list = transactions(month: month)
        for t in s.list {
            if t.type == .income {
                s.income += t.amount
                s.byIncCat[t.category, default: 0] += t.amount
                continue
            }
            s.expense += t.amount
            if t.isMandatory { s.mandatory += t.amount } else { s.optional += t.amount }
            s.byCat[t.category, default: 0] += t.amount
            s.byDay[Day.dayOfMonth(t.day), default: 0] += t.amount
        }
        s.daysTotal = Day.daysInMonth(month)
        let cur = Day.currentMonth
        s.daysPassed = month == cur ? Day.dayOfMonth(Day.today) : (month < cur ? s.daysTotal : 0)
        if month == cur && s.daysPassed > 0 {
            // обязательные обычно разовые, необязательные — экстраполируем по темпу
            s.forecast = s.mandatory + s.optional / Double(s.daysPassed) * Double(s.daysTotal) + pendingRecurring(month)
        } else {
            s.forecast = s.expense
        }
        return s
    }

    func pendingRecurring(_ month: String) -> Double {
        guard month == Day.currentMonth else { return 0 }
        let d = Day.dayOfMonth(Day.today)
        return data.recurring.filter { $0.type == .expense && $0.lastMonth != month && $0.dayOfMonth > d }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Автоматизации

    /// Проводит регулярные платежи, у которых наступил день
    @discardableResult
    func applyRecurring() -> [Transaction] {
        let m = Day.currentMonth, today = Day.dayOfMonth(Day.today)
        var added: [Transaction] = []
        for i in data.recurring.indices where data.recurring[i].lastMonth != m && today >= data.recurring[i].dayOfMonth {
            let r = data.recurring[i]
            let day = min(r.dayOfMonth, Day.daysInMonth(m))
            added.append(add(type: r.type, amount: r.amount, name: r.name, category: r.category,
                             day: m + String(format: "-%02d", day), source: .recurring))
            data.recurring[i].lastMonth = m
        }
        return added
    }

    /// При первом запуске в новом месяце — итоги прошлого в чат ассистента
    func monthRollover() -> String? {
        let cur = Day.currentMonth
        defer { data.lastOpenMonth = cur }
        guard !data.lastOpenMonth.isEmpty, data.lastOpenMonth < cur else { return nil }
        let prev = Day.addMonths(cur, -1)
        guard !data.closedMonths.contains(prev), summary(prev).count > 0 else { return nil }
        data.closedMonths.insert(prev)
        data.chat.append(ChatMessage(isUser: false, text: "📅 Новый месяц! " + Assistant.monthReport(prev, store: self) + "\n\nЗапишите в «Цели» то, что удалось отложить."))
        return prev
    }

    // MARK: - Резервные копии

    func exportJSON() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(data)) ?? Data()
    }

    func importJSON(_ raw: Data) throws {
        data = try JSONDecoder().decode(AppData.self, from: raw)
        save()
    }

    func reset() { data = AppData(); save() }

    // MARK: - Демо

    func seedDemo() {
        func r(_ a: Double, _ b: Double) -> Double { ((a + Double.random(in: 0...1) * (b - a)) / 10).rounded() * 10 }
        let cur = Day.currentMonth, todayD = Day.dayOfMonth(Day.today)
        for back in stride(from: 5, through: 0, by: -1) {
            let m = Day.addMonths(cur, -back)
            let last = back == 0 ? todayD : Day.daysInMonth(m)
            func put(_ d: Int, _ type: TxType, _ amount: Double, _ name: String, _ c: String) {
                if d <= last { add(type: type, amount: amount, name: name, category: c, day: m + String(format: "-%02d", d), source: .demo) }
            }
            put(5, .income, 48000 + r(0, 6000), "Зарплата", "salary")
            put(20, .income, 32000 + r(0, 4000), "Аванс", "salary")
            if Bool.random() { put(Int.random(in: 8...25), .income, r(4000, 15000), "Фриланс-проект", "freelance") }
            put(1, .expense, 30000, "Аренда квартиры", "home")
            put(10, .expense, r(3500, 5500), "Коммуналка", "home")
            put(3, .expense, 600, "Интернет", "phone")
            put(4, .expense, 450, "Мобильная связь", "phone")
            put(7, .expense, 799, "Netflix", "subs")
            put(12, .expense, 299, "Яндекс Плюс", "subs")
            put(2, .expense, 2500, "Спортзал", "sport")
            for d in 1...max(1, last) {
                let p = Double.random(in: 0...1)
                if Double.random(in: 0...1) < 0.45 { put(d, .expense, r(350, 2600), ["Пятёрочка", "ВкусВилл", "Продукты", "Перекрёсток"][d % 4], "food") }
                if Double.random(in: 0...1) < 0.35 { put(d, .expense, r(180, 520), ["Кофе", "Латте", "Обед", "Капучино"][d % 4], "cafe") }
                if Double.random(in: 0...1) < 0.25 { put(d, .expense, r(60, 160), "Метро", "transport") }
                if p < 0.12 { put(d, .expense, r(300, 900), "Такси", "taxi") }
                if Double.random(in: 0...1) < 0.07 { put(d, .expense, r(700, 1800), "Доставка еды", "delivery") }
                if Double.random(in: 0...1) < 0.05 { put(d, .expense, r(800, 4500), ["Кроссовки", "Наушники", "Wildberries"][d % 3], ["clothes", "shopping", "shopping"][d % 3]) }
                if Double.random(in: 0...1) < 0.04 { put(d, .expense, r(500, 1500), "Кино", "fun") }
                if Double.random(in: 0...1) < 0.03 { put(d, .expense, r(300, 1200), "Аптека", "health") }
            }
        }
        if data.settings.monthlyBudget == 0 { data.settings.monthlyBudget = 60000 }
        data.settings.categoryLimits.merge(["cafe": 6000, "taxi": 3000, "delivery": 3000]) { old, _ in old }
        if data.goals.isEmpty {
            data.goals = [Goal(name: "Подушка безопасности", target: 200000, saved: 64000, icon: "🛟"),
                          Goal(name: "Отпуск", target: 120000, saved: 38000, icon: "🏝️")]
        }
        if data.recurring.isEmpty {
            data.recurring = [RecurringPayment(name: "Аренда квартиры", amount: 30000, type: .expense, category: "home", dayOfMonth: 1, lastMonth: cur),
                              RecurringPayment(name: "Netflix", amount: 799, type: .expense, category: "subs", dayOfMonth: 7, lastMonth: cur)]
        }
        save()
    }
}
