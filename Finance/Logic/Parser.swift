import Foundation

struct ParsedItem: Hashable {
    var type: TxType
    var amount: Double
    var name: String
    var category: String
    var dayOffset: Int
}

/// Разбор фраз: «кофе 250 и такси 400», «зарплата 85 тысяч», «вчера аптека пятьсот»
enum Parser {
    static let units: [String: Double] = [
        "ноль": 0, "один": 1, "одна": 1, "одну": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6,
        "семь": 7, "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11, "двенадцать": 12, "тринадцать": 13,
        "четырнадцать": 14, "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19,
        "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50, "шестьдесят": 60, "семьдесят": 70, "восемьдесят": 80,
        "девяносто": 90, "сто": 100, "двести": 200, "триста": 300, "четыреста": 400, "пятьсот": 500, "шестьсот": 600,
        "семьсот": 700, "восемьсот": 800, "девятьсот": 900, "полторы": 1.5, "полтора": 1.5
    ]
    static let multipliers: [String: Double] = [
        "тысяча": 1e3, "тысячи": 1e3, "тысяч": 1e3, "тыс": 1e3, "тыщ": 1e3, "тыщи": 1e3, "штук": 1e3, "к": 1e3, "k": 1e3,
        "миллион": 1e6, "миллиона": 1e6, "миллионов": 1e6, "млн": 1e6, "лям": 1e6, "ляма": 1e6
    ]
    static let currencyWords: Set<String> = [
        "руб", "рублей", "рубля", "рубль", "р", "₽", "грн", "гривен", "гривны", "гривна", "₴", "долларов", "доллара", "доллар",
        "бакс", "баксов", "бакса", "$", "евро", "€", "тенге", "₸", "сом", "рубас", "рубасов", "деревянных"
    ]
    static let fillers: Set<String> = [
        "потратил", "потратила", "потратили", "потрачено", "трата", "траты", "расход", "расходы", "купил", "купила", "купили",
        "покупка", "заплатил", "заплатила", "заплатили", "оплатил", "оплатила", "оплатили", "оплата", "отдал", "отдала", "отдали",
        "на", "за", "в", "во", "и", "а", "еще", "это", "было", "был", "была", "получил", "получила", "получили", "пришло",
        "пришла", "пришел", "поступление", "поступило", "доход", "плюс", "минус", "мне", "сегодня", "вчера", "позавчера",
        "примерно", "около", "где-то", "ну", "так", "вот", "потом", "также", "запиши", "записать", "добавь", "добавить",
        "сумма", "сумму", "стоимость", "стоил", "стоила", "стоили", "ушло", "ушел", "рублей", "рубля", "рубль", "руб", "р", "₽"
    ]
    static let incomeWords = [
        "поступлен", "поступил", "получил", "пришл", "пришел", "доход", "зарплат", "зп ", "аванс", "премия", "премию",
        "кешбэк", "кэшбэк", "кешбек", "кэшбек", "перевели мне", "мне перевел", "мне скинул", "продал", "вернули", "возврат",
        "фриланс", "подработк", "заработал", "дивиденд", "начислил", "начислен", "зачислен", "подарили", "плюс "
    ]

    // MARK: - Публичное API

    static func parse(_ raw: String) -> [ParsedItem] {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let offset = dayOffset(raw)
        let norm = normalizeNumbers(raw)
            .replacingOccurrences(of: ",", with: " , ")
            .replacingOccurrences(of: ";", with: " ; ")
        let words: [String] = norm.split(whereSeparator: { $0.isWhitespace }).map { w in
            var s = String(w)
            while s.hasSuffix("!") || s.hasSuffix("?") { s.removeLast() }
            return s
        }.filter { !$0.isEmpty }

        var idx: [Int] = []
        for (i, w) in words.enumerated() where (amountValue(w) ?? 0) > 0 { idx.append(i) }
        guard !idx.isEmpty else { return [] }

        let lowerRaw = normalize(raw)
        let spendVerb = ["потратил", "купил", "заплатил", "оплатил"].contains { lowerRaw.contains($0) }
        let globalIncome = isIncome(raw) && !spendVerb

        var first = 0
        while first < words.count && (fillers.contains(words[first]) || words[first] == "+") { first += 1 }
        let amountFirst = idx[0] == first

        var segs: [(amount: String, words: [String])] = []
        if amountFirst {
            for (k, p) in idx.enumerated() {
                let end = k + 1 < idx.count ? idx[k + 1] : words.count
                segs.append((words[p], Array(words[(p + 1)..<end])))
            }
        } else {
            for (k, p) in idx.enumerated() {
                let start = k == 0 ? 0 : idx[k - 1] + 1
                segs.append((words[p], Array(words[start..<p])))
            }
            let tail = words[(idx[idx.count - 1] + 1)...].filter { !fillers.contains($0) && !currencyWords.contains($0) && $0 != "," && $0 != ";" }
            if !tail.isEmpty { segs[segs.count - 1].words += tail }
        }

        var result: [ParsedItem] = []
        var lastType: TxType? = nil
        for s in segs {
            guard let amount = amountValue(s.amount), amount > 0 else { continue }
            let segWords = s.words.filter { $0 != "," && $0 != ";" }
            let segText = segWords.joined(separator: " ")
            let type: TxType
            if isIncome(segText) {
                type = .income
            } else if globalIncome && segWords.isEmpty {
                type = .income
            } else if globalIncome && lastType != .expense && !looksExpense(segText) {
                type = .income
            } else {
                type = .expense
            }
            lastType = type
            let category = detectCategory(segText.isEmpty ? raw : segText, type)
            var name = cleanName(segWords)
            if name.isEmpty { name = Category.byId(category).name }
            result.append(ParsedItem(type: type, amount: (amount * 100).rounded() / 100, name: name, category: category, dayOffset: offset))
        }
        return result
    }

