import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var month = Day.currentMonth
    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var editing: Transaction?
    @State private var showExport = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Все", expense = "Траты", income = "Поступления", mandatory = "Обязательные", optional = "Необязательные"
        var id: String { rawValue }
    }

    private var items: [Transaction] {
        let q = query.lowercased()
        return store.transactions(month: month).filter { t in
            switch filter {
            case .all: break
            case .expense: if t.type != .expense { return false }
            case .income: if t.type != .income { return false }
            case .mandatory: if !(t.type == .expense && t.isMandatory) { return false }
            case .optional: if !(t.type == .expense && !t.isMandatory) { return false }
            }
            return q.isEmpty || (t.name + " " + t.cat.name).lowercased().contains(q)
        }
    }

    var body: some View {
        let list = items
        let days = Dictionary(grouping: list, by: \.day)
        let order = days.keys.sorted(by: >)
        NavigationStack {
            List {
                Section {
                    MonthSwitcher(month: $month)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases) { f in
                                Button {
                                    Haptics.tap()
                                    withAnimation(.snappy) { filter = f }
                                } label: {
                                    Text(f.rawValue).font(.subheadline)
                                        .padding(.horizontal, 14).padding(.vertical, 7)
                                        .background(filter == f ? Color.primary : Color(.secondarySystemGroupedBackground), in: Capsule())
                                        .foregroundStyle(filter == f ? Color(.systemBackground) : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .plainRow()

                if list.isEmpty {
                    ContentUnavailableView("Нет операций", systemImage: "tray", description: Text("За \(Day.monthName(month)) ничего не найдено"))
                        .plainRow()
                } else {
                    let total = list.reduce(0) { $0 + $1.signedAmount }
                    Text("\(list.count) \(Fmt.plural(list.count, "операция", "операции", "операций")) · итого \(store.money(total, sign: true))")
                        .font(.footnote).foregroundStyle(.secondary).plainRow()
                    ForEach(order, id: \.self) { day in
                        let txs = days[day] ?? []
                        let spent = txs.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
                        Section {
                            ForEach(txs) { tx in
                                TransactionRow(tx: tx)
                                    .onTapGesture { editing = tx }
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            if let r = store.remove(tx.id) {
                                                router.showToast("Удалено: \(r.name)", actionTitle: "Отменить") { store.restore([r]) }
                                            }
                                        } label: { Label("Удалить", systemImage: "trash") }
                                    }
                            }
                        } header: {
                            HStack {
                                Text(Day.label(day))
                                Spacer()
                                if spent > 0 { Text("−" + store.money(spent)) }
                            }
                        }
                    }
                }
                Color.clear.frame(height: 70).plainRow()
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Поиск")
            .navigationTitle("История")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showExport = true } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .sheet(item: $editing) { TransactionEditor(tx: $0) }
            .sheet(isPresented: $showExport) { NavigationStack { ExportView() } }
            .animation(.snappy, value: filter)
        }
    }
}
