import Foundation

/// Финансовый ассистент: правила работают офлайн; при наличии ключа свободный диалог идёт через Claude
@MainActor
enum Assistant {
    struct Insight: Identifiable {
        enum Level: Int { case danger = 0, warn, info, good }
        enum Action { case budget, cuts }
        let id = UUID()
        var level: Level
        var title: String
        var text: String
        var action: Action? = nil
        var actionTitle: String = ""
    }

    struct Alert {
        var isDanger: Bool
        var text: String
    }

    private static func prevAvg(_ month: String, _ n: Int, _ store: Store, _ f: (MonthSummary) -> Double) -> Double? {
        var vals: [Double] = []
        for i in 1...n {
            let s = store.summary(Day.addMonths(month, -i))
            if s.count > 0 { vals.append(f(s)) }
        }
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }

    private static func days(_ n: Int) -> String { "\(n) " + Fmt.plural(n, "день", "дня", "дней") }

    // MARK: - Инсайты

    static func insights(_ month: String = Day.currentMonth, store: Store) -> [Insight] {
        let s = store.summary(month)
        let st = store.settings
        let B = store.budget
        let M: (Double) -> String = { store.money($0) }
        var out: [Insight] = []

        guard s.count > 0 else {
            return [Insight(level: .info, title: "Начните с первой записи",
                            text: "Зажмите чёрную кнопку с микрофоном и скажите, например: «кофе 250 и такси 400» или «зарплата 85 тысяч».")]
        }

        // 1. Бюджет
        let pending = store.pendingRecurring(month)
        if B > 0 {
            let used = s.expense / B
            let allow = max(B - s.expense - pending, 0) / Double(max(s.daysLeft, 1))
            if used >= 1 {
                out.append(Insight(level: .danger, title: "Лимит превышен на \(M(s.expense - B))",
                                   text: "Потрачено \(M(s.expense)) из \(M(B)). Оставшиеся дни старайтесь закрывать только обязательные траты."))
            } else if s.isCurrent && s.forecast > B * 1.02 {
                out.append(Insight(level: used >= 0.7 ? .danger : .warn, title: "Скоро выйдете за лимит",
                                   text: "По текущему темпу к концу месяца будет \(M(s.forecast.rounded())) — на \(M((s.forecast - B).rounded())) больше бюджета. Чтобы уложиться, тратьте не больше \(M(allow.rounded())) в день."))
            } else if used >= 0.7 {
                out.append(Insight(level: .warn, title: "Использовано \(Fmt.percent(used)) бюджета",
                                   text: "Осталось \(M(B - s.expense))" + (s.isCurrent ? " на \(days(s.daysLeft))." : ".")))
            } else if s.isCurrent {
                out.append(Insight(level: .good, title: "Вы в рамках бюджета",
                                   text: "Можно тратить ~\(M(allow.rounded())) в день до конца месяца. Прогноз: \(M(s.forecast.rounded())) из \(M(B))."))
            }
        } else {
            let avg = prevAvg(month, 3, store) { $0.expense }
            let text = avg.map { "В среднем вы тратите \(M($0.rounded())) в месяц. Попробуйте лимит \(M(($0 * 0.9 / 1000).rounded() * 1000)) — это −10%." }
                ?? "С лимитом я смогу заранее предупреждать, что вы скоро выйдете за рамки."
            out.append(Insight(level: .info, title: "Задайте месячный лимит", text: text, action: .budget, actionTitle: "Настроить лимит"))
        }

        // 2. Лимиты категорий
        for (c, lim) in st.categoryLimits where lim > 0 {
            let v = s.byCat[c, default: 0]
            let name = Category.byId(c).name
            if v >= lim {
                out.append(Insight(level: .danger, title: "\(name): лимит превышен", text: "\(M(v)) из \(M(lim)) (+\(M(v - lim)))."))
            } else if v >= lim * 0.8 {
                out.append(Insight(level: .warn, title: "\(name): \(Fmt.percent(v / lim)) лимита", text: "Осталось \(M(lim - v))."))
            }
        }

        // 3. Необязательные — что урезать
        if s.expense > 0 && s.optional / s.expense > 0.3 {
            let opt = s.categoriesSorted.filter { !store.isMandatory($0) }.prefix(3)
            if !opt.isEmpty {
                let save = opt.reduce(0) { $0 + s.byCat[$1, default: 0] / 2 }
                let list = opt.map { "\(Category.byId($0).name) \(M(s.byCat[$0, default: 0]))" }.joined(separator: ", ")
                out.append(Insight(level: .warn, title: "Необязательные — \(Fmt.percent(s.optional / s.expense)) трат",
                                   text: "Больше всего: \(list). Если сократить их вдвое — сэкономите ~\(M(save.rounded())) в месяц, \(M((save * 12).rounded())) в год.",
                                   action: .cuts, actionTitle: "Что убрать?"))
            }
        }

        // 4. Рост категорий
        for c in s.categoriesSorted {
            guard let a = prevAvg(month, 3, store, { $0.byCat[c, default: 0] }), a > 500 else { continue }
            var v = s.byCat[c, default: 0]
            if s.isCurrent && s.daysPassed > 0 && !store.isMandatory(c) { v = v / Double(s.daysPassed) * Double(s.daysTotal) }
            if v > a * 1.35 && v - a > 1000 {
                out.append(Insight(level: .warn, title: "\(Category.byId(c).name) растёт",
                                   text: "\(s.isCurrent ? "Прогноз" : "Итог") \(M(v.rounded())) против обычных \(M(a.rounded())) (+\(Fmt.percent(v / a - 1)))."))
            }
        }

        // 5. Подписки
        let subs = s.list.filter { $0.category == "subs" }
        if subs.count >= 2 {
            let sum = subs.reduce(0) { $0 + $1.amount }
            out.append(Insight(level: .info, title: "\(subs.count) \(Fmt.plural(subs.count, "подписка", "подписки", "подписок")) — \(M(sum))/мес",
                               text: subs.map(\.name).joined(separator: ", ") + ". Это \(M(sum * 12)) в год. Проверьте, всеми ли вы пользуетесь."))
        }

        // 6. Эффект латте
        let small = s.list.filter { $0.type == .expense && !$0.isMandatory && $0.amount <= 600 && ["cafe", "delivery", "taxi"].contains($0.category) }
        if small.count >= 8 {
            let ss = small.reduce(0) { $0 + $1.amount }
            out.append(Insight(level: .info, title: "Эффект латте: \(small.count) мелких покупок",
                               text: "Кофе, перекусы и такси до 600 сложились в \(M(ss)). За год это ~\(M((ss * 12 / 1000).rounded() * 1000))."))
        }

        // 7. Норма сбережений и правило 50/30/20
        if s.income > 0 {
            let target = (st.savingsTarget > 0 ? st.savingsTarget : 20) / 100
            if s.saveRate >= target {
                out.append(Insight(level: .good, title: "Откладываете \(Fmt.percent(s.saveRate)) дохода",
                                   text: "Отлично, цель \(Fmt.percent(target)) выполнена. Переведите \(M(s.balance.rounded())) в накопления, пока они не «растворились»."))
            } else if !s.isCurrent || s.daysLeft < 10 {
                out.append(Insight(level: s.saveRate < 0 ? .danger : .warn, title: "Норма сбережений \(Fmt.percent(s.saveRate))",
                                   text: "Рекомендуется от \(Fmt.percent(target)). По правилу 50/30/20 из \(M(s.income)): обязательные ≤ \(M((s.income * 0.5).rounded())) (у вас \(M(s.mandatory))), желания ≤ \(M((s.income * 0.3).rounded())) (у вас \(M(s.optional)))."))
            }
        }

        // 8. Необычно крупная трата
        if let last = s.list.first(where: { $0.type == .expense }) {
            let same = store.data.transactions.filter { $0.category == last.category && $0.type == .expense && $0.id != last.id }.map(\.amount).sorted()
            if same.count >= 4 {
                let med = same[same.count / 2]
                if last.amount > med * 3 && last.amount > 1500 {
                    out.append(Insight(level: .info, title: "Необычно крупная трата",
                                       text: "«\(last.name)» — \(M(last.amount)), обычно в категории «\(last.cat.name)» ~\(M(med))."))
                }
            }
        }

        // 9. Дни без лишних трат
        if s.isCurrent && s.daysPassed >= 5 {
            let optDays = Set(s.list.filter { $0.type == .expense && !$0.isMandatory }.map(\.day))
            let free = s.daysPassed - optDays.count
            if free > 0 {
                out.append(Insight(level: .good, title: "\(days(free)) без лишних трат",
                                   text: "Попробуйте челлендж: 2 таких дня в неделю — и необязательные расходы сократятся примерно на 25%."))
            }
        }

        // 10. Цели
        if let monthly = prevAvg(Day.currentMonth, 3, store, { max($0.balance, 0) }), monthly > 0 {
            for g in store.data.goals where g.target > g.saved {
                let n = Int(ceil((g.target - g.saved) / monthly))
                out.append(Insight(level: .info, title: "\(g.icon) \(g.name)",
                                   text: "Осталось \(M(g.target - g.saved)). При вашем темпе сбережений (~\(M(monthly.rounded()))/мес) — примерно \(n) \(Fmt.plural(n, "месяц", "месяца", "месяцев"))."))
            }
        }

        return out.sorted { $0.level.rawValue < $1.level.rawValue }
    }

