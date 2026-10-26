import SwiftUI
import UniformTypeIdentifiers

struct MoreView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            List {
                Section("Бюджет") {
                    link(BudgetView(), "Лимиты и бюджет", "slider.horizontal.3", .green,
                         store.budget > 0 ? store.money(store.budget) : "не задан")
                    link(RecurringView(), "Регулярные платежи", "repeat", .indigo, store.data.recurring.isEmpty ? "" : "\(store.data.recurring.count)")
                    link(GoalsView(), "Цели накоплений", "target", .orange, store.data.goals.isEmpty ? "" : "\(store.data.goals.count)")
                }
                Section("Учёт") {
                    link(ArchiveView(), "Архив месяцев", "calendar", .blue, "\(store.months.count)")
                    link(ExportView(), "Скачать смету", "square.and.arrow.up", .teal, "")
                }
                Section {
                    link(SettingsView(), "Настройки", "gearshape.fill", .gray, "")
                    link(HelpView(), "Голос, Siri и кнопка действия", "mic.fill", .purple, "")
                } header: {
                    Text("Приложение")
                } footer: {
                    Text("Все данные хранятся только на этом iPhone. Делайте резервную копию в разделе «Скачать смету».")
                }
            }
            .navigationTitle("Ещё")
        }
    }

    private func link<D: View>(_ dest: D, _ title: String, _ icon: String, _ color: Color, _ value: String) -> some View {
        NavigationLink {
            dest
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Лимиты

struct BudgetView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Лимит в месяц")
                    Spacer()
                    TextField("не задан", value: $store.data.settings.monthlyBudget, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 140)
                    Text(store.settings.currency).foregroundStyle(.secondary)
                }
                Stepper(value: $store.data.settings.savingsTarget, in: 0...90, step: 5) {
                    HStack { Text("Цель сбережений"); Spacer(); Text("\(Int(store.settings.savingsTarget))% дохода").foregroundStyle(.secondary) }
                }
            } header: {
                Text("Месячный бюджет")
            } footer: {
                Text("Ассистент предупредит на 70%, 90% и 100% лимита, а также если темп трат выше нормы.")
            }
            Section {
                ForEach(Category.expenses) { c in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(c.icon)
                            Text(c.name)
                            Spacer()
                            TextField("без лимита", value: limitBinding(c.id), format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                        }
                        Toggle("Обязательная", isOn: mandatoryBinding(c))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Категории: лимит и обязательность")
            } footer: {
                Text("Обязательность влияет на новые операции и на советы «что убрать».")
            }
        }
        .navigationTitle("Лимиты и бюджет")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func limitBinding(_ id: String) -> Binding<Double?> {
        Binding(
            get: { store.data.settings.categoryLimits[id] },
            set: { v in
                if let v, v > 0 { store.data.settings.categoryLimits[id] = v } else { store.data.settings.categoryLimits[id] = nil }
            })
    }

    private func mandatoryBinding(_ c: Category) -> Binding<Bool> {
        Binding(
            get: { store.isMandatory(c.id) },
            set: { v in store.data.settings.mandatoryOverride[c.id] = v == c.mandatory ? nil : v })
    }
}

// MARK: - Регулярные платежи

struct RecurringView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var text = ""
    @State private var day = 1
    @State private var category = "home"

    var body: some View {
        Form {
            Section {
                if store.data.recurring.isEmpty {
                    Text("Нет регулярных платежей").foregroundStyle(.secondary)
                }
                ForEach(store.data.recurring) { r in
                    HStack {
                        Text(Category.byId(r.category).icon)
                        VStack(alignment: .leading) {
                            Text(r.name)
                            Text("каждое \(r.dayOfMonth)-е число").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.money(r.type == .income ? r.amount : -r.amount, sign: true))
                            .foregroundStyle(r.type == .income ? Color.green : Color.primary)
                    }
                }
                .onDelete { store.data.recurring.remove(atOffsets: $0) }
            } footer: {
                Text("Аренда, подписки, связь, зарплата — добавятся автоматически в нужный день каждого месяца.")
            }
            Section("Добавить") {
                TextField("Например: аренда 30000", text: $text)
                    .onChange(of: text) { _, v in if let p = Parser.parse(v).first { category = p.category } }
                Stepper("Число месяца: \(day)", value: $day, in: 1...28)
                Picker("Категория", selection: $category) {
                    ForEach(Category.all) { c in Text("\(c.type == .income ? "＋ " : "")\(c.icon) \(c.name)").tag(c.id) }
                }
                Button("Добавить платёж") { add() }.disabled(Parser.parse(text).isEmpty)
            }
        }
        .navigationTitle("Регулярные")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        guard let p = Parser.parse(text).first else { return }
        let today = Day.dayOfMonth(Day.today)
        store.data.recurring.append(RecurringPayment(name: p.name, amount: p.amount, type: Category.byId(category).type,
                                                     category: category, dayOfMonth: day,
                                                     lastMonth: day <= today ? "" : Day.currentMonth))
        let added = store.applyRecurring()
        text = ""
        Haptics.success()
        router.showToast(added.isEmpty ? "Платёж добавлен" : "Добавлено и проведено за этот месяц")
    }
}

