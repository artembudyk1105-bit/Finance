import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var mode = 0
    @State private var month = Day.currentMonth
    @State private var appear = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("", selection: $mode) {
                        Text("Месяц").tag(0)
                        Text("Год").tag(1)
                    }
                    .pickerStyle(.segmented)
                    MonthSwitcher(month: $month, yearMode: mode == 1)
                    if mode == 0 { monthContent } else { yearContent }
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Статистика")
            .onAppear { replay() }
            .onChange(of: month) { _, _ in replay() }
            .onChange(of: mode) { _, _ in replay() }
        }
    }

    private func replay() {
        appear = 0
        withAnimation(.easeOut(duration: 1.0).delay(0.05)) { appear = 1 }
    }

    // MARK: - Месяц

    @ViewBuilder private var monthContent: some View {
        let s = store.summary(month)
        let p = store.summary(Day.addMonths(month, -1))
        if s.count == 0 {
            ContentUnavailableView("Нет данных", systemImage: "chart.bar", description: Text("За \(Day.monthName(month)) операций нет"))
                .padding(.top, 40)
        } else {
            statGrid(s, p)
            cumulativeCard(s)
            mandatoryCard(s)
            categoriesCard(s)
            heatmapCard(s)
            if !s.byIncCat.isEmpty { incomeCard(s) }
        }
    }

    private func statGrid(_ s: MonthSummary, _ p: MonthSummary) -> some View {
        let dExp: Double? = p.expense > 0 ? s.expense / p.expense - 1 : nil
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Траты", color: .red, value: store.money(s.expense),
                     detail: dExp.map { ($0 > 0 ? "▲ " : "▼ ") + Fmt.percent(abs($0)) + " к прошлому" },
                     detailColor: (dExp ?? 0) > 0 ? .red : .green)
            StatTile(title: "Поступления", color: .green, value: store.money(s.income), detail: p.income > 0 ? "было \(store.money(p.income))" : nil)
            StatTile(title: "Остаток", color: .blue, value: store.money(s.balance, sign: true), detail: s.income > 0 ? "сбережения \(Fmt.percent(s.saveRate))" : nil)
            StatTile(title: "В среднем в день", color: .orange, value: store.money((s.expense / Double(max(s.daysPassed, 1))).rounded()),
                     detail: s.isCurrent ? "прогноз \(store.money(s.forecast.rounded()))" : nil)
        }
    }

    private struct Point: Identifiable {
        let id = UUID()
        let day: Int
        let value: Double
        let series: String
    }

    private func cumulativeCard(_ s: MonthSummary) -> some View {
        let last = s.daysPassed > 0 ? s.daysPassed : s.daysTotal
        var acc = 0.0
        var pts: [Point] = []
        for d in 1...last {
            acc += s.byDay[d, default: 0]
            pts.append(Point(day: d, value: acc * appear, series: "Траты"))
        }
        var forecast: [Point] = []
        if s.isCurrent && s.daysLeft > 0 {
            forecast = [Point(day: last, value: acc * appear, series: "Прогноз"), Point(day: s.daysTotal, value: s.forecast * appear, series: "Прогноз")]
        }
        let B = store.budget
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Динамика трат").font(.headline)
                Spacer()
                Text(B > 0 ? "линия — лимит" : "накопительно").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(pts) { p in
                    AreaMark(x: .value("День", p.day), y: .value("Сумма", p.value))
                        .foregroundStyle(LinearGradient(colors: [Color.pink.opacity(0.35), Color.pink.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("День", p.day), y: .value("Сумма", p.value), series: .value("Ряд", p.series))
                        .foregroundStyle(Color.pink)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                }
                ForEach(forecast) { p in
                    LineMark(x: .value("День", p.day), y: .value("Сумма", p.value), series: .value("Ряд", p.series))
                        .foregroundStyle(Color.pink.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 4]))
                }
                if B > 0 {
                    RuleMark(y: .value("Лимит", B))
                        .foregroundStyle(Color.red.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("лимит \(Fmt.short(B))").font(.caption2).foregroundStyle(.red)
                        }
                }
            }
            .chartXScale(domain: 1...s.daysTotal)
            .chartYAxis { AxisMarks(position: .trailing) { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.short(d)) } }
            } }
            .frame(height: 180)
        }
        .card()
    }

    private func mandatoryCard(_ s: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Обязательные и необязательные").font(.headline)
            GeometryReader { geo in
                let total = max(s.expense, 1)
                HStack(spacing: 2) {
                    Rectangle().fill(Color.blue).frame(width: max(geo.size.width * s.mandatory / total * appear, 0))
                    Rectangle().fill(Color.orange).frame(width: max(geo.size.width * s.optional / total * appear, 0))
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: 26)
            HStack(spacing: 24) {
                legend("Обязательные", .blue, store.money(s.mandatory), Fmt.percent(s.expense > 0 ? s.mandatory / s.expense : 0))
                legend("Необязательные", .orange, store.money(s.optional), Fmt.percent(s.expense > 0 ? s.optional / s.expense : 0))
            }
            if s.optional > 0 {
                Button("Что можно убрать? →") {
                    store.data.chat.append(ChatMessage(isUser: true, text: "Что можно убрать?"))
                    store.data.chat.append(ChatMessage(isUser: false, text: Assistant.cuts(month, store: store)))
                    router.tab = .assistant
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private func legend(_ title: String, _ color: Color, _ value: String, _ pct: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) { Circle().fill(color).frame(width: 9, height: 9); Text(title).font(.footnote).foregroundStyle(.secondary) }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.headline.monospacedDigit())
                Text(pct).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func categoriesCard(_ s: MonthSummary) -> some View {
        let cats = s.categoriesSorted
        let top = s.byCat[cats.first ?? "", default: 1]
        return VStack(alignment: .leading, spacing: 14) {
            HStack { Text("По категориям").font(.headline); Spacer(); Text("\(cats.count)").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 16) {
                Chart(cats, id: \.self) { c in
                    SectorMark(angle: .value("Сумма", s.byCat[c, default: 0] * appear + 0.0001), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(Category.byId(c).color)
                        .cornerRadius(3)
                }
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text("Траты").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.short(s.expense)).font(.headline.bold())
                    }
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cats.prefix(5), id: \.self) { c in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) { Circle().fill(Category.byId(c).color).frame(width: 8, height: 8); Text(Category.byId(c).name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Text(store.money(s.byCat[c, default: 0])).font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                    }
                }
            }
            ForEach(cats, id: \.self) { c in
                let v = s.byCat[c, default: 0]
                let lim = store.settings.categoryLimits[c] ?? 0
                let maxV = max(lim, top)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(Category.byId(c).icon) \(Category.byId(c).name)").font(.subheadline)
                        if !store.isMandatory(c) { MandatoryTag(isMandatory: false) }
                        Spacer()
                        Text(store.money(v) + (lim > 0 ? " / \(Fmt.short(lim))" : "")).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressBar(value: v / maxV, color: lim > 0 && v > lim ? .red : Category.byId(c).color, limit: lim > 0 ? lim / maxV : nil)
                }
            }
        }
        .card()
    }

    private func heatmapCard(_ s: MonthSummary) -> some View {
        let maxV = s.byDay.values.max() ?? 1
        let offset = Day.firstWeekdayOffset(s.month)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Календарь трат").font(.headline); Spacer(); Text("ярче — больше").font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: cols, spacing: 5) {
                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                ForEach(0..<offset, id: \.self) { i in Color.clear.frame(height: 1).id("e\(i)") }
                ForEach(1...s.daysTotal, id: \.self) { d in
                    let v = s.byDay[d, default: 0]
                    let a = v > 0 ? 0.18 + 0.82 * sqrt(v / maxV) : 0
                    let future = s.isCurrent && d > s.daysPassed
                    Text("\(d)").font(.caption2)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(v > 0 ? Color.red.opacity(a * appear) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .foregroundStyle(a > 0.55 && appear > 0.5 ? Color.white : Color.primary)
                        .opacity(future ? 0.35 : 1)
                }
            }
        }
        .card()
    }

    private func incomeCard(_ s: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Источники поступлений").font(.headline)
            ForEach(s.incomeCategoriesSorted, id: \.self) { c in
                HStack {
                    Text("\(Category.byId(c).icon) \(Category.byId(c).name)")
                    Spacer()
                    Text(store.money(s.byIncCat[c, default: 0])).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(.green)
                }
            }
        }
        .card()
    }

    // MARK: - Год

    private struct MonthBar: Identifiable {
        let id = UUID()
        let label: String
        let kind: String
        let value: Double
    }

    @ViewBuilder private var yearContent: some View {
        let y = Day.year(month)
        let months = (1...12).map { Day.month(year: y, month: $0) }.filter { $0 <= Day.currentMonth }
        let sums = months.map { store.summary($0) }
        let active = sums.filter { $0.count > 0 }
        if active.isEmpty {
            ContentUnavailableView("Нет данных", systemImage: "calendar", description: Text("За \(y) год операций нет")).padding(.top, 40)
        } else {
            let inc = sums.reduce(0) { $0 + $1.income }
            let exp = sums.reduce(0) { $0 + $1.expense }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Поступления за год", color: .green, value: store.money(inc))
                StatTile(title: "Траты за год", color: .red, value: store.money(exp))
                StatTile(title: "Накоплено", color: .blue, value: store.money(inc - exp, sign: true), detail: inc > 0 ? Fmt.percent((inc - exp) / inc) + " дохода" : nil)
                StatTile(title: "Траты в месяц", color: .orange, value: store.money((exp / Double(active.count)).rounded()), detail: "в среднем")
            }
            yearBars(sums)
            yearBalance(sums)
            yearBest(active)
            yearCategories(sums)
        }
    }

    private func yearBars(_ sums: [MonthSummary]) -> some View {
        var bars: [MonthBar] = []
        for s in sums {
            bars.append(MonthBar(label: Day.monthShort(s.month), kind: "Поступления", value: s.income * appear))
            bars.append(MonthBar(label: Day.monthShort(s.month), kind: "Траты", value: s.expense * appear))
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Поступления и траты").font(.headline)
            Chart(bars) { b in
                BarMark(x: .value("Месяц", b.label), y: .value("Сумма", b.value))
                    .foregroundStyle(by: .value("Тип", b.kind))
                    .position(by: .value("Тип", b.kind))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(["Поступления": Color.green, "Траты": Color.blue])
            .chartYAxis { AxisMarks(position: .trailing) { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.short(d)) } }
            } }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 200)
        }
        .card()
    }

    private func yearBalance(_ sums: [MonthSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Остаток по месяцам").font(.headline)
            Chart(sums, id: \.month) { s in
                LineMark(x: .value("Месяц", Day.monthShort(s.month)), y: .value("Остаток", s.balance * appear))
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Месяц", Day.monthShort(s.month)), y: .value("Остаток", s.balance * appear))
                    .foregroundStyle(s.balance >= 0 ? Color.green : Color.red)
            }
            .chartYAxis { AxisMarks(position: .trailing) { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.short(d)) } }
            } }
            .frame(height: 140)
        }
        .card()
    }

    private func yearBest(_ active: [MonthSummary]) -> some View {
        let best = active.max { $0.balance < $1.balance }!
        let worst = active.max { $0.expense < $1.expense }!
        return VStack(spacing: 12) {
            HStack {
                Text("🏆")
                VStack(alignment: .leading) { Text("Лучший месяц"); Text(Day.monthName(best.month)).font(.footnote).foregroundStyle(.secondary) }
                Spacer()
                Text(store.money(best.balance, sign: true)).fontWeight(.semibold).foregroundStyle(.green)
            }
            Divider()
            HStack {
                Text("🔥")
                VStack(alignment: .leading) { Text("Больше всего трат"); Text(Day.monthName(worst.month)).font(.footnote).foregroundStyle(.secondary) }
                Spacer()
                Text(store.money(worst.expense)).fontWeight(.semibold)
            }
        }
        .card()
    }

    private func yearCategories(_ sums: [MonthSummary]) -> some View {
        var byCat: [String: Double] = [:]
        for s in sums { for (c, v) in s.byCat { byCat[c, default: 0] += v } }
        let cats = byCat.keys.sorted { byCat[$0, default: 0] > byCat[$1, default: 0] }
        let top = byCat[cats.first ?? "", default: 1]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Категории за год").font(.headline)
            ForEach(cats, id: \.self) { c in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(Category.byId(c).icon) \(Category.byId(c).name)").font(.subheadline)
                        Spacer()
                        Text(store.money(byCat[c, default: 0])).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressBar(value: byCat[c, default: 0] / top, color: Category.byId(c).color)
                }
            }
        }
        .card()
    }
}

struct StatTile: View {
    let title: String
    let color: Color
    let value: String
    var detail: String? = nil
    var detailColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) { Circle().fill(color).frame(width: 8, height: 8); Text(title).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            Text(value).font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail ?? " ").font(.caption).foregroundStyle(detailColor).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