    static let tips = [
        "Подушка безопасности — 3–6 месяцев обязательных расходов. Начните с одного месяца.",
        "Правило 24 часов: перед необязательной покупкой дороже 3 000 подождите сутки.",
        "Сначала заплатите себе: откладывайте 10–20% в день зарплаты, а не «что останется».",
        "Подписки — тихие траты. Раз в квартал проверяйте, чем реально пользуетесь.",
        "Кредитная карта выгодна, только если гасить её полностью в льготный период.",
        "Крупные цели разбивайте на взносы: 120 000 за год = 10 000 в месяц.",
        "Покупки по списку в продуктовом экономят до 20% чека.",
        "Считайте цену в часах работы: сколько часов стоит эта вещь?",
        "Кэшбэк выгоден, только если вы не тратите больше ради него.",
        "Деньги на цели держите на отдельном счёте с процентом — так их сложнее потратить."
    ]

    static var tipOfDay: String {
        let c = Day.calendar.dateComponents([.day, .month], from: Date())
        return tips[((c.day ?? 1) + (c.month ?? 1)) % tips.count]
    }

    static func headline(store: Store) -> Insight {
        let all = insights(store: store)
        return all.first { $0.level == .danger || $0.level == .warn }
            ?? all.first { $0.level == .good }
            ?? all.first
            ?? Insight(level: .info, title: "Совет дня", text: tipOfDay)
    }