// MARK: - Цели

struct GoalsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var name = ""
    @State private var target: Double?
    @State private var icon = "🎯"
    @State private var depositGoal: Goal?
    @State private var deposit: Double?

    var body: some View {
        Form {
            Section {
                if store.data.goals.isEmpty {
                    Text("Поставьте цель — например, подушку безопасности на 3 месяца расходов.").foregroundStyle(.secondary)
                }
                ForEach(store.data.goals) { g in
                    HStack(spacing: 14) {
                        GoalRing(progress: g.target > 0 ? g.saved / g.target : 0, icon: g.icon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).fontWeight(.semibold)
                            Text("\(store.money(g.saved)) из \(store.money(g.target))").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { deposit = nil; depositGoal = g } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { store.data.goals.remove(atOffsets: $0) }
            }
            Section("Новая цель") {
                TextField("Название (Отпуск, Подушка…)", text: $name)
                TextField("Сумма", value: $target, format: .number).keyboardType(.numberPad)
                TextField("Иконка", text: $icon)
                Button("Создать цель") {
                    guard let t = target, t > 0, !name.isEmpty else { return }
                    store.data.goals.append(Goal(name: name, target: t, saved: 0, icon: icon.isEmpty ? "🎯" : String(icon.prefix(2))))
                    name = ""; target = nil
                    Haptics.success()
                }
                .disabled(name.isEmpty || (target ?? 0) <= 0)
            }
        }
        .navigationTitle("Цели")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Пополнить цель", isPresented: Binding(get: { depositGoal != nil }, set: { if !$0 { depositGoal = nil } })) {
            TextField("Сумма", value: $deposit, format: .number).keyboardType(.decimalPad)
            Button("Отмена", role: .cancel) {}
            Button("Добавить") {
                guard let g = depositGoal, let v = deposit, let i = store.data.goals.firstIndex(where: { $0.id == g.id }) else { return }
                store.data.goals[i].saved = max(0, store.data.goals[i].saved + v)
                Haptics.success()
                if store.data.goals[i].saved >= store.data.goals[i].target { router.showToast("🎉 Цель «\(g.name)» достигнута!") }
            }
        } message: {
            Text(depositGoal.map { "Сколько отложили на «\($0.name)»?" } ?? "")
        }
    }
}

struct GoalRing: View {
    let progress: Double
    let icon: String
    @State private var shown = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: 6)
            Circle().trim(from: 0, to: min(progress, 1) * shown)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(icon)
        }
        .frame(width: 50, height: 50)
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { shown = 1 } }
    }
}

// MARK: - Архив

struct ArchiveView: View {
    @EnvironmentObject var store: Store
    @State private var report: String?

