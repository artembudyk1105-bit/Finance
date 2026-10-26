import Foundation

/// Даты в виде строк yyyy-MM-dd / yyyy-MM — удобно группировать и хранить
enum Day {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        return c
    }()

    static let monthsNom = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
    static let monthsGen = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    static let monthsPrep = ["январе", "феврале", "марте", "апреле", "мае", "июне", "июле", "августе", "сентябре", "октябре", "ноябре", "декабре"]
    static let weekdays = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]

    static func string(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }
    static var today: String { string(Date()) }
    static var currentMonth: String { String(today.prefix(7)) }
    static func offset(days: Int) -> String { string(calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()) }

    static func date(_ s: String) -> Date {
        let p = s.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents()
        c.year = p.count > 0 ? p[0] : 2000
        c.month = p.count > 1 ? p[1] : 1
        c.day = p.count > 2 ? p[2] : 1
        c.hour = 12
        return calendar.date(from: c) ?? Date()
    }

    static func year(_ m: String) -> Int { Int(m.prefix(4)) ?? 2000 }
    static func monthIndex(_ m: String) -> Int { Int(m.dropFirst(5).prefix(2)) ?? 1 }
    static func dayOfMonth(_ s: String) -> Int { Int(s.suffix(2)) ?? 1 }

    static func month(year: Int, month: Int) -> String { String(format: "%04d-%02d", year, month) }

    static func addMonths(_ m: String, _ n: Int) -> String {
        let total = year(m) * 12 + (monthIndex(m) - 1) + n
        return month(year: total / 12, month: total % 12 + 1)
    }

    static func daysInMonth(_ m: String) -> Int {
        let d = date(m + "-01")
        return calendar.range(of: .day, in: .month, for: d)?.count ?? 30
    }

    /// 0 = понедельник
    static func firstWeekdayOffset(_ m: String) -> Int {
        let wd = calendar.component(.weekday, from: date(m + "-01")) // 1 = вс
        return (wd + 5) % 7
    }

    static func monthName(_ m: String, withYear: Bool = true) -> String {
        let n = monthsNom[monthIndex(m) - 1]
        return withYear ? "\(n.capitalized) \(year(m))" : n
    }
    static func monthShort(_ m: String) -> String { String(monthsNom[monthIndex(m) - 1].prefix(3)) }
    static func monthPrep(_ m: String) -> String { monthsPrep[monthIndex(m) - 1] }

    static func label(_ s: String) -> String {
        if s == today { return "Сегодня" }
        if s == offset(days: -1) { return "Вчера" }
        let d = date(s)
        let wd = weekdays[calendar.component(.weekday, from: d) - 1]
        return "\(dayOfMonth(s)) \(monthsGen[monthIndex(s) - 1]), \(wd)"
    }

    static var todayTitle: String {
        let d = Date()
        let wd = weekdays[calendar.component(.weekday, from: d) - 1].capitalized
        return "\(wd), \(calendar.component(.day, from: d)) \(monthsGen[calendar.component(.month, from: d) - 1])"
    }
}

enum Fmt {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    static func number(_ v: Double) -> String {
        let a = abs(v)
        formatter.maximumFractionDigits = (a.truncatingRemainder(dividingBy: 1) != 0 && a < 1000) ? 2 : 0
        formatter.minimumFractionDigits = formatter.maximumFractionDigits
        return formatter.string(from: NSNumber(value: a)) ?? "\(Int(a))"
    }

    static func money(_ v: Double, _ currency: String, sign: Bool = false) -> String {
        let s = sign ? (v < 0 ? "−" : "+") : (v < 0 ? "−" : "")
        return s + number(v) + "\u{00a0}" + currency
    }

    static func short(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 { return String(format: a >= 10_000_000 ? "%.0fМ" : "%.1fМ", v / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if a >= 1000 {
            let s = String(format: a >= 10_000 ? "%.0fк" : "%.1fк", v / 1000).replacingOccurrences(of: ".", with: ",")
            return s.replacingOccurrences(of: ",0к", with: "к")
        }
        return String(Int(v.rounded()))
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n = abs(n) % 100
        let n1 = n % 10
        if n > 10 && n < 20 { return many }
        if n1 > 1 && n1 < 5 { return few }
        if n1 == 1 { return one }
        return many
    }
}