    // MARK: - Сразу после добавления

    static func afterAdd(_ added: [Transaction], store: Store) -> Alert? {
        guard store.settings.alerts else { return nil }
        var result: Alert? = nil
        for tx in added where tx.type == .expense {
            let m = tx.month
            let s = store.summary(m)
            func once(_ key: String, _ a: Alert) {
                if !store.data.alerted.contains(key) { store.data.alerted.insert(key); if result == nil { result = a } }
            }
            if let lim = store.settings.categoryLimits[tx.category], lim > 0 {
                let v = s.byCat[tx.category, default: 0]
                if v >= lim { once("\(m):\(tx.category):100", Alert(isDanger: true, text: "\(tx.cat.name): лимит превышен")) }
                else if v >= lim * 0.8 { once("\(m):\(tx.category):80", Alert(isDanger: false, text: "\(tx.cat.name): осталось \(store.money(lim - v))")) }
            }
            let B = store.budget
            if B > 0 {
                let u = s.expense / B
                if u >= 1 { once("\(m):b100", Alert(isDanger: true, text: "Месячный лимит превышен")) }
                else if u >= 0.9 { once("\(m):b90", Alert(isDanger: true, text: "Осталось \(store.money(B - s.expense)) до лимита")) }
                else if u >= 0.7 { once("\(m):b70", Alert(isDanger: false, text: "Потрачено \(Fmt.percent(u)) бюджета")) }
                else if s.isCurrent && s.forecast > B * 1.05 {
                    once("\(m):fc\(Int(s.forecast / B * 10))", Alert(isDanger: false, text: "Темп выше лимита: прогноз \(store.money(s.forecast.rounded()))"))
                }
            }
        }
        return result
    }

    // MARK: - Тексты

    static func cuts(_ month: String = Day.currentMonth, store: Store) -> String {
        let s = store.summary(month)
        let items = s.categoriesSorted.filter { !store.isMandatory($0) }.prefix(5)
        guard !items.isEmpty else { return "Необязательных трат в этом месяце нет — отличная дисциплина!" }
        var total = 0.0
        var lines: [String] = []
        for (i, c) in items.enumerated() {
            let v = s.byCat[c, default: 0]
            let isSubs = c == "subs"
            let cut = isSubs ? v : v * (i == 0 ? 0.5 : 0.3)
            total += cut
            let how = isSubs ? "лишние подписки" : "на \(i == 0 ? "50%" : "30%")"
            lines.append("• \(Category.byId(c).icon) \(Category.byId(c).name) — \(store.money(v)). Сократить \(how) → −\(store.money(cut.rounded()))/мес")
        }
        return "Где можно сэкономить:\n" + lines.joined(separator: "\n") +
            "\n\nИтого ~\(store.money(total.rounded())) в месяц или \(store.money((total * 12).rounded())) в год. Обязательные траты (жильё, продукты, связь, здоровье) я не трогаю."
    }

