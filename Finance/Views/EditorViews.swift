import SwiftUI

/// Добавление / изменение операции
struct TransactionEditor: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    let tx: Transaction?

    @State private var type: TxType = .expense
    @State private var amount = ""
    @State private var name = ""
    @State private var date = Date()
    @State private var category = "other"
    @State private var mandatory = false
    @State private var loaded = false
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Тип", selection: $type) {
                        ForEach(TxType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    TextField("0 \(store.settings.currency)", text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Название, например «кофе»", text: $name)
                        .onSubmit { autoCategory() }
                    DatePicker("Дата", selection: $date, in: ...Date().addingTimeInterval(86400 * 366), displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                    if type == .expense {
                        Toggle(isOn: $mandatory) {
                            VStack(alignment: .leading) {
                                Text("Обязательная трата")
                                Text("Жильё, еда, связь, лечение…").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Категория") {
                    CategoryGrid(type: type, selected: $category)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                if let tx {
                    Section {
                        Button("Удалить операцию", role: .destructive) {
                            if let r = store.remove(tx.id) {
                                router.showToast("Удалено: \(r.name)", actionTitle: "Отменить") { store.restore([r]) }
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(tx == nil ? "Новая операция" : "Операция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tx == nil ? "Добавить" : "Сохранить") { save() }.fontWeight(.semibold).disabled(parsedAmount == nil)
                }
            }
            .onChange(of: type) { _, t in
                if loaded && Category.byId(category).type != t { category = t == .expense ? "other" : "other_in" }
            }
            .onChange(of: category) { _, c in
                if loaded && tx == nil { mandatory = store.isMandatory(c) }
            }
            .onAppear(perform: load)
        }
        .presentationDragIndicator(.visible)
    }

    private var parsedAmount: Double? {
        let v = Double(amount.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
        return (v ?? 0) > 0 ? v : nil
    }

    private func load() {
        guard !loaded else { return }
        if let tx {
            type = tx.type
            amount = Parser.numString(tx.amount)
            name = tx.name
            date = Day.date(tx.day)
            category = tx.category
            mandatory = tx.isMandatory
        } else {
            amountFocused = true
        }
        DispatchQueue.main.async { loaded = true }
    }

    private func autoCategory() {
        guard category == "other" || category == "other_in" else { return }
        category = Parser.detectCategory(name, type)
    }

    private func save() {
        guard let v = parsedAmount else { return }
        autoCategory()
        let finalName = name.trimmingCharacters(in: .whitespaces)
        if var t = tx {
            t.type = type
            t.amount = v
            t.name = finalName.isEmpty ? Category.byId(category).name : finalName
            t.category = category
            t.day = Day.string(date)
            t.isMandatory = type == .expense && mandatory
            store.update(t)
            Haptics.success()
        } else {
            let added = store.add(type: type, amount: v, name: finalName, category: category, day: Day.string(date),
                                  mandatory: type == .expense && mandatory, source: .manual)
            router.announce([added], store: store)
        }
        dismiss()
    }
}

/// Быстрый ввод текстом (можно диктовкой клавиатуры)
struct QuickInputView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let items = Parser.parse(text)
        NavigationStack {
            Form {
                Section {
                    TextField("кофе 250, такси 400", text: $text, axis: .vertical)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                } footer: {
                    Text("Пишите как говорите: «продукты 1 840 и аптека 560», «зарплата 85 тысяч», «вчера кино 900». Можно нажать 🎙 на клавиатуре.")
                }
                if !items.isEmpty {
                    Section("Будет добавлено") {
                        ForEach(items, id: \.self) { it in
                            HStack {
                                Text(Category.byId(it.category).icon)
                                VStack(alignment: .leading) {
                                    Text(it.name)
                                    Text(Category.byId(it.category).name).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(store.money(it.type == .income ? it.amount : -it.amount, sign: true))
                                    .fontWeight(.semibold).foregroundStyle(it.type == .income ? Color.green : Color.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Быстрый ввод")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Добавить", action: add).fontWeight(.semibold).disabled(items.isEmpty) }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        let added = store.addFromText(text, source: .manual)
        guard !added.isEmpty else { return }
        router.announce(added, store: store)
        dismiss()
    }
}