    static func detectCategory(_ text: String, _ type: TxType) -> String {
        let t = " " + normalize(text) + " "
        var best: Category? = nil
        var bestLen = 0
        for c in Category.all where c.type == type {
            for k in c.keywords {
                let kk = normalize(k)
                if kk.count > bestLen && containsAtWordStart(t, kk) { best = c; bestLen = kk.count }
            }
        }
        return best?.id ?? (type == .income ? "other_in" : "other")
    }

    static func isIncome(_ text: String) -> Bool {
        if matches(text, "(^|\\s)\\+\\s?\\d") { return true }
        let t = " " + normalize(text) + " "
        return incomeWords.contains { t.contains(normalize($0)) }
    }

    // MARK: - Числа

    /// «две тысячи триста» → «2300», «1 500» → «1500», «2к» → «2000»
    static func normalizeNumbers(_ text: String) -> String {
        var s = " " + normalize(text) + " "
        for _ in 0..<2 { s = replace(s, "(\\d)[ \\u00a0\\u202f](?=\\d{3}(?!\\d))", "$1") }
        s = replace(s, "(\\d+(?:[.,]\\d+)?)\\s?(к|k|тыс\\.?)(?=[\\s,.;!?]|$)") { g in
            let v = (Double(g[1].replacingOccurrences(of: ",", with: ".")) ?? 0) * 1000
            return " " + numString(v) + " "
        }
        s = replace(s, "\\+\\s?(?=\\d)", " плюс ")
        s = replace(s, "([а-яa-z])(\\d)", "$1 $2")
        s = replace(s, "(\\d)([а-я₽€₴₸$])", "$1 $2")

        // токены: слова и разделители
        var toks: [String] = []
        var cur = ""
        let chars = Array(s)
        for (i, ch) in chars.enumerated() {
            let nextIsDigit = i + 1 < chars.count && chars[i + 1].isNumber
            let isSep = ch.isWhitespace || ",;!?".contains(ch) || (ch == "." && !nextIsDigit)
            if isSep {
                if !cur.isEmpty { toks.append(cur); cur = "" }
                toks.append(String(ch))
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { toks.append(cur) }

        var out: [String] = []
        var small = 0.0, total = 0.0, used = false
        func flush() {
            if used { out.append(numString(total + small) + " ") }
            small = 0; total = 0; used = false
        }
        for t in toks {
            if t.allSatisfy({ $0.isWhitespace }) {
                if !used { out.append(t) }
                continue
            }
            let w = t.hasSuffix(".") ? String(t.dropLast()) : t
            if isNumToken(w), let v = Double(w.replacingOccurrences(of: ",", with: ".")) {
                if used && small != 0 && small < 1000 && v >= 1000 { flush(); out.append(" ") }
                if used && small != 0 && v < 1000 && digitsLen(small) <= digitsLen(v) { flush(); out.append(" ") }
                small += v; used = true
                continue
            }
            if let u = units[w] {
                if used && small != 0 && digitsLen(u) >= lastPlace(small) { flush(); out.append(" ") }
                small += u; used = true
                continue
            }
            if let m = multipliers[w], used || w.hasPrefix("тысяч") || w.hasPrefix("миллион") {
                total += (small == 0 ? 1 : small) * m
                small = 0; used = true
                continue
            }
            flush()
            out.append(t)
        }
        flush()
        return out.joined().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Вспомогательное

    static func normalize(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "ё", with: "е") }

    static func dayOffset(_ text: String) -> Int {
        let t = normalize(text)
        if t.contains("позавчера") { return -2 }
        if t.contains("вчера") { return -1 }
        return 0
    }

    static func cleanName(_ words: [String]) -> String {
        let w = words.filter { !fillers.contains($0) && !currencyWords.contains($0) }
        let s = w.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-"))
        guard let f = s.first else { return "" }
        return String(f).uppercased() + s.dropFirst()
    }

    static func looksExpense(_ t: String) -> Bool { detectCategory(t, .expense) != "other" }

    static func amountValue(_ w: String) -> Double? {
        var s = w
        if s.hasSuffix(".") || s.hasSuffix(",") { s.removeLast() }
        guard isNumToken(s) else { return nil }
        return Double(s.replacingOccurrences(of: ",", with: "."))
    }

    static func isNumToken(_ s: String) -> Bool { matches(s, "^\\d+([.,]\\d+)?$") }

    static func numString(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    static func digitsLen(_ n: Double) -> Int { String(Int(n)).count }

    /// Разряд младшей части: 300 → 3, 20 → 2, 5 → 1
    static func lastPlace(_ n: Double) -> Int {
        let v = Int(n) % 1000
        if v % 100 == 0 { return 3 }
        if v % 10 == 0 { return 2 }
        return 1
    }

    static func containsAtWordStart(_ t: String, _ k: String) -> Bool {
        var from = t.startIndex
        while from < t.endIndex, let r = t.range(of: k, range: from..<t.endIndex) {
            if r.lowerBound == t.startIndex || !t[t.index(before: r.lowerBound)].isLetter { return true }
            from = t.index(after: r.lowerBound)
        }
        return false
    }

    static func matches(_ s: String, _ pattern: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    static func replace(_ s: String, _ pattern: String, transform: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            out += transform(groups)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