    static func monthReport(_ month: String, store: Store) -> String {
        let s = store.summary(month), p = store.summary(Day.addMonths(month, -1))
        let M: (Double) -> String = { store.money($0) }
        var t = "Итоги — \(Day.monthName(month))\n↓ Поступления: \(M(s.income))\n↑ Траты: \(M(s.expense))"
        if p.expense > 0 { t += " (\(s.expense >= p.expense ? "+" : "−")\(Fmt.percent(abs(s.expense / p.expense - 1))) к прошлому месяцу)" }
        t += "\n= Остаток: \(store.money(s.balance, sign: true))"
        if s.income > 0 { t += ", сбережения \(Fmt.percent(s.saveRate))" }
        t += "\nОбязательные: \(M(s.mandatory)) · Необязательные: \(M(s.optional))"
        let top = s.categoriesSorted.prefix(3)
        if !top.isEmpty { t += "\nТоп категорий: " + top.map { "\(Category.byId($0).name) \(M(s.byCat[$0, default: 0]))" }.joined(separator: ", ") }
        if store.budget > 0 {
            t += s.expense <= store.budget ? "\nЛимит \(M(store.budget)) — соблюдён ✅" : "\nЛимит \(M(store.budget)) — превышен на \(M(s.expense - store.budget)) ⚠️"
        }
        return t
    }

    static func localAnswer(_ q: String, store: Store) -> String? {
        let t = Parser.normalize(q)
        let m = Day.currentMonth, s = store.summary(m), B = store.budget
        let M: (Double) -> String = { store.money($0) }
        let pending = store.pendingRecurring(m)
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }

        if has(["убрать", "сократ", "эконом", "урез", "лишн"]) { return cuts(m, store: store) }
        if has(["итог", "отчет", "подыт", "сводк"]) { return monthReport(has(["прошл"]) ? Day.addMonths(m, -1) : m, store: store) }
        if has(["осталось", "остаток", "сколько можно", "могу потратить", "в день"]) {
            guard B > 0 else { return "Остаток месяца: \(store.money(s.balance, sign: true)) (поступления минус траты). Задайте лимит в «Ещё → Лимиты», и я посчитаю дневную норму." }
            let perDay = max(B - s.expense - pending, 0) / Double(max(s.daysLeft, 1))
            return "До лимита осталось \(M(max(B - s.expense, 0))). Это ~\(M(perDay.rounded())) в день на \(days(s.daysLeft))" +
                (pending > 0 ? " (с учётом будущих регулярных платежей \(M(pending)))." : ".")
        }
        if has(["прогноз", "к концу месяца", "хватит"]) {
            var a = "Прогноз трат к концу месяца: \(M(s.forecast.rounded()))"
            if B > 0 { a += s.forecast > B ? " — это больше лимита на \(M((s.forecast - B).rounded()))." : " — укладываетесь в лимит \(M(B))." } else { a += "." }
            return a
        }
        if has(["подписк"]) {
            let subs = s.list.filter { $0.category == "subs" }
            if subs.isEmpty { return "Подписок в этом месяце не найдено." }
            return "Подписки в этом месяце: " + subs.map { "\($0.name) \(M($0.amount))" }.joined(separator: ", ") + ". Всего \(M(subs.reduce(0) { $0 + $1.amount }))."
        }
        if has(["совет", "копить", "грамотн"]) {
            let first = insights(store: store).first.map { "\n\n\($0.title): \($0.text)" } ?? ""
            return "💡 " + tipOfDay + first
        }
        if let c = Category.expenses.first(where: { c in t.contains(Parser.normalize(String(c.name.prefix(5)))) || c.keywords.contains { $0.count > 3 && t.contains($0) } }) {
            let v = s.byCat[c.id, default: 0]
            let avg = prevAvg(m, 3, store) { $0.byCat[c.id, default: 0] }
            return "\(c.icon) \(c.name) в \(Day.monthPrep(m)): \(M(v))" + (avg.map { ". В среднем за прошлые месяцы — \(M($0.rounded()))." } ?? ".")
        }
        if has(["потратил", "трат", "расход"]) { return "В \(Day.monthPrep(m)) потрачено \(M(s.expense)): обязательные \(M(s.mandatory)), необязательные \(M(s.optional))." }
        if has(["заработал", "получил", "доход", "поступ"]) { return "Поступления в \(Day.monthPrep(m)): \(M(s.income))." }
        return nil
    }

    static func answer(_ q: String, store: Store) async -> String {
        let local = localAnswer(q, store: store)
        if !store.settings.apiKey.isEmpty {
            do {
                return try await ClaudeClient.ask(q, store: store)
            } catch {
                return (local.map { $0 + "\n\n" } ?? "") + "⚠️ Claude недоступен: \(error.localizedDescription)"
            }
        }
        return local ?? "Я понимаю вопросы вроде: «сколько осталось», «прогноз», «что убрать», «сколько на кафе», «итоги месяца», «подписки», «совет».\n\nЧтобы задавать любые вопросы — добавьте ключ Claude API в «Ещё → Настройки»."
    }
}