    var body: some View {
        List {
            Section {
                ForEach(store.months.reversed(), id: \.self) { m in
                    let s = store.summary(m)
                    Button { report = Assistant.monthReport(m, store: store) } label: {
                        HStack {
                            Text(s.balance >= 0 ? "📈" : "📉")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Day.monthName(m)).foregroundStyle(.primary)
                                Text("↓ \(store.money(s.income)) · ↑ \(store.money(s.expense))" + (store.budget > 0 && s.expense > store.budget ? " · ⚠️ лимит" : ""))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(store.money(s.balance, sign: true)).fontWeight(.semibold).foregroundStyle(s.balance >= 0 ? Color.green : Color.primary)
                        }
                    }
                }
            } footer: {
                Text("Каждый месяц сохраняется автоматически. Нажмите на месяц, чтобы увидеть итоги.")
            }
        }
        .navigationTitle("Архив месяцев")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { report.map { ReportText(text: $0) } }, set: { report = $0?.text })) { r in
            NavigationStack {
                ScrollView { Text(r.text).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading) }
                    .navigationTitle("Итоги").navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct ReportText: Identifiable {
    var text: String
    var id: String { text }
}

// MARK: - Экспорт

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ExportView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var range: Exporter.Range = .month(Day.currentMonth)
    @State private var share: ShareItem?
    @State private var importing = false
    @State private var importError: String?

    private var ranges: [Exporter.Range] {
        let ms = store.months.reversed()
        let years = Array(Set(ms.map { Day.year($0) })).sorted(by: >)
        return ms.map { Exporter.Range.month($0) } + years.map { Exporter.Range.year($0) } + [.all]
    }

    var body: some View {
        Form {
            Section {
                Picker("Период", selection: $range) {
                    ForEach(ranges, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Формат") {
                row("📗", "Excel", "Сводка, категории и все операции на отдельных листах") { Exporter.excel(range, store) }
                row("📕", "PDF-смета", "Отчёт с выводами ассистента — для печати") { Exporter.pdf(range, store) }
                row("📄", "CSV", "Для Google Таблиц, Numbers и других программ") { Exporter.csv(range, store) }
            }
            Section("Резервная копия") {
                row("💾", "Сохранить резервную копию", "Все данные и настройки в одном файле") { Exporter.backup(store) }
                Button { importing = true } label: { label("📥", "Восстановить из копии", "Заменит текущие данные") }
            }
        }
        .navigationTitle("Скачать смету")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { ActivityView(url: $0.url).presentationDetents([.medium, .large]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                try store.importJSON(Data(contentsOf: url))
                router.showToast("Данные восстановлены")
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Не удалось восстановить", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
    }

    private func row(_ icon: String, _ title: String, _ sub: String, make: @escaping () -> URL) -> some View {
        Button {
            Haptics.tap()
            share = ShareItem(url: make())
        } label: { label(icon, title, sub) }
    }

    private func label(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Text(icon).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(sub).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Настройки

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Основное") {
                Picker("Валюта", selection: $store.data.settings.currency) {
                    ForEach(Store.currencies, id: \.self) { Text($0).tag($0) }
                }
                Picker("Тема", selection: $store.data.settings.theme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
                Picker("Язык распознавания", selection: $store.data.settings.speechLocale) {
                    Text("Русский").tag("ru-RU")
                    Text("Українська").tag("uk-UA")
                    Text("Қазақша").tag("kk-KZ")
                    Text("English").tag("en-US")
                }
                Toggle("Предупреждения о лимитах", isOn: $store.data.settings.alerts)
                Toggle("Уведомления", isOn: $store.data.settings.notifications)
                    .onChange(of: store.data.settings.notifications) { _, on in
                        if on {
                            Task {
                                if await Notifier.requestAccess() { Notifier.scheduleMonthly() } else { store.data.settings.notifications = false }
                            }
                        } else {
                            Notifier.cancelMonthly()
                        }
                    }
            }
            Section {
                SecureField("sk-ant-…", text: $store.data.settings.apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Модель", selection: $store.data.settings.model) {
                    Text("Claude Opus 5.5 — умнее").tag("claude-opus-5-5")
                    Text("Claude Sonnet 5.5 — баланс").tag("claude-sonnet-5-5")
                    Text("Claude Haiku 5.5 — дешевле").tag("claude-haiku-5-5")
                }
            } header: {
                Text("Умный ассистент (Claude)")
            } footer: {
                Text("Без ключа ассистент работает офлайн по встроенным правилам. С ключом — отвечает на любые вопросы. Ключ хранится только на iPhone и отправляется напрямую в Anthropic. Получить: console.anthropic.com → API Keys.")
            }
            Section("Данные") {
                Button("Загрузить демо-данные") { store.seedDemo(); router.showToast("Демо-данные за 6 месяцев загружены") }
                Button("Стереть все данные", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Стереть все операции, цели и настройки? Это нельзя отменить.", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Стереть всё", role: .destructive) { store.reset(); router.showToast("Данные стёрты") }
        }
    }
}

// MARK: - Справка

struct HelpView: View {
    var body: some View {
        List {
            Section("Как говорить") {
                Text("Зажмите чёрную кнопку 🎙, говорите, отпустите.")
                Text("• «кофе 250»\n• «продукты 1840 и аптека 560»\n• «зарплата 85 тысяч»\n• «вчера такси четыреста»\n• «кэшбэк 340», «продал велосипед 12к»")
            }
            Section("Кнопка действия (iPhone 15 Pro и новее)") {
                Text("1. Настройки iPhone → Кнопка действия → «Команда».\n2. Выберите «Финансы» → «Голосовая трата».\n3. Нажмите кнопку — приложение откроется и сразу начнёт слушать; запись остановится сама после паузы.")
            }
            Section("Без открытия приложения — результат в Dynamic Island") {
                Text("1. Откройте «Команды» → «+».\n2. Добавьте «Диктовать текст».\n3. Добавьте действие «Записать трату» (приложение «Финансы») и передайте в него «Продиктованный текст».\n4. Назначьте эту команду на кнопку действия или двойное касание задней панели (Настройки → Универсальный доступ → Касание → Касание задней панели).\nРезультат «Кофе −250 ₽» появится в настоящем Dynamic Island.")
            }
            Section("Siri") {
                Text("«Привет, Siri, голосовая трата в Финансах»\n«Привет, Siri, записать трату в Финансах»")
            }
        }
        .navigationTitle("Голос и Siri")
        .navigationBarTitleDisplayMode(.inline)
    }
}
